# Building MSXZero for the ECP5 (IcePi Zero XL 45F)

The whole core builds, fits the 45F, and packs a bitstream on the open-source toolchain.
One command:

```
cd fpga
./build_ecp5.sh # -> msx_ecp5.bit
EXTRA_DEFINES=-DBRINGUP_LEDS ./build_ecp5.sh # bring-up bitstream (status LEDs — see BRINGUP.md)
```

## Prerequisites
- OSS CAD Suite (yosys, nextpnr-ecp5, ghdl, ecppack, iverilog, ecppll). The script points at
 `/Volumes/External II/tools/oss-cad-suite` — edit `OSS=` at the top for your path.
- sv2v (SystemVerilog→Verilog). Installed at `$OSS/bin/sv2v`. Get it from
 github.com/zachjs/sv2v if missing.

## What the build does (and why each step exists)
This is a mixed-language design — VHDL + Verilog + SystemVerilog — which the open flow can't
just throw at yosys. `build_ecp5.sh` does:

0. sv2v — convert the SystemVerilog (HDMI encoder + `v9958_top.v`) to Verilog-2005. yosys's
 Verilog frontend can't parse SV unpacked-array ports / `real` params; sv2v flattens them.
1. ghdl analyze — compile all VHDL into a clean work library (skip-successful fixpoint, so a
 package is never re-analyzed after a dependent — avoids the T80/T80_Pack obsolescence error).
2. ghdl → RTLIL per boundary entity — each VHDL entity that Verilog instantiates is elaborated
 with ghdl and flattened to its own `.il` (`gen/vhdl/`). Done per-entity because ghdl's
 `-read` crashes deriving >1 VHDL module, and flattening absorbs shared sub-entities like `ram`
 so nothing is re-defined. lpf1/lpf2 get `-gMSBI=11`.
3. yosys synth_ecp5 — read the `.il` modules + the plain `.v` + the sv2v output, then
 `synth_ecp5 -flatten`. LUTs are mapped with classic `abc -lut 4:7`, not abc9 (abc9 hits a
 Yosys dev-build XAIGER bug on this design — see `docs/abc9_issue.md`). → `msx_ecp5.json`.
4. nextpnr-ecp5 — place & route for `--45k --package CABGA256`, `icepi.lpf`,
 `--lpf-allow-unconstrained` (unused m0s pins). → `msx_ecp5.config`.
5. ecppack — pack the bitstream. → `msx_ecp5.bit`.

## ECP5 vs Gowin selection
Every ECP5 change is behind `` `ifdef ECP5``; the Gowin build stays intact. Selection is by which
files the script includes/excludes (it drops the Gowin `clk_108p`, `gowin_clkdiv*`, `clk_135`,
`serializer.sv`) plus `ifdef`s in `top.v` / `v9958_top.v`. ECP5-only sources live in `src/lattice/`
(`clocks_ecp5.v`, `bufg_ecp5.v`) and `tn_vdp_v3_v9958/src/hdmi/serializer_ecp5.sv`.

## Current status
- Synthesizes, fits (75% LUT / 29% FF / 16% BRAM / 12% DSP / 1 PLL / 1 USRMCLK on LFE5U-45F), routes, bitstream (~700 KB).
- SDRAM controller memtest passes in sim (both CPU + VRAM ports, full 8 MB across 4 banks) — see `sim/README.md`.
- Full-design boot-in-sim: the whole MSX runs in iverilog and the Z80 executes C-BIOS from SDRAM (`sim/tb_frame.v`). A drawn frame isn't reachable in sim (C-BIOS spins in early init before video) — the real screen comes from hardware.
- `mspi_sclk` → ECP5 `USRMCLK` (flash config clock) — done; routes `1/1`, so the design can boot from flash.
- `clk_54m` (Z80) timing routes ~24–36 vs 53.85 MHz — multicycle CPU, likely fine on HW (`README.md`).
- On-hardware bring-up not started — procedure in `BRINGUP.md`. Next prep: HDMI test-pattern + on-HW SDRAM memtest harnesses.

See `PORT_PLAN.md` (roadmap), `SDRAM_PORT.md` (memory), `BRINGUP.md` (hardware), `docs/abc9_issue.md`.
