# MSXnano → F45 port plan (Lattice ECP5 LFE5U-45F / MiniMistle)

Fork of `Papipapito/MSXnano` (MSX2+ for Tang Nano 20K / Gowin). Goal: keep the MSX2+
core (Z80, V9958, SCC/OPLL, Nextor) and swap the **Gowin platform layer** for **ECP5**.
Practice project — work happens on branch `ecp5-f45-port`.

## References
- **ECP5 platform guide:** `lawrie/ulx3s_msx` (MSX on ULX3S ECP5, pure Verilog).
  Cloned locally at `../_ref_ulx3s_msx`. ⚠️ **No license = read/learn only, don't copy
  files wholesale into this GPL-3.0 repo without the author's OK.** (`ecp5pll.sv` is
  emard's standard ULX3S PLL wrapper — that one's reusable.)
- **Same-ecosystem ECP5 port pattern:** NanoMig (icepi-zero/ECP5) — how the MiSTle
  world ports Tang Nano (Gowin) cores to ECP5.
- **Author's own audit:** `fpga/AUDIT_PRE_PORT_60K.md` — read §1 before starting.

## The 4 port fronts — file map
| Replace (MSXnano / Gowin) | Guide (ulx3s_msx / ECP5) |
|---|---|
| `fpga/src/gowin/clk_108p.v` (rPLL) | `ulx3s/pll.v` + `src/lattice/ecp5pll.sv` (`EHXPLLL`) |
| `fpga/tang9k.cst`, `Z80_goauld.sdc` | `ulx3s/ulx3s_v20.lpf` (`LOCATE COMP … SITE`) |
| Gowin DVI TX | `src/hdmi.v` (ECP5 GPDI/DVI) |
| Gowin SDRAM controller | `src/sdram.v` (ECP5-tested) |
| `fpga/bl616` companion | `esp32/` → maps to our **RP2040 FPGA Companion** |
| `fpga/top.v` (Tang Nano) | `src/msx.v` + a new F45 board top |

## Bring-up order (each step testable on real HW)
1. **Clocks** — write an `EHXPLLL` PLL from `ulx3s/pll.v`. Feed it the MiniMistle system
   oscillator (Y1 → GLOBAL_CLK — CHECK its frequency), produce MSXnano's core clocks
   (≈108/135 MHz etc.). Get `locked` high.
2. **Constraints** — write `f45.lpf` from `ulx3s_v20.lpf` + MiniMistle pin map (GPDI pair,
   SDRAM bus, SD, clk, reset/buttons). Silent-fail risk if pins are wrong — double-check.
3. **Video** — swap Gowin DVI → `src/hdmi.v`; get a **test pattern out the GPDI/HDMI** first.
4. **SDRAM** — adopt `src/sdram.v` (or adapt MSXnano's); prove it with a memtest before the core.
5. **Companion** — map BL616 keyboard/SD/OSD hooks → RP2040 (FPGA Companion), or mimic the
   ulx3s ESP32 approach.
6. **Core bring-up** — instantiate the MSX2+ core on the new platform; iterate.

## To fill in (board specifics)
- MiniMistle system-clock frequency (Y1). GPDI/HDMI pin sites. SDRAM part + pinout.
  RP2040↔FPGA interface (SPI: FPGA_SCK/MISO/MOSI/CS from the MiniMistle schematic).
  ECP5-45F resource budget vs MSX2+ (85F on ULX3S is roomier — watch LUT/BRAM usage).

## Toolchain — DECIDE
- **Open-source (recommended for learning):** Yosys + nextpnr-ecp5 + prjtrellis.
- **Lattice:** Diamond + Synplify (matches NanoMig; needed for flash-boot behavior).
The `EHXPLLL` attributes in `ulx3s/pll.v` are written Diamond-style but also work under Yosys.

## Pre-port bug fixes (from AUDIT §1)
- `flash_rw.v` — 2 fixes required before reusing it for SRAM-persistence.
- YM2149 combinational loop — placement lottery on a new device; watch it.
