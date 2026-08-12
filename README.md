# MSXZero — an MSX2+ computer on the Lattice ECP5 (IcePi Zero 45F)

**Status: work in progress — not finished. It does not build or run yet.**
The FPGA platform layer (clocks, video output, constraints) is written; the SDRAM controller,
full synthesis, and on-hardware bring-up are still to do. See progress at the bottom.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano), being ported from the
**Tang Nano 20K (Gowin)** to the **IcePi Zero (ECP5, 45F)** on the MiSTle **icepi_carrier**.

## Progress (by stage)

| Stage | Status | Done |
|---|---|---|
| Research / target lock-in (IcePi Zero + carrier) | complete | 100% |
| Open-source toolchain (Yosys + nextpnr-ecp5 + ghdl) | installed & verified | 100% |
| Clocks / PLL (`EHXPLLL`, 50→107.69/134.6/26.92/53.85) | synthesizes; phase to tune on HW | 90% |
| Video output (ECP5 GPDI/TMDS) | RTL done, untested | 85% |
| Constraints (`icepi.lpf`) | mapped; flash `USRMCLK` pending | 90% |
| Gowin-primitive cleanup (BUFG, file list) | done | 85% |
| Full synthesis (compile the whole design) | **done** — the whole core maps to ECP5 primitives with the open-source flow | 100% |
| SDRAM controller (16-bit) | proven controller vendored (NanoMig — tested on this exact board, the hard part done); adapter to CPU/VDP + arbitration + memtest remain | ~30% |
| Fit on the 45F (nextpnr place & route) | **fits + routes + packs to a .bit**: 78% logic (34360/43848 LUT4), 29% FF, 16% BRAM (18/108), 12% DSP (9/72), 1 PLL. ~22% LUT headroom + free BRAM/DSP for OPL4/V9968. `clk_54m` (Z80) timing not yet closed (~30–36 vs 53.85 MHz) | 90% |
| Bitstream (ecppack) | **done** — full flow RTL→synth→P&R→`msx_ecp5.bit` (~683 KB) on the open-source toolchain | 100% |
| On-hardware bring-up (HDMI / SDRAM / companion / DB9) | not started | 0% |
| Extras (OPL4 MoonSound, etc.) | core vendored, not wired | 5% |
| **Overall** | **synthesizes + fits the 45F (78% logic); SDRAM adapter + hardware bring-up ahead** | **~45%** |

> "Written" is the easy part; the build-and-bring-up phase is where most of the remaining effort is.

