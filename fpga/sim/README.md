# SDRAM bring-up simulation

Verifies `memory_ctrl` (`../src/memory.v`) against a behavioral SDRAM model, so the
16-bit ECP5 read path + geometry can be checked before hardware.

## Run
```
cd fpga
OSS=/path/to/oss-cad-suite; export PATH="$OSS/bin:$PATH"
iverilog -g2012 -DECP5 -DSIM_FAST_INIT -o sim/tb sim/tb_memory.v sim/sdram_model.v src/memory.v
vvp sim/tb
```
Use **iverilog** (4-state) — the SDRAM data bus is tri-state (`inout`), which Verilator's
2-state model collapses to 0. `-DSIM_FAST_INIT` shortens the ~2M-cycle power-on init.

## Files
- `sdram_model.v` — behavioral 16-bit SDR SDRAM (4 banks, 13-row/9-col, CAS-2, DQM). Data
  appears on `dq` exactly CAS_LATENCY cycles after a READ (combinational output — a registered
  one would add a cycle).
- `tb_memory.v` — clocks, dot-clock windows, a CPU write→read self-check, and `[dbg]` probes.

## State: MEMTEST PASSES (CPU + VRAM)
Both memory ports round-trip correctly:
- **CPU RAM** (8-bit, bank 0): across byte lanes, rows, and high address bits (to 2 MB), **no aliasing**.
- **VRAM** (8-bit write / 16-bit read, bank 3): byte lanes correct, 16-bit word assembled right
  (`{odd,even}`), up to the top of 128 KB.
- CPU and VRAM live in different banks and **don't disturb each other**.

This validates the whole ECP5 SDRAM data path in simulation. Three real issues were found + fixed getting here:
1. **Read path** — the ECP5 build latched `SdrDat` (our tri-stated drive reg = Z) instead of the
   `IO_sdram_dq` bus; Gowin's inferred-SDRAM magic hid this. Fixed in `memory.v`.
2. **Power-up state** — several FSM regs (`ff_mem_seq`, `ff_sdr_seq`, `SdrSta`, …) were
   uninitialized; on real FPGA they power up to 0, but in 4-state sim they stayed `X` and init
   never ran. Added explicit `= 0` initializers (also the correct config-time state on ECP5).
3. **Dot-clock cadence (testbench)** — `memory.v`'s `ff_sdr_seq` locks to `video_dhclk`, and the
   CPU/VDP choice is made from `video_dlclk` at `ff_sdr_seq==001`. The tb now replicates the VDP's
   4-phase dot-state machine (vdp_ssg.vhd): DH rises with DL=0 → CPU, with DL=1 → VDP. With the
   wrong cadence, every access looked like a VDP access.

Notes / next:
- Geometry addresses the **full 8 MB** (bank=`addr[22:21]` + row=`addr[12:1]` + col=`addr[20:13]`),
  verified in the test across banks 0/1/2 + VRAM in bank 3, no aliasing. The MSX can't address more,
  so the 13/9 rewrite is **not needed** (see `../SDRAM_PORT.md`).
- **VDP-port memtest** (drive `vram_*` during the DL=1 phase, check 16-bit reads) — DONE; the remaining
  coverage; on-hardware SDRAM phase tuning is the final board-only step.

---

# Full-design boot simulation (whole MSX in iverilog)

Beyond the `memory_ctrl` unit test above, the **entire mixed-language MSX2+ core** runs in iverilog.

## How
```
./build_ecp5.sh                                                    # produces gen/ artifacts
EXTRA_DEFINES="-DSIM_FAST_BOOT -DSIM_FAST_INIT" ./sim/gen_full_sim.sh   # -> sim/sim_msx.v
iverilog -g2012 -o sim/simboot sim/tb_boot.v sim/sim_msx.v sim/ecp5_prims_sim.v sim/sdram_model.v
vvp sim/simboot
```
- `gen_full_sim.sh` — yosys reads the whole design (VHDL `.il` + Verilog + sv2v), flattens, and writes
  ONE behavioral Verilog. `memory_collect; setundef -init -zero` gives FFs a power-up 0 (real FPGA does;
  4-state sim otherwise leaves them X and the boot FSM locks). Two registered `inout` pins
  (`IO_sdram_dq`, `mspi_mosi`) that write_verilog emits as inout+reg are split into a wire + tri-state assign.
- `ecp5_prims_sim.v` — behavioral `EHXPLLL` (clock tree from the divider params), `ODDRX1F`, `USRMCLK`.
- `tb_boot.v` — drives the 50 MHz osc + reset, connects the SDRAM model, observes boot progress.
- **`SIM_FAST_BOOT`** (top.v, ifdef, no synth impact) shortens the ~56 ms reset ramp + the ~3 s ESP/WiFi
  hold (`esp_boot_ok`) that would otherwise make RTL sim of boot take hours.

## State — C-BIOS boots; the Z80 executes it
Clocks tick (108 MHz), reset releases, the machine boots, and with **C-BIOS pre-loaded into the SDRAM
model** (`tb_frame.v`: 32 KB main @`0x760000` + 16 KB sub @`0x768000`, from `cbios_*.hex`), the **Z80
fetches and runs C-BIOS** — `bios_reads` climbs steadily (thousands of instruction fetches from the
BIOS region of SDRAM). This validates the CPU + memory + BIOS path *logically*.

`tb_frame.v` also watches for **VDP VRAM writes** (bank 3, col `0xE0+`) and, once the screen is drawn,
dumps the low 8 KB of VRAM (name/pattern tables) to `sim/vram_dump.txt` for offline rendering; live
progress is flushed to `sim/frame_status.txt`. C-BIOS's init (RAM test / hardware setup) is long, so
reaching the first VRAM write takes a lengthy sim run. `SIM_FAST_BOOT` skips the 512 KB flash copy
(shrinks `GOAULD_ROM_SIZE`) since the ROMs are pre-loaded directly.

Note: `cbios_main.hex` / `cbios_sub.hex` are generated locally from the C-BIOS ROMs
(`od -An -v -tx1 <rom> | tr -s ' ' '\n'`) and are **gitignored** (don't redistribute the binaries).
