# SDRAM port: 32-bit → 16-bit (memory_ctrl / src/memory.v)

Step 4 of PORT_PLAN.md. The whole change is contained to **`src/memory.v`** (`memory_ctrl`,
463 lines). The MSX core talks to it through an 8-bit CPU + VRAM contract; only the physical
SDRAM layer is 32-bit. IcePi Zero SDRAM is 16-bit → narrow the physical layer, keep the contract.

## DON'T TOUCH — the core-side contract (top.v + the whole MSX depend on it)
```
ram_din[7:0], ram_req, ram_write, ram_addr[22:0], ram_dout[7:0], ram_busy   // CPU (8-bit)
vram_din[7:0], vram_write, vram_addr[16:0], vram_dout[15:0]                  // VDP
clk_27m, clk_108m, video_dhclk, video_dlclk, bus_reset_n, bus_rfsh_n
```
MSXnano already duplicates the CPU byte on writes (`ram_din={cpu_dout,cpu_dout}` in top.v) —
same trick as ulx3s_msx, so the write path is already lane-agnostic.

## How it works today (32-bit)
A 32-bit word = 4 bytes, addressed by `sdram_addr[1:0]` (memory.v ~L290):
```
if (sdram_addr[1]==0) { SdrUdq<=~sdram_addr[0]; SdrLdq<=sdram_addr[0]; }   // low  16b half, bytes 0/1
else                  { SdrHUdq<=...;           SdrHLdq<=...; }             // high 16b half, bytes 2/3
```
`O_sdram_dqm[3:0] = {SdrHUdq,SdrHLdq,SdrUdq,SdrLdq}`, `IO_sdram_dq[31:0]`, `SdrDat[31:0]`.

## The 16-bit change-list (edit in place)
A 16-bit word = 2 bytes, addressed by `sdram_addr[0]` alone. `sdram_addr[1]` stops being a
byte-within-word selector and becomes the **lowest word-address (column) bit**.

1. **Ports:** `IO_sdram_dq[31:0]→[15:0]`, `O_sdram_dqm[3:0]→[1:0]`, `O_sdram_addr[10:0]→[12:0]`
   (IcePi SDRAM has 13 address lines; see icepi.lpf).
2. **Datapath reg:** `SdrDat[31:0]→[15:0]`; drive `IO_sdram_dq[15:0]`.
3. **DQM:** delete `SdrHUdq`/`SdrHLdq`; `O_sdram_dqm = {SdrUdq, SdrLdq}`.
4. **Byte lane (L~290):** always `SdrUdq<=~sdram_addr[0]; SdrLdq<=sdram_addr[0];` (drop the
   `sdram_addr[1]==0` branch entirely).
5. **Word address:** the SDRAM now indexes **16-bit words = `sdram_addr[22:1]`** (was `[22:2]`).
   Shift the row/column split up by one bit and widen `SdrAdr`/`O_sdram_addr` accordingly.
6. **Read return:**
   - CPU: `ram_dout <= sdram_addr[0] ? SdrDat[15:8] : SdrDat[7:0];`
   - VRAM: `vram_dout <= SdrDat[15:0];`  (a 16-bit read is now exactly one word — simpler)
7. **Init/hi-Z:** the `SdrDat<=32'hzzzz…`/`32'hffff…` lines become 16-bit.
8. **SdrSize / mode-register:** set for the IcePi chip's geometry (rows/cols/CAS) — copy the
   values from `cheyao/icepi-zero/gateware/sdram/memtest` mode-register setup.

## IcePi SDRAM chip geometry (from cheyao's tested controller — use these exact params)
- **16-bit data** (`sd_data[15:0]`), **13-bit mux address** (`sd_addr[12:0]`), **2 banks**.
- **24-bit word address** (`addr[23:0]`) → 16M words × 16-bit = **32 MB** (plenty for MSX2+).
- **CAS latency 2**, tRCD = 3 cycles, **burst length 1**, single-access writes.
- MODE register = `{3'b000, NO_WRITE_BURST=1, OP_MODE=00, CAS=2, ACCESS=0, BURST=000}`.
- Byte strobes `udsn`/`ldsn` (active-low) select the two lanes; `rw` = write.
- Designed for ~100 MHz; MSXnano runs 108 MHz — verify tRCD/CAS still close (or drop CAS to keep margin).

## Recommended path — Option B: wrap cheyao's controller
Now that we have the chip params, the cleaner route is: use **`cheyao icepi sdram.v`** as the
physical controller (silicon-proven timing on THIS board) and write a small **arbiter** that
maps memory.v's stable `ram_*`/`vram_*` ports onto its `addr[23:0]`/`din`/`dout`/`udsn`/`ldsn`/`rw`
interface + the VDP/refresh slot logic. This keeps you off the Tang-Nano-specific row/col packing
in the current FSM. (Option = edit memory.v's physical layer in place per the change-list above —
lower diff but you inherit the 32-bit chip's address math; more error-prone.)

## Watch-outs
- **Bandwidth halves** (2 bytes/access vs 4). MSX2+ (Z80 + V9958 VRAM) should be fine at 108 MHz —
  NanoMig runs *Amiga* off the same 16-bit chip at 85 MHz — but verify the CPU/VRAM arbiter still
  meets refresh + VDP deadlines.
- **Verify first with cheyao's memtest** on the real board before wiring the core.
- Tune the `clkoutp` 180° SDRAM phase (clk_108p_ecp5.v) for setup/hold once it runs.

## References
- Byte-lane pattern: `ulx3s_msx/src/sdram.v` (`addr[0]` + `dqm={addr[0],~addr[0]}`).
- Tested 16-bit controller + geometry: `cheyao/icepi-zero/gateware/sdram/memtest/sdram.v`.
- IcePi SDRAM pins/width: `fpga/icepi.lpf` and NanoMig `nanomig.lpf`.
