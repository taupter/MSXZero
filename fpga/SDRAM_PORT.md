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

---

## DESIGN DECISION (2026-08-12): narrow memory.v — do NOT wrap NanoMig

Two ways to get 16-bit SDRAM on the IcePi:
- **A. Wrap NanoMig's `sdram` controller** (`src/lattice/nanomig_sdram.sv`). Proven physical
  layer, BUT it's a generic 2-port request/`sync` controller — adopting it means re-building the
  MSX's CPU/VDP **dot-clock interleaving** (the core streams VRAM on `video_dhclk`/`video_dlclk`,
  not on a request/ack handshake). High risk in the MSX-specific timing.
- **B. Narrow `memory.v`'s existing physical layer to 16-bit** (this file's plan). Keeps the
  proven MSX interleaving + command FSM intact; only the data width, byte lane, and row/col/bank
  packing change. **Chosen.** The SDRAM command protocol (tRCD, CAS-2, refresh, auto-precharge)
  is the JEDEC standard both controllers already implement — only the *geometry* differs.

NanoMig is still the value: it **confirms the IcePi's SDRAM geometry** so we don't have to guess.

## CONFIRMED IcePi geometry (from NanoMig, DATA_WIDTH=16, ADDR_BASE=0)
```
16-bit data, 4 banks, 13-bit row, 9-bit col  (word address = byte_addr[.. :1])
  COL (9) = word_addr[8:0]
  RAS (13)= word_addr[21:9]
  BA  (2) = word_addr[23:22]   (NanoMig uses bank 0 only; MSXnano separates CPU/VDP by bank)
  A10 during CAS = auto-precharge
  sd_dqm = byte strobe: addr[0] ? {1'b1, ds} : {ds, 1'b1}
```

## The 13/9 geometry change is NOT needed (resolved 2026-08)
Earlier this doc called the 12-row/8-col draft "under-addressed." **It isn't.** The CPU uses
**bank = `addr[22:21]` (2b) + row = `addr[12:1]` (12b) + col = `addr[20:13]` (8b) = `addr[22:1]`
= the full 8 MB** across all 4 banks; VDP/VRAM sits in bank 3. Since the MSX core only generates a
23-bit address (`ram_addr[22:0]`), it **cannot address beyond 8 MB anyway** — so switching to
13-row/9-col (which would expose the chip's full 32 MB) buys nothing and only risks a subtle
regression. **Verified in sim:** the memtest round-trips across banks 0/1/2 (`0x000100`, `0x200100`,
`0x400100`) plus VRAM in bank 3, no aliasing. So the current geometry is correct for this design;
the 13/9 rewrite was dropped.

<details><summary>The 13/9 mapping (only if a future design needs the full chip)</summary>

| field | now (12/8, 8 MB via banks) | 13/9 (full 32 MB — not needed) |
|---|---|---|
| CPU row (RAS) | `{1'b0, sdram_addr[12:1]}` | `sdram_addr[22:10]` |
| CPU col (CAS) | `sdram_addr[20:13]`→A[7:0] | `sdram_addr[9:1]`→A[8:0], A10=precharge |
| byte lane | `SdrUdq=~addr[0]; SdrLdq=addr[0]` | keep |
</details>

## STATUS (2026-08): memtest PASSES in sim ✅
1. **Simulate — DONE.** `fpga/sim/` (iverilog 4-state; a behavioral 16-bit SDRAM model + a
   testbench that drives the VDP dot-clock cadence). CPU write→read round-trips across byte lanes,
   rows, and high bits (2 MB) with no aliasing; VRAM 8-bit write / 16-bit read works, separate
   bank, no cross-interference. See `sim/README.md`. Two real bugs were found + fixed here:
   - **Read path:** the ECP5 read must latch `IO_sdram_dq` (the bus), NOT `SdrDat` (our tri-stated
     drive reg = Z). Gowin's inferred-SDRAM magic hid this. (So ignore the older `vram_dout <=
     SdrDat[15:0]` note above — the code now reads `IO_sdram_dq`.)
   - **Power-up X-init:** FSM regs needed explicit `= 0` (real FPGA powers up to 0; 4-state sim didn't).
   - The geometry addresses the **full 8 MB** (bank+row+col, verified across banks 0/1/2 + VRAM
     bank 3). The MSX can't address more, so the 13/9 rewrite is **not needed** (see section below).
2. **Frame dump** (still TODO): boot BIOS in sim, dump VRAM → PNG; the MSX logo would confirm the
   whole VDP↔SDRAM↔core path.
3. **Hardware** (board-only): SDRAM read-capture phase / CPHASE tuning is the last step — see `BRINGUP.md` stage 4.
