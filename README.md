# MSXnano-F45 — MSX2+ core ported to Lattice ECP5 (IcePi Zero 45F)

**Status: work in progress — not finished. It does not build or run yet.**
The FPGA *platform layer* (clocks, video output, constraints) is largely in place in RTL; the
SDRAM controller, flash-clock, toolchain and on-hardware bring-up are still to do.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano) (a full MSX2+ core —
Z80, V9958, SCC/OPLL, SD/Nextor, plus ColecoVision and Sega SG-1000 — for the **Tang Nano 20K /
Gowin**), being ported to the **IcePi Zero (ECP5, 45F)** on the MiSTle **icepi_carrier**.

The Gowin build is kept intact: every ECP5 change is behind `` `ifdef ECP5`` and the ECP5-only
modules live in `fpga/src/lattice/`. Build recipe: [`fpga/BUILD_ECP5.md`](fpga/BUILD_ECP5.md).
Full roadmap: [`PORT_PLAN.md`](PORT_PLAN.md).

## Done so far
**Clocks** — one PLL from the IcePi's 50 MHz oscillator makes everything:
- `fpga/src/lattice/clocks_ecp5.v` — 108 / 108@180 / 54 / 27 MHz (one VCO@540, all exact),
  replacing the Gowin `CLK_108P` + both `Gowin_CLKDIV` dividers.
- `fpga/tn_vdp_v3_v9958/src/lattice/clk_135_ecp5.v` — 27 -> 135 MHz for the VDP (replaces Gowin `CLK_135`).
- `fpga/src/lattice/ecp5pll.sv` — BSD ECP5 PLL generator.

**Video output** — `fpga/tn_vdp_v3_v9958/src/hdmi/serializer_ecp5.sv`: a 5x `ODDRX1F`
pseudo-differential GPDI output, replacing the Gowin `OSER10` serializer + `ELVDS_OBUF`. Keeps
MSXnano's own TMDS encoding and its 27/135 MHz clocks.

**Constraints** — `fpga/icepi.lpf`: clock (M1/50 MHz), GPDI, 16-bit SDRAM, SD card, config flash,
LEDs, buttons, UART, and the RP2350 **companion SPI** (`spi_sclk`/`csn`/`dir`/`dat`/`irqn` on
L1/N4/F2/J2/P2) — pins taken from the tested NanoMig IcePi port.

**Synthesis-clean-up** — `fpga/src/lattice/bufg_ecp5.v` (BUFG pass-through; ECP5 infers global
routing). Memories are inferred BRAM (portable). The Gowin PLL/CLKDIV/serializer helper files are
excluded from the ECP5 file list (see `BUILD_ECP5.md`).

## Not done yet
- **SDRAM** — the IcePi SDRAM is 16-bit, MSXnano's controller is 32-bit; conversion is planned in
  [`fpga/SDRAM_PORT.md`](fpga/SDRAM_PORT.md) (contained to `src/memory.v`).
- **Flash clock** — `mspi_sclk` must go through the ECP5 `USRMCLK` config-clock primitive.
- **Toolchain** — pick + install Yosys+nextpnr-ecp5 or Diamond, wire in the `BUILD_ECP5.md` file list.
- **On-hardware bring-up** — clocks lock, HDMI test pattern, SDRAM memtest, companion, then the core.

Notes: ColecoVision + SG-1000 share the Z80/VDP/PSG and ride along unchanged. Reference platform =
the NanoMig IcePi port and `cheyao/icepi-zero` (same board, tested).

## Credits and license
Based on Papipapito/MSXnano, which is based on jabadiagm/MSXgoauldSD_tn20k. **GPL-3.0**
(see `LICENSE`). The original project README is kept as [`README.upstream.md`](README.upstream.md).

Parts of this port were done with assistance from Claude (an AI coding assistant).