**Toolchain note:** the open-source flow needed real integration work for this mixed
VHDL/Verilog/SystemVerilog design: the SystemVerilog HDMI encoder is pre-converted with
**sv2v** (yosys can't parse unpacked-array ports / `real` params); each VHDL boundary entity
is elaborated with **ghdl** and flattened to RTLIL (the `-read` path crashes on multiple VHDL
modules, and shared sub-entities like `ram` must not be re-defined); and several source nits
that Gowin tolerated were fixed (package shared-variables, a missing instance name, port-name
case, `real`→integer math). See `fpga/build_ecp5.sh` and `BUILD_ECP5.md`.

## What the core is

This is a complete **MSX2+ home computer** implemented in FPGA logic, plus two bonus consoles
that share the same silicon. It is not an emulator running on a CPU — it is the actual hardware,
recreated:

### Systems
- **MSX2+** — the main machine (Z80, V9958 video, full BIOS/sub-ROM).
- **ColecoVision** and **Sega SG-1000** — ride along for free (they reuse the Z80 / VDP / PSG).

### CPU & memory
- **Z80** CPU (the T80 core) with the MSX clock-enable timing.
- **512 KB mapper RAM** + **128 KB VRAM**, held in external SDRAM.
- **MegaRAM / MegaROM** mappers (ASCII 8K/16K, Konami/SCC) for cartridge images.
- Config flash + an RTC.

### Video (V9958 VDP)
- All MSX / MSX2 / MSX2+ screen modes, sprites, 19268-colour YJK modes, hardware scroll.
- Output over **HDMI** (and the design also carries VGA-style timing).

### Sound
- **PSG** (AY-3-8910 / YM2149) — the classic MSX sound.
- **SCC / SCC-I** — Konami wavetable (Gradius etc.).
- **OPLL** (YM2413, MSX-Music FM) via the `jtopl` core.
- **OPL4 / MoonSound** — the `YMF278B` core is vendored in (`fpga/opl4wave/`), not yet wired up.

### Storage & I/O
- **SD card** with the **Nextor** kernel (MSX-DOS 2 — boot disks, load ROM/DSK images).
- **FPGA Companion** (RP2350 on the carrier, over SPI) — provides **USB keyboard and gamepads**
  and the on-screen menu.
- **Two DB9 joystick ports** (via the carrier's 74LCX07 buffers) — read natively by the PSG,
  as on a real MSX (added in this port).
- WiFi hooks (via the companion), MIDI, WS2812 status LED.

## The ECP5 port (this fork)

Goal: keep the MSX2+ core, swap the **Gowin platform layer** for **ECP5**. Every ECP5 change is
behind `` `ifdef ECP5`` and lives in `fpga/src/lattice/`; the Gowin build stays intact.
Target hardware: **IcePi Zero (ECP5-45F) + icepi_carrier** (the tested MiSTle board), RP2350 companion.

**Done:**
- Clocks — `clocks_ecp5.v`: one `EHXPLLL` from the 50 MHz osc → 107.69 (sys) / 134.6 (TMDS) /
  26.92 (pixel) / 53.85 MHz. (108 MHz is not reachable from 50 MHz; the whole system runs 0.28%
  low — within HDMI tolerance, imperceptible for MSX.)
- Video output — `serializer_ecp5.sv`: ECP5 `ODDRX1F` GPDI, replacing the Gowin `OSER10` + `ELVDS_OBUF`.
- Constraints — `icepi.lpf`: clock, GPDI, 16-bit SDRAM, SD, flash, LEDs, buttons, companion SPI, DB9 joysticks.
- Synthesis-clean-up — `bufg_ecp5.v` stub; the entire VHDL layer analyzes under `ghdl`.
- Toolchain — open-source (Yosys + nextpnr-ecp5 + ghdl); `build_ecp5.sh` + `BUILD_ECP5.md`.

**Not done yet:**
- Full synthesis (Yosys/GHDL mixed-language integration), then nextpnr fit (does MSX2+ fit a 45F?).
- **SDRAM** — the IcePi SDRAM is 16-bit; plan is to wrap NanoMig's tested controller (`nanomig_sdram.sv`).
- Flash clock (`mspi_sclk` → ECP5 `USRMCLK`), on-hardware bring-up (HDMI, SDRAM memtest, companion).
- **OPL4** — wire in the vendored `opl4wave/YMF278B.sv` (redo its wave-ROM memory wrapper for ECP5). See PORT_PLAN.md.

## Building

Open-source flow: `cd fpga && ./build_ecp5.sh` (needs the OSS CAD Suite). Details: `fpga/BUILD_ECP5.md`.
Roadmap: `PORT_PLAN.md`. SDRAM plan: `fpga/SDRAM_PORT.md`.

## References & credits

Based on Papipapito/MSXnano ← jabadiagm/MSXgoauldSD_tn20k. **GPL-3.0** (`LICENSE`).
Platform references (same IcePi hardware): NanoMig IcePi port, `cheyao/icepi-zero`.
OPL4 core vendored from [Papipapito/MSXimus](https://github.com/Papipapito/MSXimus) (GPL-3.0).
`jtopl` FM cores by jotego (GPL-3.0). Upstream README kept as `README.upstream.md`.

Parts of this port were done with assistance from Claude (an AI coding assistant).
