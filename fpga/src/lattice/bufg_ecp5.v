// bufg_ecp5.v
// ECP5 stand-in for the Gowin global-clock buffer primitive `BUFG`.
// ECP5 (nextpnr / Diamond) infers global clock routing automatically, so BUFG is just a
// wire pass-through here. Provides the `BUFG` module so v9958_top.v's BUFG instances compile
// unchanged on ECP5. Only compiled for the ECP5 build (guarded) to avoid clashing with the
// real Gowin BUFG primitive on the Gowin build.
`ifdef ECP5
module BUFG (
    output O,
    input  I
);
    assign O = I;
endmodule
`endif
