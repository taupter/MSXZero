# MSXZero — port roadmap (Lattice ECP5-45F)

Fork of `Papipapito/MSXnano` (MSX2+ for Tang Nano 20K / Gowin). Goal: keep the MSX2+ core
(Z80, V9958, SCC/OPLL, Nextor) and swap the **Gowin platform layer** for **ECP5**, on the
open-source toolchain. Practice project. Detailed docs: `fpga/BUILD_ECP5.md` (build),
`fpga/SDRAM_PORT.md` (memory), `fpga/BRINGUP.md` (hardware), `fpga/sim/README.md` (memtest),
`fpga/docs/abc9_issue.md` (a toolchain known-issue). Live progress tables are in the top `README.md`.

**Scope note:** the fork also emulates ColecoVision + Sega SG-1000 (they reuse the Z80/VDP/PSG).
Kept as-is — the port is purely the platform layer.

## Target hardware
**IcePi Zero** (ECP5, 45F) on the **MiSTle icepi_carrier** — the tested board. RP2350 on the
carrier = FPGA Companion (keyboard/SD/OSD). 50 MHz osc on pin `M1`.

## Where it stands (the paper machine is done; hardware is next)
| Front | State |
|---|---|
| Clocks / PLL | ✅ `src/lattice/clocks_ecp5.v` — one `EHXPLLL`, 50 → 107.69/134.6/26.92/53.85 MHz |
| Constraints | ✅ `icepi.lpf` (clk, GPDI, 16-bit SDRAM, SD, flash, LEDs, buttons, companion SPI, DB9) |
| Video out | ✅ `serializer_ecp5.sv` — ECP5 `ODDRX1F` GPDI (replaces Gowin OSER10 + ELVDS_OBUF) |
| Mixed-language build | ✅ sv2v (SV) + ghdl→RTLIL per-module flatten (VHDL) + classic abc → `build_ecp5.sh` |
| **Synthesis + fit + bitstream** | ✅ 78% LUT on the 45F, routes, `msx_ecp5.bit` |
| **SDRAM (16-bit)** | ✅ **memtest passes in sim, both CPU + VRAM ports** (narrowed `memory.v`, not NanoMig) |
| `clk_54m` (Z80) timing | ⏳ routes ~30–36 vs 53.85 MHz — multicycle CPU, likely OK on HW (abc9 blocked, see docs) |
| On-hardware bring-up | ⏳ not started (board pending) — full procedure in `BRINGUP.md` |
| `mspi_sclk` → `USRMCLK` | ⏳ flash config clock, needed to boot from flash |

Key decisions made along the way:
- **SDRAM:** narrow `memory.v`'s proven MSX CPU/VDP dot-clock interleaving to 16-bit — do NOT
  wrap NanoMig's generic controller (would mean rebuilding the MSX timing). NanoMig only confirms
  the IcePi geometry (13-row/9-col). See `SDRAM_PORT.md`.
- **LUT mapping:** classic `abc` (abc9 hits a Yosys dev-build XAIGER bug; `docs/abc9_issue.md`).

## Next (no hardware needed)
- `mspi_sclk` → `USRMCLK`.

## Next (needs the board — see `BRINGUP.md`)
Bring-up order: **config → clocks (status LEDs) → HDMI test pattern → SDRAM phase tuning →
companion/keyboard → MSX boot.** Then SD/Nextor.

## Future features (post-Beta-1 — see README "Table 2")
- **OPL4 / MoonSound** — core vendored in `fpga/opl4wave/`; needs ECP5 wave-ROM memory + an OPL3 FM core.
- **OPL4 hi-res sample option** — interpolation/oversampling toggle vs authentic.
- **V9968** (accurate V9958) — LUT-heavy, tight at 78%; measure standalone first.
- **Real cartridge slot** — only on a dedicated board (the `ex_bus_*` interface is tied off on the IcePi).
- **Turbo-R / R800** — a whole new (fast) CPU; big-ticket, same tight-fit category as V9968.
