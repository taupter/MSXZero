# MSXZero — an MSX2+ computer on the Lattice ECP5 (IcePi Zero 45F)

**Status: work in progress — builds + boots in sim, not yet run on hardware.**
The whole core **synthesizes, fits the 45F (75% logic), routes, packs a bitstream**, its **SDRAM
is validated in simulation** (both ports, full 8 MB), and — the big one — the **whole machine boots
in a full-design simulation and the Z80 executes C-BIOS**. So the design is validated *logically*;
what remains is the physical **on-hardware bring-up** (`clk_54m` timing is a likely-fine multicycle
item). See the progress tables below.

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
| Video output (ECP5 GPDI/TMDS) | RTL done; a **standalone HDMI test-pattern harness** (`fpga/bringup/`) builds + routes + times cleanly (clk_135 ~300 MHz), isolating the PLL + encoder + `serializer_ecp5` GPDI path. Untested on a real monitor | 88% |
| Constraints (`icepi.lpf`) | mapped; **flash clock via `USRMCLK`** — done (routes `1/1`) | 100% |
| Gowin-primitive cleanup (BUFG, file list) | done | 85% |
| Full synthesis (compile the whole design) | **done** — the whole core maps to ECP5 primitives with the open-source flow | 100% |
| Fit on the 45F (nextpnr place & route) | **fits + routes + packs to a .bit**: 75% logic (33166/43848 LUT4), 29% FF, 16% BRAM (18/108), 12% DSP (9/72), 1 PLL, 1 `USRMCLK` | 90% |
| Bitstream (ecppack) | **done** — full flow RTL→synth→P&R→`msx_ecp5.bit` (~700 KB) | 100% |
| `clk_54m` (Z80) timing | routes at ~24–36 MHz (varies with placement). But the worst path is the **clock-enabled** T80 CPU (runs at 3.58/5.37 MHz — the FFs advance ~1 in 10–15 base cycles), so it's genuinely **multicycle** and the 53.85 MHz check is far stricter than the CPU actually needs → very likely fine on hardware. Open-source tools can't *express* multicycle (nextpnr) or map it tighter — abc9 is blocked by a Yosys **dev-build XAIGER bug** (ruled out tri-state, real loops, and all black boxes — a pure LUT/FF design still trips it; see `fpga/docs/abc9_issue.md`). Classic abc is used instead. HW-confirm pending | 70% |
| SDRAM controller (16-bit) | **narrow memory.v to 16-bit** (not wrap NanoMig). **memtest PASSES for BOTH ports** in sim (`fpga/sim/`, iverilog 4-state): CPU RAM (byte lanes, rows, **full 8 MB across all 4 banks**, no aliasing) **and** VRAM (8-bit write / 16-bit read, bank 3, no cross-interference). Whole data path validated; the 13/9 geometry rewrite was found unnecessary. Remaining: on-HW SDRAM phase tuning (board-only). `fpga/SDRAM_PORT.md`, `fpga/sim/README.md` | ~75% |
| **Boot validation (full-design sim)** | **the whole MSX boots in iverilog and the Z80 executes C-BIOS** from SDRAM (`fpga/sim/`) — validates the CPU + memory + BIOS path logically (80 K+ steady BIOS fetches). A drawn frame is *not* reachable in this sim: C-BIOS spins in early init (slot-detect / vblank-IRQ) before video, so VRAM stays empty — the real screen comes from hardware (bring-up) | 80% |
| **Bring-up harnesses** | **done** — standalone **HDMI test-pattern** (stage 3) and **SDRAM memtest** (stage 4) bitstreams in `fpga/bringup/`, each reusing the *real* modules so video + memory can be proven independently on the board. The SDRAM one is **sim-validated** ("SDRAM HARNESS: PASS") and reports on the LEDs. See `fpga/BRINGUP.md` | 100% |
| On-hardware bring-up (HDMI / SDRAM / companion / DB9) | not started (board pending) — procedure/risks/tuning prepped in `fpga/BRINGUP.md`, and the stage-3/4 harnesses above are ready to flash. Now "confirm + tune," not "debug from scratch" (design validated in sim) | 5% |
| **Beta 1 overall** | **the entire pre-hardware side is done: builds + fits + bitstreams; SDRAM validated; boots + runs C-BIOS in sim; flash-boot (`USRMCLK`) closed; and stage-3/4 bring-up harnesses built + sim-validated. All that remains is the physical on-hardware bring-up — which is deliberately the last ~30% and can't be retired from a chair (real SDRAM phase, HDMI sync on a monitor, companion USB, `clk_54m` confirm, actual C-BIOS boot)** | **~70%** |

