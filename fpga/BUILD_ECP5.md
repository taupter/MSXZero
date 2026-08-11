# ECP5 build recipe (IcePi Zero 45F)

The port keeps the Gowin build working: every ECP5 change is behind `` `ifdef ECP5``, and the
ECP5-specific modules live in `src/lattice/`. To build for the IcePi Zero you must (1) **define
`ECP5`**, (2) **add** the lattice files, and (3) **exclude** the Gowin vendor files (they define
the same module names / use Gowin primitives).

## 1. Define
```
+define+ECP5      # (Verilog `define ECP5) — selects clocks_ecp5, serializer_ecp5, BUFG stub, etc.
```

## 2. Add (ECP5-only source)
- `src/lattice/ecp5pll.sv`                       — BSD ECP5 PLL generator
- `src/lattice/clocks_ecp5.v`                    — 50 -> 108/108@180/54/27 (replaces CLK_108P + both dividers)
- `src/lattice/bufg_ecp5.v`                      — BUFG pass-through (ECP5 infers global routing)
- `tn_vdp_v3_v9958/src/lattice/clk_135_ecp5.v`   — CLK_135 drop-in (27 -> 135)
- `tn_vdp_v3_v9958/src/hdmi/serializer_ecp5.sv`  — GPDI output (ODDRX1F), replaces OSER10 + ELVDS_OBUF
- constraints: `icepi.lpf`   (not `tang9k.cst`)

## 3. Exclude (Gowin-only — do NOT compile for ECP5)
- `src/gowin/clk_108p.v`                     (Gowin rPLL; replaced by clocks_ecp5)
- `src/gowin_clkdiv/gowin_clkdiv.v`          (Gowin CLKDIV; replaced by clocks_ecp5)
- `src/gowin_clkdiv2/gowin_clkdiv2.vhd`      (Gowin CLKDIV; replaced by clocks_ecp5)
- `tn_vdp_v3_v9958/src/gowin/clk_135.v`      (Gowin rPLL; replaced by clk_135_ecp5)
- `tn_vdp_v3_v9958/src/hdmi/serializer.sv`   (Gowin OSER10; replaced by serializer_ecp5)
- `src/lattice/clk_108p_ecp5.v`              (early 2-output CLK_108P drop-in; superseded by clocks_ecp5 — optional)

## How the selection works (no per-instance ifdefs needed for the drop-ins)
- `CLK_135` and `BUFG` are selected purely by **which file** is in the list (same module name,
  one definition wins). Their instantiations in `v9958_top.v` are untouched.
- `clocks_ecp5` (new name) and `serializer_ecp5` (new name) are chosen by `` `ifdef ECP5`` in
  `top.v` / `v9958_top.v`; the Gowin `CLK_108P` / `serializer` sit in the `` `else``.
- `Gowin_CLKDIV` / `Gowin_CLKDIV2` instances are compiled out with `` `ifndef ECP5``; `clk_27m` /
  `clk_54m` come from `clocks_ecp5` instead.

## Still TODO before it will actually build/run
- `mspi_sclk`: ECP5 flash clock is the config MCLK -> drive via `USRMCLK` primitive, not a pin.
- Assign the companion SPI + joystick FPGA pins in `icepi.lpf` (from NanoMig `gpio[]` / J3).
- Step 4: the 16-bit SDRAM controller (see `SDRAM_PORT.md`).
- Pick a toolchain (Yosys+nextpnr-ecp5 or Diamond) and wire this file list into it.
