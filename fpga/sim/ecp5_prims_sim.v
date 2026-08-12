// Behavioral sim models for the ECP5 hard primitives MSXZero instantiates, so the
// flattened design can run in iverilog. NOT timing-accurate — just functional.
`timescale 1ns/1ps

// EHXPLLL: generate the output clocks phase-coherently from one VCO.
// VCO = CLKI/CLKI_DIV * CLKFB_DIV * CLKOP_DIV ; CLKOx = VCO / CLKOx_DIV.
module EHXPLLL #(
    parameter CLKI_DIV = 1, parameter CLKFB_DIV = 1,
    parameter CLKOP_DIV = 1, parameter CLKOS_DIV = 1,
    parameter CLKOS2_DIV = 1, parameter CLKOS3_DIV = 1,
    parameter CLKOP_ENABLE = "ENABLED", parameter CLKOS_ENABLE = "DISABLED",
    parameter CLKOS2_ENABLE = "DISABLED", parameter CLKOS3_ENABLE = "DISABLED",
    parameter CLKOP_CPHASE = 0, parameter CLKOP_FPHASE = 0,
    parameter CLKOS_CPHASE = 0, parameter CLKOS_FPHASE = 0,
    parameter CLKOS2_CPHASE = 0, parameter CLKOS2_FPHASE = 0,
    parameter CLKOS3_CPHASE = 0, parameter CLKOS3_FPHASE = 0,
    parameter FEEDBK_PATH = "CLKOP", parameter DPHASE_SOURCE = "DISABLED",
    parameter INTFB_WAKE = "DISABLED", parameter STDBY_ENABLE = "DISABLED",
    parameter PLLRST_ENA = "DISABLED",
    parameter OUTDIVIDER_MUXA = "DIVA", parameter OUTDIVIDER_MUXB = "DIVB",
    parameter OUTDIVIDER_MUXC = "DIVC", parameter OUTDIVIDER_MUXD = "DIVD"
) (
    input  CLKI, input CLKFB, input RST, input STDBY, input PHASESEL0, input PHASESEL1,
    input  PHASEDIR, input PHASESTEP, input PHASELOADREG, input PLLWAKESYNC, input ENCLKOP,
    input  ENCLKOS, input ENCLKOS2, input ENCLKOS3,
    output reg CLKOP, output reg CLKOS, output reg CLKOS2, output reg CLKOS3,
    output reg LOCK, output CLKINTFB
);
    // measure CLKI period, derive VCO, generate divided outputs
    real ti0 = 0, clki_per = 20.0, vco_per = 2.0;
    real op_h, os_h, os2_h, os3_h;
    integer opc = 0, osc = 0, os2c = 0, os3c = 0;

    initial begin CLKOP=0; CLKOS=0; CLKOS2=0; CLKOS3=0; LOCK=0; end
    assign CLKINTFB = CLKOP;

    // learn the input period from the first two rising edges
    always @(posedge CLKI) begin
        if (ti0 != 0.0 && clki_per == 20.0) clki_per = ($realtime - ti0);
        ti0 = $realtime;
    end

    initial begin
        #200;                                   // let CLKI establish
        vco_per = clki_per * CLKI_DIV / (CLKFB_DIV * CLKOP_DIV);   // VCO period (ns)
        op_h  = (vco_per * CLKOP_DIV ) / 2.0;
        os_h  = (vco_per * CLKOS_DIV ) / 2.0;
        os2_h = (vco_per * CLKOS2_DIV) / 2.0;
        os3_h = (vco_per * CLKOS3_DIV) / 2.0;
        #100 LOCK = 1'b1;
        fork
            forever #(op_h)  CLKOP  = ~CLKOP;
            forever #(os_h)  CLKOS  = ~CLKOS;
            forever #(os2_h) CLKOS2 = ~CLKOS2;
            forever #(os3_h) CLKOS3 = ~CLKOS3;
        join
    end
endmodule

// ODDRX1F: DDR output register. We don't check the serialized HDMI, so a functional
// DDR mux is plenty (Q follows D0 on the SCLK high phase, D1 on the low phase).
module ODDRX1F (input SCLK, input RST, input D0, input D1, output reg Q);
    initial Q = 0;
    always @(posedge SCLK) Q <= D0;
    always @(negedge SCLK) Q <= D1;
endmodule

// USRMCLK: user access to the config clock pin — stub (flash clock).
module USRMCLK (input USRMCLKI, input USRMCLKTS, output USRMCLKO);
    assign USRMCLKO = 1'b0;
endmodule