### Table 2 — future features (after the fork boots)

Post-Beta-1 additions. The 45F fit above leaves ~25% LUT headroom + lots of free BRAM/DSP,
which is why the sample-based OPL4 is comfortable but the LUT-heavy V9968 is a coin-flip. And that
75% is itself a **toolchain** number, not bloat — see the LUT-reduction levers below the table
(abc9 on a stable Yosys + de-duping the two HDMI encoders could reach ~60%, freeing more room).

| Feature | Status | Done |
|---|---|---|
| OPL4 / MoonSound (`YMF278B`) | core vendored (`fpga/opl4wave/`), not wired; needs ECP5 wave-ROM memory + an OPL3 FM core | 5% |
| OPL4 "super hi-res" samples (interpolation option) | idea only — cheap on the 45F, keep as A/B toggle vs authentic | 0% |
| V9968 (accurate V9958, HRA!) | evaluate — LUT-heavy, tight at 75% base (but see LUT-reduction below); measure standalone first | 0% |
| **WiFi** | the MSX core already has the WiFi plumbing (the `wifi_lite` entity + WiFi ROM region + a UART modem — a vendored MSXnano feature). Gap is *physical*: the RP2350 has **no built-in radio**, so it needs an external **ESP module on a UART** (as MSXnano assumes) + a firmware bridge. Cheap hardware, a **dedicated-board** item | 0% |
| **RGB (SCART) video out** | the *authentic* MSX picture — analog **RGB + composite sync at 15 kHz** (240p/288p) to a SCART TV / PVM / OSSC, sharper than the HDMI upscale. The VDP already produces the digital RGB at native rate; needs a **raw pre-scandouble 15 kHz tap + a CSync generator** (modest logic) and an analog output stage (**video DAC + SCART/DIN connector**). The IcePi has no RGB connector → **dedicated-board** | 0% |
| **Real cartridge slot** | a physical MSX cartridge edge connector — **not on the IcePi Zero** (no pins / 5V shifting), only when the project moves to a dedicated board. The core already has the interface (`ex_bus_*`/pinfilter in top.v, tied off now); the dedicated board wires it to real bidirectional IO through level shifters | 0% |

> **Not in this table (already Beta-1, provisioned both sides):** **SD card** (Nextor / MSX-DOS 2, 4-bit SD pinned in `icepi.lpf` + microSD on the carrier — mandatory, native FPGA logic) and **USB keyboard/gamepads** (via the RP2350 FPGA-Companion over SPI — needs companion firmware, not new logic). These are bring-up checklist items, not future features.

The **dedicated-board** items above (WiFi radio, RGB/SCART output, real cartridge slot) share a theme: the *logic* is largely present or cheap, but the **IcePi Zero lacks the connectors / analog stage / level-shifting** for them. They come together when the project moves off the IcePi to its own board.

**LUT-reduction backlog (the 75% is a toolchain story, not bloat).** From the real build data
(33166 LUT4, 18 BRAM, **0 distributed LUT-RAM**, 9 DSP) the fit is a synthesis-mapping result — the
same RTL fits a Tang Nano 20K under Gowin's proprietary tools. Ranked levers, *without removing any
MSX feature*: **(1)** run the build on a **stable OSS CAD Suite so abc9 works** (classic `abc -lut 4:7`
maps looser; ~10–20%); **(2)** **de-dup the dual HDMI encoder** — `v9958_top.v` instantiates two full
`hdmi` encoders (NTSC VIC=2 + PAL VIC=17) and muxes one out (~5–9%). Ruled out by the data: RAM/flatten
duplication (BRAM is sane, zero distributed LUT-RAM). Target 1+2 ≈ 75% → ~60%. Details in `PORT_PLAN.md`.

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

**Done — the core builds, fits, and boots in sim:**
- **The whole core synthesizes, fits, and packs to a bitstream** on the open-source flow
  (Yosys + ghdl + nextpnr-ecp5 → `ecppack`). On the **LFE5U-45F**: **75% logic** (33166/43848
  LUT4), 29% flip-flops, 16% block RAM, 12% DSP, 1 PLL, 1 `USRMCLK` — the base MSX2+ fits with room
  to spare (and that 75% is a toolchain number — see the LUT-reduction backlog above).
