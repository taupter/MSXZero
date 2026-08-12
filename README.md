# MSXZero — an MSX2+ computer on the Lattice ECP5 (IcePi Zero 45F)

**Status: work in progress — builds, not yet run on hardware.**
The whole core now **synthesizes, fits the 45F (78% logic), routes, and packs to a bitstream**
on the open-source toolchain. What's left before it runs a real MSX2+: the 16-bit SDRAM
adapter, `clk_54m` (Z80) timing closure, and on-hardware bring-up. See the progress tables below.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano), being ported from the
**Tang Nano 20K (Gowin)** to the **IcePi Zero (ECP5, 45F)** on the MiSTle **icepi_carrier**.

## Progress

### Table 1 — a first working fork (boot MSX2+ on the IcePi Zero)

These are the items needed to get a real MSX2+ running on hardware. This is the goal.

| Stage | Status | Done |
|---|---|---|
| Research / target lock-in (IcePi Zero + carrier) | complete | 100% |
| Open-source toolchain (Yosys + nextpnr-ecp5 + ghdl) | installed & verified | 100% |
| Clocks / PLL (`EHXPLLL`, 50→107.69/134.6/26.92/53.85) | synthesizes; phase to tune on HW | 90% |
| Video output (ECP5 GPDI/TMDS) | RTL done, untested | 85% |
| Constraints (`icepi.lpf`) | mapped; flash `USRMCLK` pending | 90% |
| Gowin-primitive cleanup (BUFG, file list) | done | 85% |
| Full synthesis (compile the whole design) | **done** — the whole core maps to ECP5 primitives with the open-source flow | 100% |
| Fit on the 45F (nextpnr place & route) | **fits + routes + packs to a .bit**: 78% logic (34360/43848 LUT4), 29% FF, 16% BRAM (18/108), 12% DSP (9/72), 1 PLL | 90% |
| Bitstream (ecppack) | **done** — full flow RTL→synth→P&R→`msx_ecp5.bit` (~683 KB) | 100% |
| `clk_54m` (Z80) timing closure | routes but ~30–36 vs 53.85 MHz — abc9/multicycle/retiming | 20% |
| SDRAM controller (16-bit) | **narrow memory.v to 16-bit** (not wrap NanoMig). **memtest PASSES** in sim (`fpga/sim/`, iverilog 4-state): CPU write→read round-trips across byte lanes, rows, high bits (2 MB), no aliasing. Validated the read-path fix + byte lanes. Remaining: VDP-port memtest + optional 13/9 geometry + on-HW phase tuning. `fpga/SDRAM_PORT.md`, `fpga/sim/README.md` | ~60% |
| On-hardware bring-up (HDMI / SDRAM / companion / DB9) | not started | 0% |
| **Beta 1 overall** | **synthesizes + fits the 45F; SDRAM + bring-up ahead** | **~45%** |

### Table 2 — future features (after the fork boots)

Post-Beta-1 additions. The 45F fit above leaves ~22% LUT headroom + lots of free BRAM/DSP,
which is why the sample-based OPL4 is comfortable but the LUT-heavy V9968 is a coin-flip.

| Feature | Status | Done |
|---|---|---|
| OPL4 / MoonSound (`YMF278B`) | core vendored (`fpga/opl4wave/`), not wired; needs ECP5 wave-ROM memory + an OPL3 FM core | 5% |
| OPL4 "super hi-res" samples (interpolation option) | idea only — cheap on the 45F, keep as A/B toggle vs authentic | 0% |
| V9968 (accurate V9958, HRA!) | evaluate — LUT-heavy, tight at 78% base; measure standalone first | 0% |
| MSXimus cherry-picks (test_hdmi / test_sdram harnesses, board abstraction) | noted in PORT_PLAN | 0% |
| **Real cartridge slot** | a physical MSX cartridge edge connector — **not on the IcePi Zero** (no pins / 5V shifting), only when the project moves to a dedicated board. The core already has the interface (`ex_bus_*`/pinfilter in top.v, tied off now); the dedicated board wires it to real bidirectional IO through level shifters | 0% |

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

