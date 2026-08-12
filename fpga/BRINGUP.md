# MSXZero hardware bring-up checklist (IcePi Zero + icepi_carrier)

The plan is to bring the board up **one subsystem at a time**, in an order where each stage
proves the next stage's prerequisites. Don't jump to "boot MSX" — if it doesn't work you won't
know which of ten things failed. Everything below is validated in synthesis/sim; this is the
first time on silicon, so treat each stage as a real experiment.

Board facts (from `icepi.lpf`): 50 MHz osc on **M1**; 5 LEDs `led[0..4]` (E13/D14/E12/C13/D13);
buttons **s1** user (C5), **s2** reset (C4); UART **tx=K15 / rx=K16** (IcePi FTDI); WS2812 on J3;
GPDI clk/data pairs; 16-bit SDRAM; SD on P15/N16; RP2350 companion over SPI.

## 0. Build the bring-up bitstream (status LEDs) FIRST
The single highest-value bring-up aid — with no monitor/keyboard working yet, the LEDs are your
only window. Already wired behind `BRINGUP_LEDS` (active-low, 0 = lit):
- `led[0]` solid = **PLL locked** (clocks up)   · `led[1]` blinking = **clocks running** (heartbeat)
- `led[2]` flicker = **SDRAM activity**   · `led[3]` = reset released   · `led[4]` = flash config idle

```
EXTRA_DEFINES=-DBRINGUP_LEDS ./build_ecp5.sh     # -> msx_ecp5.bit with status LEDs
```
This turns "nothing happens" into "clocks + SDRAM are up, so video is the problem." Do the whole
bring-up on this bitstream; rebuild without the define once it boots. (Default build keeps the
normal joystick/SD LEDs.)

## 1. Configure the FPGA
```
cd fpga && ./build_ecp5.sh          # produces msx_ecp5.bit
openFPGALoader -b <icepi-zero>  msx_ecp5.bit      # SRAM (volatile, fast iterate)
# or flash it: openFPGALoader -f -b <icepi-zero> msx_ecp5.bit
```
Tools present: `openFPGALoader`, `ecpprog`, `fujprog`, `openocd`. Confirm the board's `DONE`
goes active (config succeeded). If config fails: check `SYSCONFIG` in the lpf and the flash clock
(`mspi_sclk` must go through **USRMCLK**, not a pin — pending item).
✅ Pass = board configures, DONE active.

## 2. Clocks / PLL lock
The whole design hangs off one `EHXPLLL` (50 → 107.69/134.6/26.92/53.85 MHz). If the heartbeat
LED (stage 0) blinks, clocks are alive. Without LEDs, you're flying blind until HDMI.
✅ Pass = heartbeat blinks (or, next stage, HDMI syncs at all).

## 3. HDMI test pattern — FIRST BIG MILESTONE
This proves PLL + pixel/TMDS clocks + the `serializer_ecp5` GPDI path in one shot. Expect
**720×480 @ ~59.94 Hz** (NTSC). Notes:
- The system runs **0.28% low** (107.69 not 108 MHz) — inside HDMI tolerance; most monitors lock
  fine. If a picky monitor won't sync, try another display first before suspecting the design.
- Wrong colors / shifted image ⇒ GPDI pair mapping or TMDS bit order.
- No signal at all ⇒ PLL/serializer; recheck stage 2.
✅ Pass = a stable picture on the monitor (even garbage VRAM is fine — it means video works).

## 4. SDRAM — the "never works first try" stage
Memtest **passes in sim** (`fpga/sim/`), so the controller *logic* is right. The board risk is
**physical read-capture timing**: the `clk_108m`→SDRAM data path phase. Symptoms of a phase
problem: video shows garbage that never resolves, or the MSX boots but crashes/corrupts.
- Tuning knob: the SDRAM clock phase (a phase-shifted PLL output for capture, a.k.a. CPHASE).
  If reads are flaky, sweep the SDRAM output-clock phase (or the capture register clock) in small
  steps. This is *the* classic ECP5-SDRAM bring-up chore — expect to spend time here.
- A HW memtest (LED pass/fail, or over the UART) is worth adding before trusting boot.
✅ Pass = HW memtest clean across CPU + VRAM regions.

## 5. Companion (RP2350 over SPI) → USB keyboard
SPI on `spi_sclk=L1` etc. Confirms the FPGA↔RP2350 link, then USB HID keyboard + the on-screen
menu. Needs the companion firmware running on the carrier's RP2350.
✅ Pass = keypresses reach the core (menu responds).

## 6. Boot the MSX — THE milestone
BIOS + sub-ROM → MSX BASIC prompt; then SD/Nextor for disks. If stages 3–5 pass and it still
won't boot, the prime suspects are (a) SDRAM phase (stage 4), and (b) the **`clk_54m` (Z80)
timing** — it routes ~30–36 MHz vs the 53.85 MHz constraint. That path is the *clock-enabled*
(multicycle) CPU and should be fine, but if you see random crashes/instability that clean SDRAM
doesn't explain, that's the place to look (drop the CPU turbo, or revisit abc9 — see
`docs/abc9_issue.md`).
✅ Pass = MSX BASIC prompt, then a disk boots from SD.

## Known risks / things to verify on HW (quick reference)
| Item | Risk | Where |
|---|---|---|
| SDRAM read-capture phase | flaky reads / crashes | stage 4, tune SDRAM clock phase |
| `clk_54m` Z80 timing | CPU instability (likely OK — multicycle) | stage 6; `docs/abc9_issue.md` |
| HDMI 0.28% low | picky monitor won't sync | stage 3 |
| DB9 joystick bit order | directions/buttons swapped | ASSUMPTION in top.v — verify, swap if needed |
| Flash config clock (USRMCLK) | won't boot from flash | stage 1 (mspi_sclk → USRMCLK, pending) |
| DB9 5V vs 3.3V | (per carrier 74LCX07 buffers — OK) | carrier handles level shifting |

## Debug resources on the board
- **5 LEDs** — wire status/heartbeat (stage 0). Your primary no-monitor debug.
- **UART (K15/K16)** — the core has a UART; print init progress / memtest results.
- **s2** = reset, **s1** = user button.
- **WS2812 (J3)** — a second status indicator.
