# MSXnano-F45 — MSX2+ core ported to Lattice ECP5 (IcePi Zero 45F)

**Status: work in progress — not finished. It does not build or run yet.**
This is a learning/porting effort; the steps below show how far it has got.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano) (a full MSX2+ core —
Z80, V9958, SCC/OPLL, SD/Nextor, plus ColecoVision and Sega SG-1000 — for the **Tang Nano 20K /
Gowin**), being ported to the **IcePi Zero (ECP5, 45F)** on the MiSTle **icepi_carrier**.

## The plan
Keep the MSX2+ core; replace the **Gowin platform layer** with **ECP5** equivalents.
Full roadmap: [`PORT_PLAN.md`](PORT_PLAN.md).

Bring-up order: clocks -> constraints -> HDMI test -> SDRAM -> companion -> core.

Platform references (same board, tested): NanoMig IcePi port, `cheyao/icepi-zero`.

## Steps taken so far
- **Step 1 — Clocks (done).** [`fpga/src/lattice/clk_108p_ecp5.v`](fpga/src/lattice/clk_108p_ecp5.v):
  a drop-in ECP5 PLL (via BSD `ecp5pll.sv`) producing 108 MHz at 0/180 deg from the IcePi's
  50 MHz oscillator. Same module name/ports as the Gowin `CLK_108P`, so `top.v` is unchanged.
- **Step 2 — Constraints (in progress).** [`fpga/icepi.lpf`](fpga/icepi.lpf): pin map from the
  tested NanoMig IcePi port. Clock, GPDI, SDRAM, SD, flash, LEDs and buttons mapped; companion
  SPI (RP2350), UART and a few nets still to do.
- **Step 4 — SDRAM (planned).** [`fpga/SDRAM_PORT.md`](fpga/SDRAM_PORT.md): the IcePi SDRAM is
  16-bit vs MSXnano's 32-bit; the conversion plan and IcePi chip geometry are written up.

## Not done yet
Video (GPDI/HDMI TX and pixel/TMDS clocks), the SDRAM controller, RP2350 companion,
core bring-up, and a working build/toolchain (Diamond or Yosys — undecided).

## Credits and license
Based on Papipapito/MSXnano, which is based on jabadiagm/MSXgoauldSD_tn20k. **GPL-3.0**
(see `LICENSE`). The original project README is kept as [`README.upstream.md`](README.upstream.md).

Parts of this port were done with assistance from Claude (an AI coding assistant).