**Done — the core builds and fits:**
- **The whole core synthesizes, fits, and packs to a bitstream** on the open-source flow
  (Yosys + ghdl + nextpnr-ecp5 → `ecppack`). On the **LFE5U-45F**: **78% logic** (34360/43848
  LUT4), 29% flip-flops, 16% block RAM, 12% DSP, 1 PLL — so the base MSX2+ fits with room to spare.
- Clocks — `clocks_ecp5.v`: one `EHXPLLL` from the 50 MHz osc → 107.69 (sys) / 134.6 (TMDS) /
  26.92 (pixel) / 53.85 MHz. (Exact 108 MHz isn't reachable from 50 MHz without an out-of-spec
  2 MHz phase detector; the system runs 0.28% low — within HDMI tolerance, imperceptible for MSX.)
- Video output — `serializer_ecp5.sv`: ECP5 `ODDRX1F` GPDI, replacing the Gowin `OSER10` + `ELVDS_OBUF`.
- Constraints — `icepi.lpf`: clock, GPDI, 16-bit SDRAM, SD, flash, LEDs, buttons, companion SPI, DB9 joysticks.
- DB9 joysticks read natively by the PSG (added in this port), plus the RP2350 companion over SPI.
- **Mixed-language build** — the tricky part. The SystemVerilog HDMI encoder is pre-converted with
  **sv2v** (yosys can't parse its unpacked-array ports / `real` params); each VHDL boundary entity is
  elaborated with **ghdl** and flattened to RTLIL (ghdl's `-read` crashes on multiple VHDL modules);
  LUTs are mapped with **classic abc** (abc9 false-positives on the design's internal tri-state).
  A dozen source nits Gowin silently tolerated are fixed (package shared-variables, `real`→integer
  math, an async-load PSG envelope, a PSG tri-state loop, port-name case, a missing instance name).
  See `fpga/build_ecp5.sh` + `BUILD_ECP5.md`.

**In progress / remaining:**
- **`clk_54m` (Z80) timing** — the design routes but this domain runs ~30–36 vs the 53.85 MHz target
  (the T80 has long combinational paths). Options: abc9 once tri-state is resolved, a multicycle
  constraint (the CPU is clock-enabled), or retiming.
- **SDRAM (16-bit)** — decision made: **narrow the existing `memory.v`** (which already has the proven
  MSX CPU/VDP dot-clock interleaving) to 16-bit, rather than wrap NanoMig's generic controller. NanoMig
  confirms the IcePi geometry (13-row/9-col). The ECP5 read path is fixed (Gowin inferred the SDRAM and
  fed reads back into a reg; ECP5 must read the real bus). Geometry fix + a memtest simulation (`fpga/sim/`)
  are in progress. See `fpga/SDRAM_PORT.md`.
- Flash config clock (`mspi_sclk` → ECP5 `USRMCLK`); on-hardware bring-up (HDMI picture, SDRAM memtest,
  SD/Nextor boot, companion keyboard). The board is the last-mile validation — nothing here is silicon-tested yet.
- **OPL4 / MoonSound** and other extras — see the "future features" table above and `PORT_PLAN.md`.

## Building

Open-source flow: `cd fpga && ./build_ecp5.sh` (needs the OSS CAD Suite). Details: `fpga/BUILD_ECP5.md`.
Roadmap: `PORT_PLAN.md`. SDRAM plan: `fpga/SDRAM_PORT.md`.

## References & credits

Based on Papipapito/MSXnano ← jabadiagm/MSXgoauldSD_tn20k. **GPL-3.0** (`LICENSE`).
Platform references (same IcePi hardware): NanoMig IcePi port, `cheyao/icepi-zero`.
OPL4 core vendored from [Papipapito/MSXimus](https://github.com/Papipapito/MSXimus) (GPL-3.0).
`jtopl` FM cores by jotego (GPL-3.0). Upstream README kept as `README.upstream.md`.

Parts of this port were done with assistance from Claude (an AI coding assistant).
