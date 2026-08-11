// clocks_ecp5.v
// Single ECP5 PLL that replaces MSXnano's Gowin clock trio in top.v:
//   CLK_108P (50->108 + 108@180) + Gowin_CLKDIV (108->27) + Gowin_CLKDIV2 (108->54).
//
// From the IcePi Zero's 50 MHz oscillator, one VCO @ 540 MHz gives all four exactly:
//   108 MHz = 540/5   (main / SDRAM clock, clk_108m)
//   108 MHz @ 180deg  (SDRAM strobe, clk_108m_n)
//    54 MHz = 540/10  (clk_54m)
//    27 MHz = 540/20  (clk_27m -> VDP; its clk_135_ecp5 makes 135 from this)
//
// Fewer primitives and less jitter than chaining CLKDIVs off a PLL output.
// Uses emard's BSD ecp5pll.sv (fpga/src/lattice/ecp5pll.sv).

module clocks_ecp5 (
    input  wire clkin_50,   // 50 MHz IcePi Zero oscillator (pin M1)
    output wire clk_108,    // 108 MHz  0deg
    output wire clk_108_n,  // 108 MHz  180deg  (SDRAM)
    output wire clk_54,     //  54 MHz
    output wire clk_27,     //  27 MHz
    output wire locked
);
    wire [3:0] clk_o;
    assign clk_108   = clk_o[0];
    assign clk_108_n = clk_o[1];
    assign clk_54    = clk_o[2];
    assign clk_27    = clk_o[3];

    ecp5pll #(
        .in_hz   (50_000_000),
        .out0_hz (108_000_000), .out0_deg (0),
        .out1_hz (108_000_000), .out1_deg (180),
        .out2_hz ( 54_000_000), .out2_deg (0),
        .out3_hz ( 27_000_000), .out3_deg (0)
    ) pll_inst (
        .clk_i        (clkin_50),
        .clk_o        (clk_o),
        .reset        (1'b0),
        .standby      (1'b0),
        .phasesel     (2'b00),
        .phasedir     (1'b0),
        .phasestep    (1'b0),
        .phaseloadreg (1'b0),
        .locked       (locked)
    );
endmodule
