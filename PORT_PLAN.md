# MSXZero — port roadmap (Lattice ECP5-45F)

Fork of `Papipapito/MSXnano` (MSX2+ for Tang Nano 20K / Gowin). Goal: keep the MSX2+ core
(Z80, V9958, SCC/OPLL, Nextor) and swap the Gowin platform layer for ECP5, on the
open-source toolchain. Practice project. Detailed docs: `fpga/BUILD_ECP5.md` (build),
`fpga/SDRAM_PORT.md` (memory), `fpga/BRINGUP.md` (hardware), `fpga/sim/README.md` (memtest),
`fpga/docs/abc9_issue.md` (a toolchain known-issue). Live progress tables are in the top `README.md`.

Scope note: the fork also emulates ColecoVision + Sega SG-1000 (they reuse the Z80/VDP/PSG).
Kept as-is — the port is purely the platform layer.

## Target hardware
IcePi Zero XL (ECP5, 45F) on the MiSTle icepi_carrier — the tested board. RP2350 on the
carrier = FPGA Companion (keyboard/SD/OSD). 50 MHz osc on pin `M1`.

## Where it stands (the paper machine is done; hardware is next)
| Front | State |
|---|---|
| Clocks / PLL | `src/lattice/clocks_ecp5.v` — one `EHXPLLL`, 50 → 107.69/134.6/26.92/53.85 MHz |
| Constraints | `icepi.lpf` (clk, GPDI, 16-bit SDRAM, SD, flash, LEDs, buttons, companion SPI, DB9) |
| Video out | `serializer_ecp5.sv` — ECP5 `ODDRX1F` GPDI (replaces Gowin OSER10 + ELVDS_OBUF) |
| Mixed-language build | sv2v (SV) + ghdl→RTLIL per-module flatten (VHDL) + classic abc → `build_ecp5.sh` |
| Synthesis + fit + bitstream | 75% LUT on the 45F (+1 USRMCLK), routes, `msx_ecp5.bit` |
| SDRAM (16-bit) | memtest passes in sim, both CPU + VRAM ports (narrowed `memory.v`, not NanoMig) |
| Boot-in-sim (C-BIOS) | the whole MSX boots in iverilog and the Z80 executes C-BIOS from SDRAM (`tb_frame.v`). Frame render is the last mile |
| `mspi_sclk` → `USRMCLK` | flash config clock routed through the ECP5 `USRMCLK` primitive (`1/1`) — can boot from flash |
| `clk_54m` (Z80) timing | routes ~24–36 vs 53.85 MHz — multicycle CPU, likely OK on HW (abc9 blocked, see docs) |
| On-hardware bring-up | not started (board pending) — full procedure in `BRINGUP.md` |

Key decisions made along the way:
- SDRAM: narrow `memory.v`'s proven MSX CPU/VDP dot-clock interleaving to 16-bit — do NOT
 wrap NanoMig's generic controller (would mean rebuilding the MSX timing). NanoMig only confirms
 the IcePi geometry (13-row/9-col). See `SDRAM_PORT.md`.
- LUT mapping: classic `abc` (abc9 hits a Yosys dev-build XAIGER bug; `docs/abc9_issue.md`).

## Next (no hardware needed)
- Boot-in-sim — done: the whole MSX runs in iverilog (`gen_full_sim.sh` + `tb_frame.v`), and with
 C-BIOS pre-loaded the Z80 executes it (`bios_reads` climbs). Remaining last-mile: run long
 enough for the VDP to draw (first VRAM write) and render `vram_dump.txt` to an image. C-BIOS init is
 long; an 80 ms run confirmed C-BIOS spins in early init (VRAM stays empty) — the drawn screen needs
 hardware (or a slot-detect/vblank-IRQ debug in the flattened netlist). See `fpga/sim/README.md`.
- `mspi_sclk` → `USRMCLK` — done (flash config clock routes through USRMCLK).
- Bring-up harnesses — done: `bringup/` has a standalone HDMI test-pattern (stage 3) and
 SDRAM memtest (stage 4), each building to its own bitstream; the SDRAM one is sim-validated
 ("SDRAM HARNESS: PASS"). They isolate the video + memory paths for fast board bring-up. See `BRINGUP.md`.
- Next doable-now: the LUT-reduction backlog above (abc9 on a stable OSS CAD Suite + de-dup the
 dual HDMI encoder) — measured before/after. Everything else waits for the board.

## Next (needs the board — see `BRINGUP.md`)
Bring-up order: config → clocks (status LEDs) → HDMI test pattern → SDRAM phase tuning →
companion/keyboard → MSX boot. Then SD/Nextor.

