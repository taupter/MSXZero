// clk_108p_ecp5.v
// IcePi Zero (Lattice ECP5-45F) replacement for the Gowin CLK_108P
// (drop-in for fpga/src/gowin/clk_108p.v — same module name + ports).
//
// Generates the two clocks MSXnano's top.v needs, from the IcePi Zero's
// 50 MHz oscillator (ECP5 pin M1, "clk"):
//   clkout  = 108 MHz, 0   deg   (Gowin CLKOUT  -> clk_108m)
//   clkoutp = 108 MHz, 180 deg   (Gowin CLKOUTP -> clk_108m_n; Gowin used PSDA_SEL="1000" = 180 deg)
//
// The original Gowin PLL used a 27 MHz reference (Tang Nano osc). On the IcePi the
// reference is 50 MHz. MSXnano derives its 27 MHz clock-enable by /4 of clk_108m, so
// as long as clkout is *exactly* 108 MHz, all downstream Z80/VDP/PSG/video timing is
// preserved. 108 MHz is exactly reachable from 50 MHz (VCO 540 MHz: /5 = 108).
//
// Uses emard's BSD-licensed ecp5pll.sv generator (fpga/src/lattice/ecp5pll.sv) —
// tool-agnostic (Yosys+nextpnr-ecp5 or Lattice Diamond); it computes the EHXPLLL
// dividers at elaboration.
//
// TODO (Step 3 video): add pixel + 5x TMDS clocks for the ECP5 GPDI output. A single
//   PLL at VCO 540 MHz can also yield 135 MHz (/4, TMDS) and 27 MHz (pixel) alongside 108.
// TODO (Step 4 SDRAM): the 180 deg phase on clkoutp is a starting point — tune it when
//   bringing up the SDRAM controller on real hardware.

module CLK_108P (
    output wire clkout,   // 108 MHz  0   deg
    output wire lock,     // PLL locked
    output wire clkoutp,  // 108 MHz  180 deg
    input  wire reset,    // unused (kept for port-compatibility with the Gowin module)
    input  wire clkin     // 50 MHz  IcePi Zero oscillator (pin M1)
);
    wire [3:0] clk_o;
    assign clkout  = clk_o[0];
    assign clkoutp = clk_o[1];

    ecp5pll #(
        .in_hz   (50_000_000),
        .out0_hz (108_000_000), .out0_deg (0),
        .out1_hz (108_000_000), .out1_deg (180)
    ) pll_inst (
        .clk_i        (clkin),
        .clk_o        (clk_o),
        .reset        (1'b0),
        .standby      (1'b0),
        .phasesel     (2'b00),
        .phasedir     (1'b0),
        .phasestep    (1'b0),
        .phaseloadreg (1'b0),
        .locked       (lock)
    );
endmodule
