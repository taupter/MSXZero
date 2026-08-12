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

## State: MEMTEST PASSES
CPU write→read round-trips correctly across byte lanes, multiple rows, and high address bits
(up to 2 MB), with **no aliasing** (early writes survive later ones). This validates the ECP5
read path + byte-lane handling in simulation. Three real issues were found + fixed getting here:
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
- The current geometry is 12-row/8-col → **2 MB** addressable, which passes and is enough for the
  MSX (512 KB mapper RAM + 128 KB VRAM). The 13/9 fix (`../SDRAM_PORT.md`) would use the full chip
  but isn't required for the core to work.
- **VDP-port memtest** (drive `vram_*` during the DL=1 phase, check 16-bit reads) is the remaining
  coverage; on-hardware SDRAM phase tuning is the final board-only step.
