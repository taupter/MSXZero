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

## State (what works / what's next)
Working: compiles, power-on init completes (`RstSeq→31`), the command FSM issues ACTIVATE/
READ/WRITE, and **VDP-side accesses run** (bank 3). Two real bugs were found+fixed getting here:
1. **Read path** — the ECP5 build latched `SdrDat` (our tri-stated drive reg = Z) instead of the
   `IO_sdram_dq` bus; Gowin's inferred-SDRAM magic hid this. Fixed in `memory.v`.
2. **Power-up state** — several FSM regs (`ff_mem_seq`, `ff_sdr_seq`, `SdrSta`, …) were
   uninitialized; on real FPGA they power up to 0, but in 4-state sim they stayed `X` and init
   never ran. Added explicit `= 0` initializers (also the correct config-time state on ECP5).

Next: the **CPU-side access** activates its row (bank 0 ACTIVATE) but the READ/WRITE doesn't
issue — the controller expects a specific VDP dot-clock cadence on `video_dhclk`/`video_dlclk`
that the current testbench doesn't yet replicate (it toggles them together). Fixing that (drive
the two phases the way the real VDP does) is the next step, then the 13/9 geometry can be
validated end-to-end. See `../SDRAM_PORT.md`.
