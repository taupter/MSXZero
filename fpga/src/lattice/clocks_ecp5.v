// clocks_ecp5.v - ECP5 clock generation for MSXnano on the IcePi Zero (50 MHz oscillator).
//
// IMPORTANT: 108 MHz is NOT exactly reachable from 50 MHz (ecppll best = 107.692). We run the
// whole system 0.28% low - within HDMI pixel-clock tolerance and imperceptible for MSX timing.
// One VCO @ 538.462 MHz (CLKI_DIV=13, CLKFB_DIV=28, feedback from CLKOP) gives all four,
// phase-locked to each other:
//   CLKOP  /5  = 107.692 MHz -> clk_108  (system / SDRAM)
//   CLKOS  /4  = 134.615 MHz -> clk_135  (HDMI TMDS bit clock = 5x pixel)
//   CLKOS2 /20 =  26.923 MHz -> clk_27   (HDMI pixel clock)
//   CLKOS3 /10 =  53.846 MHz -> clk_54
// Downstream: clk_27m/clk_54m come from here (replacing the Gowin dividers); the VDP is fed
// clk_135 directly (replacing its internal CLK_135). clk_54 = clk_108/2 harmonic; the 27/135
// pair stays 1:5 for TMDS.
//
// Base EHXPLLL attributes from `ecppll --clkin 50 --clkout0 108`; CLKOS/2/3 added by hand.
// CPHASE ~ DIV/2 (edge alignment) - TUNE on hardware/sim (esp. the 27<->135 TMDS pair).
// clk_108_n (SDRAM 180deg strobe) = ~clk_108 placeholder; real phase set with the SDRAM controller.

module clocks_ecp5 (
    input  wire clkin_50,
    output wire clk_108,
    output wire clk_108_n,
    output wire clk_135,
    output wire clk_54,
    output wire clk_27,
    output wire locked
);
    assign clk_108_n = ~clk_108;

    (* FREQUENCY_PIN_CLKI="50" *)
    (* FREQUENCY_PIN_CLKOP="107.692" *)
    (* FREQUENCY_PIN_CLKOS="134.615" *)
    (* FREQUENCY_PIN_CLKOS2="26.923" *)
    (* FREQUENCY_PIN_CLKOS3="53.846" *)
    (* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
    EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(13),
        .CLKFB_DIV(28),
        .FEEDBK_PATH("CLKOP"),
        .CLKOP_ENABLE("ENABLED"),  .CLKOP_DIV(5),   .CLKOP_CPHASE(2),  .CLKOP_FPHASE(0),
        .CLKOS_ENABLE("ENABLED"),  .CLKOS_DIV(4),   .CLKOS_CPHASE(2),  .CLKOS_FPHASE(0),
        .CLKOS2_ENABLE("ENABLED"), .CLKOS2_DIV(20), .CLKOS2_CPHASE(10),.CLKOS2_FPHASE(0),
        .CLKOS3_ENABLE("ENABLED"), .CLKOS3_DIV(10), .CLKOS3_CPHASE(5), .CLKOS3_FPHASE(0)
    ) pll_i (
        .RST(1'b0), .STDBY(1'b0),
        .CLKI(clkin_50),
        .CLKOP(clk_108),
        .CLKOS(clk_135),
        .CLKOS2(clk_27),
        .CLKOS3(clk_54),
        .CLKFB(clk_108),
        .CLKINTFB(),
        .PHASESEL0(1'b0), .PHASESEL1(1'b0), .PHASEDIR(1'b1), .PHASESTEP(1'b1), .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0), .ENCLKOP(1'b0),
        .LOCK(locked)
    );
endmodule
