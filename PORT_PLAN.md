# MSXnano → F45 port plan (Lattice ECP5-45F)

Fork of `Papipapito/MSXnano` (MSX2+ for Tang Nano 20K / Gowin). Goal: keep the MSX2+
core (Z80, V9958, SCC/OPLL, Nextor) and swap the **Gowin platform layer** for **ECP5**.
Practice project — work is on `main` (the port branch was merged in + deleted).

**Scope note:** the fork also emulates **ColecoVision + Sega SG-1000** (they reuse the same
Z80 / VDP / PSG). Not needed here, but harmless — **keep them as-is, don't strip.** The port
is purely the platform layer (clocks/constraints/video/SDRAM/companion); the emulated systems
ride along unchanged.

## Target hardware (TESTED)
**IcePi Zero** (Lattice ECP5, upgraded to **45F**) on the **MiSTle icepi_carrier**.
This is the done-and-tested board — NOT the unfinished MiniMistle (which is *derived from*
the IcePi Zero, so it's close, but we target the real thing). RP2350 on the carrier =
FPGA Companion (keyboard/SD/OSD).

## References (primary = same board, tested)
- **NanoMig IcePi-Zero port** — `MiSTle-Dev/NanoMig/src/lattice/icepi-zero/`: `nanomig.lpf`,
  `nanomig.sdc`, `pll_142m.v`, `top.sv`, `build.tcl`/`.ldf`. The **tested** carrier-level
  constraints/PLL/companion for this exact hardware. **Best platform template.**
- **`cheyao/icepi-zero`** — the board itself: `gateware/sdram/memtest/` (tested `sdram.v` +
  `ecp5pll.sv` + `.lpf`) and `gateware/dvi/` (GPDI/DVI). Proven bare-board building blocks.
- **`lawrie/ulx3s_msx`** (`../_ref_ulx3s_msx`) — secondary: MSX-on-ECP5 *logic* patterns
  (Verilog Z80, keyboard, video). No license → read/learn only, don't copy files in.
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

## Board specifics (CONFIRMED from tested NanoMig/cheyao ports)
- **Input clock: 50 MHz** on ECP5 pin **`M1`** (`nanomig.lpf`: `FREQUENCY PORT "clk" 50 MHZ`).
- **GPDI/HDMI** (tested pins): `gpdi_dp/dn[0..2]` on R13/T14, R15/T15, … `IO_TYPE=LVCMOS33D`.
- **SDRAM:** use the IcePi-tested controller `cheyao/icepi-zero/gateware/sdram/memtest/sdram.v`
  + its `.lpf` pin block.
- **Companion:** RP2350 on the carrier — see `nanomig top.sv` for the SPI/OSD hookup pattern.
- **Resource budget:** 45F is smaller than the ULX3S 85F — watch LUT/BRAM for MSX2+.

## Bring-up order (each step testable on real HW)
1. **Clocks — DONE.** `fpga/src/lattice/clk_108p_ecp5.v` (drop-in for the Gowin `CLK_108P`)
   makes 108 MHz 0°/180° from the 50 MHz IcePi osc, via BSD `ecp5pll.sv`. Build swaps
   `gowin/clk_108p.v` → `lattice/clk_108p_ecp5.v`. Downstream 27 MHz enable = /4 of 108, so
   MSX timing preserved. (Video pixel/TMDS clocks added in Step 3.)
2. **Constraints** — write `icepi.lpf` from `nanomig.lpf` + `cheyao` `.lpf`: clk(M1,50MHz),
   GPDI pins above, SDRAM bus, SD, companion SPI, reset/buttons. Silent-fail if pins wrong.
3. **Video** — output stage DONE. `tn_vdp_v3_v9958/src/hdmi/serializer_ecp5.sv` replaces the
   Gowin `OSER10` serializer + `ELVDS_OBUF` with a 5x ODDRX1F pseudo-differential GPDI output
   (drives P and inverse N as plain LVCMOS33 — icepi.lpf updated). Wired into `v9958_top.v`
   under ``ifdef ECP5`` (Gowin path kept as the `else`). Keeps MSXnano's TMDS encoding + its
   existing clk_pixel(27)/clk_pixel_x5(135) clocks. REMAINING for video:
     - VDP clock PLL DONE: `tn_vdp_v3_v9958/src/lattice/clk_135_ecp5.v` = ECP5 drop-in for the
       Gowin `CLK_135` (27->135 via ecp5pll).
     - CLOCK TREE DONE: `fpga/src/lattice/clocks_ecp5.v` = one ecp5pll (VCO 540) making
       108/108@180/54/27 from the 50 MHz osc. In top.v under ``ifdef ECP5`` it replaces CLK_108P;
       the two Gowin_CLKDIV dividers are excluded with ``ifndef ECP5`` (clk_27m/clk_54m from PLL).
       VDP keeps clk_135_ecp5 (27->135). Tree: 50MHz -> [PLL] 108/108@180/54/27 -> VDP clk_27m -> [PLL] 135.
     - REMAINING to build: define `ECP5` (e.g. `+define+ECP5`); handle any leftover Gowin
       primitives (e.g. `BUFG` global-clock buffers — usually just remove/alias on ECP5, routing
       is inferred); the flash `mspi_sclk` uses the ECP5 config clock (USRMCLK), not a pin.
     - then get a test pattern out HDMI on real hardware.
4. **SDRAM** — IcePi is **16-bit** vs MSXnano's **32-bit** controller. Don't fight the 32-bit
   controller: adopt a **16-bit** one. `ulx3s_msx/src/sdram.v` shows the tested pattern — an
   8-bit-CPU ↔ 16-bit-SDRAM bridge that picks the byte lane by `addr[0]` and masks writes with
   `sd_dqm={addr[0],~addr[0]}`. Base the F45 controller on `cheyao icepi sdram.v` (16-bit, tested
   on this exact board) + that byte-lane wrapper; prove it with cheyao's memtest first. Tune the
   clkoutp phase (currently 180°). Note: MSX2+ needs ~512K mapper + 128K VRAM, so BRAM-only
   (ulx3s `c_sdram=0`, 32K) is not enough — the 16-bit SDRAM path is required.
5. **Companion** — map BL616 keyboard/SD/OSD → RP2350 (FPGA Companion), pattern from NanoMig `top.sv`.
6. **Core bring-up** — instantiate the MSX2+ core on the new platform; iterate.

## Toolchain
- **Diamond + Synplify** = what the tested NanoMig IcePi port uses (`build.tcl`/`.ldf`, `scuba` PLL).
  Safest match for this board.
- **Open-source** (Yosys + nextpnr-ecp5 + prjtrellis) also works — `cheyao` has Makefiles, and
  `ecp5pll.sv` computes dividers for either flow. Good for fast iteration / learning.
- Neither is installed locally yet — decide + install before the first build.

## Pre-port bug fixes (from AUDIT §1)
- `flash_rw.v` — 2 fixes required before reusing it for SRAM-persistence.
- YM2149 combinational loop — placement lottery on a new device; watch it.

## Future: OPL4 (MoonSound)
`fpga/opl4wave/` is vendored from Papipapito/MSXimus (GPL-3.0): `YMF278B.sv` (the OPL4 core,
~1200 lines) + `YMF278B_pkg.sv` + `ymf278b_gowin.v` (Gowin wave-ROM wrapper) + `convert.sh`/
`postproc.py` (wave-ROM tools). NOT wired up yet. To add MoonSound:
- The `YMF278B.sv` core (24-voice PCM + FM regs) is largely portable SV — keep it.
- Redo the memory side: `ymf278b_gowin.v` is Gowin-specific; the OPL4 wave ROM (YRW801, 2 MB, +
  sample RAM) must be served from the IcePi SDRAM (share the 16-bit controller) or a dedicated
  region. This is the real integration work.
- OPL4 = OPL3 FM + PCM; pair it with MSXimus's `opl3/` for the full FM path if wanted.
- Resource check on the 45F first — OPL4 + OPL3 is not tiny.

## Cherry-picks from MSXimus (Papipapito's GW5AT-60 port) — what's worth taking
Same core lineage, GPL-3.0. It's Gowin+DDR3 so the *platform* code isn't reusable, but:
- **OPL4** (`opl4wave/`) — DONE, pulled (above). Best path to MoonSound vs writing from MAME/datasheet.
- **`test_hdmi/` + `test_sdram/`** — standalone bring-up harnesses (HDMI test pattern; SDRAM tester
  `sdram_tester.v` + `tester_tb.v`). HIGH value: adapt for ECP5 to validate GPDI and SDRAM in isolation
  before the full core (mirrors our Step 3/Step 4 bring-up).
- **Board-abstraction structure** (`msx_console60k/`, `constraints/`, `ip/`) — reorganize our scattered
  `src/lattice/` into a clean `icepi/` board dir following this pattern.
- **`opl3/`** — full OPL3 FM core; take it with OPL4 for MoonSound FM.
- SKIP for now: `jt10` (YM2610, not MSX-standard), `v9968`/`video720` (enhanced VDP + 720p — likely
  too big for a 45F; get basic V9958 working first). `check_timing.py` is a handy timing helper.
