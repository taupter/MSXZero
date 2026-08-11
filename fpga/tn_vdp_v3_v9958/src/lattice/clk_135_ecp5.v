// clk_135_ecp5.v
// ECP5 replacement for the VDP's Gowin CLK_135 (tn_vdp_v3_v9958/src/gowin/clk_135.v).
// Drop-in: same module name + ports (clkout, lock, reset, clkin).
//
// The VDP is clocked at clk_27m (27 MHz) and this PLL makes the 135 MHz (5x) TMDS bit clock
// that serializer_ecp5.sv needs. 135 MHz = 27 x 5, exact.
//
// Uses emard's BSD ecp5pll.sv (fpga/src/lattice/ecp5pll.sv).
//
// NOTE: this chains a PLL off the already-divided 27 MHz. It works, but for lowest jitter the
// cleaner long-term option is one top-level ecp5pll from the 50 MHz osc producing 108/54/27/135
// directly (VCO 540 MHz: /5=108, /10=54, /20=27, /4=135) and feeding 135 into the VDP, replacing
// CLK_108P + both Gowin_CLKDIV dividers + this. See PORT_PLAN.md Step 3.

module CLK_135 (
    output wire clkout,   // 135 MHz
    output wire lock,     // PLL locked
    input  wire reset,    // unused (kept for port-compatibility with the Gowin module)
    input  wire clkin     // 27 MHz (clk_27m)
);
    wire [3:0] clk_o;
    assign clkout = clk_o[0];

    ecp5pll #(
        .in_hz   (27_000_000),
        .out0_hz (135_000_000)
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