## Board-abstraction refactor (post-Beta-1)
MSXZero already runs on the MiSTle project's hardware — the icepi_carrier and the RP2350 FPGA
Companion, the same board and companion NanoMig runs on. It is not an official MiSTle core, and it
isn't structured like the MiSTle cores yet: the platform layer is hand-ported inline (`clocks_ecp5`,
`serializer_ecp5`, narrowed `memory.v`) via scattered `` `ifdef ECP5`` rather than sitting on a
shared board wrapper.

Since the carrier is shared, adopting the same board-abstraction layout is worth doing. Plan (after
the fork boots on hardware — refactor a known-good design, not a moving target):
1. Use the NanoMig top from `MiSTle-Dev/NanoMig` as a concrete reference for the carrier wiring
   (PLL, SDRAM, GPDI, SD, companion SPI) — it targets the exact same board.
2. Extract a `board_top` exposing a canonical board interface (clk/reset, SDRAM, RGB+audio,
   companion SPI, SD, joysticks); split the platform code into `board/gowin/` + `board/ecp5/` so the
   MSX core connects only to that interface (no inline `` `ifdef ECP5``).
3. Follow the FPGA-Companion menu/config conventions the carrier's RP2350 firmware expects.
Payoff: one core codebase targets both boards (Tang Nano + IcePi Zero XL, plus a future dedicated
board), and the platform layer stays clean and swappable.

## After Beta 1 — two tracks (see README "Roadmap")
The project splits into two streams. Track 1 is the devboard core anyone can run on an
off-the-shelf IcePi Zero XL + icepi_carrier (Beta 1 boots it; devboard-fit features follow).
Track 2 is a purpose-built MSX board for the features the devboard can't physically provide.

### Track 1 — devboard additions (fit the IcePi Zero XL)
- OPL4 / MoonSound — core vendored in `fpga/opl4wave/`; needs ECP5 wave-ROM memory + an OPL3 FM core.
- OPL4 hi-res sample option — interpolation/oversampling toggle vs authentic.
- V9968 (accurate V9958) — LUT-heavy, tight at 75% (see LUT-reduction backlog); measure standalone first.
- Turbo-R / R800 — a whole new (fast) CPU; big-ticket, same tight-fit category as V9968.

Already on the devboard (not future work): SD card (Nextor/MSX-DOS 2 — 4-bit SD pinned + microSD on
carrier) and USB keyboard/gamepads (RP2350 companion over SPI). Both provisioned; bring-up items.

### Track 2 — dedicated MSX board (beyond the devboard)
Logic is present or cheap in every case; the IcePi just lacks the connectors / analog stage / level-shifting.
- Real cartridge slot — physical MSX edge connector; the `ex_bus_*` interface is tied off on the IcePi,
  the dedicated board wires it to real bidirectional IO through level shifters.
- RGB (SCART) video out — the authentic 15 kHz MSX picture. VDP already makes the RGB; needs a
  raw pre-scandouble 15 kHz tap + CSync generator (modest logic) + an analog stage (video DAC + SCART).
- WiFi — the core has the modem plumbing (`wifi_lite` + WiFi ROM + UART modem). The radio hardware
  is not decided: options are an external module on a UART (an ESP, for example) or a WiFi-capable
  companion. TBD.

## LUT-reduction backlog (75% is a toolchain story, not bloat)
From the real build data (nextpnr util: 33166 LUT4, 18 BRAM, 0 distributed LUT-RAM, 9 DSP), ranked
by evidence — savings are without removing any MSX feature:
1. abc9 on a stable OSS CAD Suite (~10–20%) — classic `abc -lut 4:7` maps looser than abc9; abc9 is
 blocked only by a Yosys dev-build XAIGER bug (`docs/abc9_issue.md`). Rebuild on a tagged release.
2. De-dup the dual HDMI encoder (~5–9%) — `v9958_top.v` instantiates TWO full `hdmi` encoders
 (`hdmi_ntsc` VIC=2 + `hdmi_pal` VIC=17) and muxes one out (`pal_mode ? tmds_pal : tmds_ntsc`). The
 encoder carries audio/data-island/BCH/TERC4 — collapse to one parameterized instance.
3. Per-module attribution build (synth VDP / T80 / audio standalone) — diagnostic, if 1+2 aren't enough.
- Ruled out by data: RAM/flatten duplication — BRAM is sane and there is zero distributed LUT-RAM,
 so memories infer to block RAM correctly; the LUTs are genuine logic. Don't chase this.
Target: 1+2 together ≈ 75% → ~60%. Why bigger than the TN20K: Gowin's proprietary synth + native
primitives pack this RTL tighter than yosys + classic abc — a mapping story, plus the one real dup.
