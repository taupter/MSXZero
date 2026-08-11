// serializer_ecp5.sv
// ECP5 replacement for MSXnano's Gowin video output (serializer.sv's OSER10 + ELVDS_OBUF).
//
// Keeps MSXnano's TMDS encoding (tmds_channel.sv -> tmds_internal[9:0] per channel).
// Swaps the two Gowin-specific pieces for the standard ECP5 method:
//   - OSER10 (10:1 serializer)  -> a 5x shift-out feeding ODDRX1F (2 DDR bits per fast clock)
//   - ELVDS_OBUF (LVDS macro)   -> pseudo-differential: drive the P pin and its inverse on the
//                                  N pin as two ordinary LVCMOS33 outputs (see icepi.lpf).
//
// Clocks are the same ones MSXnano already generates: clk_pixel (e.g. 27 MHz) and
// clk_pixel_x5 (5x = 135 MHz). No 10x/270 MHz clock needed (unlike cheyao's single-rate DVI).
//
// Drop-in for the `serializer` + `ELVDS_OBUF` block in v9958_top.v: it drives the same
// tmds_data_p/n[2:0] + tmds_clk_p/n outputs directly.

module serializer_ecp5 #(parameter NUM_CHANNELS = 3) (
    input  wire                    clk_pixel,
    input  wire                    clk_pixel_x5,
    input  wire                    reset,
    input  wire [9:0]              tmds_internal [NUM_CHANNELS-1:0], // B, G, R  (10b TMDS words)
    output wire [NUM_CHANNELS-1:0] tmds_data_p,
    output wire [NUM_CHANNELS-1:0] tmds_data_n,
    output wire                    tmds_clk_p,
    output wire                    tmds_clk_n
);
    // TMDS clock channel = the constant 10-bit pattern (same as serializer.sv)
    localparam [9:0] CLK_PATTERN = 10'b0000011111;

    // 5-phase load strobe: reload the shift regs with a fresh word once per pixel.
    reg [2:0] ctr = 0;
    reg       shift_ld = 0;
    always @(posedge clk_pixel_x5) begin
        if (reset) begin
            ctr <= 0;
            shift_ld <= 0;
        end else begin
            ctr <= (ctr == 3'd4) ? 3'd0 : ctr + 3'd1;
            shift_ld <= (ctr == 3'd4);
        end
    end

    // One shift register + DDR output pair per channel (data channels + the clock channel).
    genvar i;
    generate
        for (i = 0; i <= NUM_CHANNELS; i = i + 1) begin : gen_ch
            wire [9:0] word = (i == NUM_CHANNELS) ? CLK_PATTERN : tmds_internal[i];
            reg  [9:0] sh = 0;
            always @(posedge clk_pixel_x5)
                sh <= shift_ld ? word : {2'b00, sh[9:2]};   // shift right 2 bits/fast clock, LSB first

            wire q_p, q_n;
            // rising edge -> bit0, falling edge -> bit1
            ODDRX1F ddr_p (.Q(q_p), .SCLK(clk_pixel_x5), .RST(1'b0), .D0(sh[0]),  .D1(sh[1]));
            ODDRX1F ddr_n (.Q(q_n), .SCLK(clk_pixel_x5), .RST(1'b0), .D0(~sh[0]), .D1(~sh[1]));

            if (i < NUM_CHANNELS) begin : gen_data
                assign tmds_data_p[i] = q_p;
                assign tmds_data_n[i] = q_n;
            end else begin : gen_clk
                assign tmds_clk_p = q_p;
                assign tmds_clk_n = q_n;
            end
        end
    endgenerate
endmodule
