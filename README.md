# MSXnano-F45 — MSX2+ core ported to Lattice ECP5 (IcePi Zero 45F)

> ⚠️ **Work in progress — NOT finished.** It does not build or run yet. This repo is a
> learning/porting effort; see the steps below for exactly how far it's got.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano) (a full MSX2+ core —
Z80, V9958, SCC/OPLL, SD/Nextor — for the **Tang Nano 20K / Gowin**), being ported to the
**IcePi Zero (ECP5, 45F)** on the MiSTle **icepi_carrier**. A Verilog-practice project.

## The plan
Keep the MSX2+ core; replace the **Gowin platform layer** with **ECP5** equivalents.
Full roadmap: [`PORT_PLAN.md`](PORT_PLAN.md). Work happens on branch `ecp5-f45-port`.

Bring-up order: **clocks → constraints → HDMI test → SDRAM → companion → core.**

Platform references (same board, tested): NanoMig IcePi port, `cheyao/icepi-zero`.

## Steps taken so far
- ✅ **Step 1 — Clocks.** [`fpga/src/lattice/clk_108p_ecp5.v`](fpga/src/lattice/clk_108p_ecp5.v):
  a drop-in ECP5 PLL (via BSD `ecp5pll.sv`) producing 108 MHz @ 0°/180° from the IcePi's
  50 MHz oscillator. Same module name/ports as the Gowin `CLK_108P`, so `top.v` is unchanged.
- 🔶 **Step 2 — Constraints (in progress).** [`fpga/icepi.lpf`](fpga/icepi.lpf): pin map from
  the tested NanoMig IcePi port. Clock, GPDI, SDRAM, SD, flash, LEDs and buttons are mapped;
  companion SPI (RP2350), UART and a few nets are still TODO.

## Not done yet
- **Video** — ECP5 GPDI/HDMI TX + pixel/TMDS clocks.
- **SDRAM** — the IcePi SDRAM is **16-bit**; MSXnano's controller is **32-bit** → needs adapting.
- **Companion** — RP2350 (keyboard/SD/OSD) integration.
- **Core bring-up** and a working **build/toolchain** (Diamond or Yosys — undecided).

## Credits & license
Based on Papipapito/MSXnano ← jabadiagm/MSXgoauldSD_tn20k. **GPL-3.0** (see `LICENSE`).
Original project README kept as [`README.upstream.md`](README.upstream.md).