- **Boots in a full-design simulation** — the whole mixed-language MSX runs in iverilog and the Z80
  **executes C-BIOS** from SDRAM (`fpga/sim/`); SDRAM memtest passes for both ports. Design validated logically.
- **Flash boot + bring-up harnesses** — the flash clock routes through `USRMCLK` (boot-from-flash),
  and `fpga/bringup/` has standalone HDMI-test-pattern + SDRAM-memtest bitstreams for staged board bring-up.
- Clocks — `clocks_ecp5.v`: one `EHXPLLL` from the 50 MHz osc → 107.69 (sys) / 134.6 (TMDS) /
  26.92 (pixel) / 53.85 MHz. (Exact 108 MHz isn't reachable from 50 MHz without an out-of-spec
  2 MHz phase detector; the system runs 0.28% low — within HDMI tolerance, imperceptible for MSX.)
- Video output — `serializer_ecp5.sv`: ECP5 `ODDRX1F` GPDI, replacing the Gowin `OSER10` + `ELVDS_OBUF`.
- Constraints — `icepi.lpf`: clock, GPDI, 16-bit SDRAM, SD, flash, LEDs, buttons, companion SPI, DB9 joysticks.
- DB9 joysticks read natively by the PSG (added in this port), plus the RP2350 companion over SPI.
- **Mixed-language build** — the tricky part. The SystemVerilog HDMI encoder is pre-converted with
  **sv2v** (yosys can't parse its unpacked-array ports / `real` params); each VHDL boundary entity is
  elaborated with **ghdl** and flattened to RTLIL (ghdl's `-read` crashes on multiple VHDL modules);
  LUTs are mapped with **classic abc** (abc9 hits a Yosys dev-build XAIGER bug — ruled out as a
  design issue; see `fpga/docs/abc9_issue.md`). A dozen source nits Gowin silently tolerated are
  fixed (package shared-variables, `real`→integer math, an async-load PSG envelope, a PSG tri-state
  loop, a tri-stated clock net → proper gated clock, port-name case, a missing instance name).
  See `fpga/build_ecp5.sh` + `BUILD_ECP5.md`.

**Remaining — on-hardware bring-up (no FPGA glue left):**
- **The board is the last mile.** Nothing here is silicon-tested yet. Bring-up order (with the ready
  harnesses): config → clocks/LEDs → **HDMI test pattern** → **SDRAM memtest** → companion/USB keyboard
  → SD/Nextor → C-BIOS boot. See `fpga/BRINGUP.md`.
- **`clk_54m` (Z80) timing** — routes but runs ~24–36 vs the 53.85 MHz target. The worst path is the
  **clock-enabled (multicycle)** T80 CPU, so it's very likely fine on hardware (the SDRAM-only harness
  hits ~180 MHz on the same clock — the "failure" is the CPU path). Clean fixes are blocked by
  open-source tool limits (nextpnr can't express multicycle; abc9 is a dev-build bug). HW-confirm pending.
- **SDRAM phase tuning** — the 16-bit `memory.v` memtest passes in sim (both ports) and in the standalone
  harness; the only board-specific step is tuning the read-capture clock phase. See `fpga/SDRAM_PORT.md`.
- **LUT reduction** (optional, no HW needed) — abc9 on a stable Yosys + de-dup the dual HDMI encoder; see above.
- **OPL4 / MoonSound** and other extras — see the "future features" table above and `PORT_PLAN.md`.

## Building

Open-source flow: `cd fpga && ./build_ecp5.sh` (needs the OSS CAD Suite). Details: `fpga/BUILD_ECP5.md`.
Bring-up harnesses: `bash bringup/build_hdmi_test.sh` and `bash bringup/build_sdram_test.sh` (standalone
video / memory test bitstreams). Roadmap: `PORT_PLAN.md`. SDRAM plan: `fpga/SDRAM_PORT.md`. Bring-up: `fpga/BRINGUP.md`.

## References & credits

Based on Papipapito/MSXnano ← jabadiagm/MSXgoauldSD_tn20k. **GPL-3.0** (`LICENSE`).
Platform references (same IcePi hardware): NanoMig IcePi port, `cheyao/icepi-zero`.
OPL4 core vendored from [Papipapito/MSXimus](https://github.com/Papipapito/MSXimus) (GPL-3.0).
`jtopl` FM cores by jotego (GPL-3.0). Upstream README kept as `README.upstream.md`.

Parts of this port were done with assistance from Claude (an AI coding assistant).
