// hdmi_test_top.sv — standalone HDMI test-pattern harness for IcePi Zero bring-up (stage 3).
//
// Purpose: validate the *video output path* in isolation — the PLL (clocks_ecp5), the hdl-util
// HDMI encoder, and serializer_ecp5's ODDRX1F GPDI — WITHOUT the whole MSX (no VDP/Z80/SDRAM).
// If a monitor syncs and shows 8 colour bars, then clocking + TMDS encoding + GPDI are all good,
// and any later "no picture" during full-core bring-up is upstream (the VDP), not the output stage.
//
// Reuses the exact same modules the real design uses (clocks_ecp5 + hdmi + serializer_ecp5), at the
// same VIC=2 / 27 MHz pixel / 135 MHz x5 clocking, so it exercises the real hardware path.
//
// Build: bringup/build_hdmi_test.sh   ->  bringup/hdmi_test.bit

module hdmi_test_top (
    input  wire       ex_clk_27m,   // 50 MHz oscillator (pin M1) — name kept from the main design
    output wire [2:0] data_p,       // GPDI data (B,G,R)
    output wire [2:0] data_n,
    output wire       clk_p,        // GPDI clock
    output wire       clk_n,
    output wire [4:0] led           // led[0]=PLL locked (active-low LEDs on the carrier)
);
    // ---- clocks: one EHXPLLL, exactly as the MSX design ----
    wire clk_108, clk_108_n, clk_135, clk_54, clk_27, locked;
    clocks_ecp5 clocks (
        .clkin_50 (ex_clk_27m),
        .clk_108  (clk_108), .clk_108_n(clk_108_n), .clk_135(clk_135),
        .clk_54   (clk_54),  .clk_27   (clk_27),    .locked (locked)
    );

    wire reset = ~locked;   // hdmi/serializer reset is active-high (matches v9958_top's hdmi_reset)

    // ---- test pattern: 8 vertical colour bars keyed off the encoder's own pixel X ----
    localparam int NUM_CHANNELS = 3;
    wire [9:0] cx, cy;                       // VIC=2 (480p) -> 10-bit counters
    wire [9:0] frame_width, frame_height, screen_width, screen_height;
    wire [9:0] tmds_internal [NUM_CHANNELS-1:0];

    // rgb is {red[23:16], green[15:8], blue[7:0]} (hdl-util/hdmi convention).
    reg [23:0] pattern;
    always @(*) begin
        case (cx[9:7])                       // ~8 bars across the active line
            3'd0: pattern = 24'hFFFFFF;      // white
            3'd1: pattern = 24'hFFFF00;      // yellow
            3'd2: pattern = 24'h00FFFF;      // cyan
            3'd3: pattern = 24'h00FF00;      // green
            3'd4: pattern = 24'hFF00FF;      // magenta
            3'd5: pattern = 24'hFF0000;      // red
            3'd6: pattern = 24'h0000FF;      // blue
            default: pattern = 24'h000000;   // black
        endcase
    end

    // ---- HDMI encoder (video only: DVI_OUTPUT drops all audio/data-island infra) ----
    hdmi #(
        .VIDEO_ID_CODE       (2),            // 480p60 — widely supported, 27 MHz pixel
        .DVI_OUTPUT          (1'b1),         // no audio -> no clk_audio / packet machinery needed
        .VIDEO_REFRESH_RATE  (6000),         // centi-Hz (yosys has no real); unused under DVI_OUTPUT
        .AUDIO_RATE          (44100),
        .AUDIO_BIT_WIDTH     (16)
    ) hdmi_inst (
        .clk_pixel_x5   (clk_135),
        .clk_pixel      (clk_27),
        .clk_audio      (1'b0),
        .reset          (reset),
        .rgb            (pattern),
        .audio_sample_word ('{16'd0, 16'd0}),
        .aspect_16_9    (1'b0),
        .cx             (cx),
        .cy             (cy),
        .frame_width    (frame_width),
        .frame_height   (frame_height),
        .screen_width   (screen_width),
        .screen_height  (screen_height),
        .tmds_internal  (tmds_internal)
    );

    // ---- ECP5 GPDI output (ODDRX1F pseudo-differential) ----
    serializer_ecp5 #(.NUM_CHANNELS(NUM_CHANNELS)) serializer (
        .clk_pixel    (clk_27),
        .clk_pixel_x5 (clk_135),
        .reset        (reset),
        .tmds_internal(tmds_internal),
        .tmds_data_p  (data_p),
        .tmds_data_n  (data_n),
        .tmds_clk_p   (clk_p),
        .tmds_clk_n   (clk_n)
    );

    assign led = ~{4'b0000, locked};         // led[0] lit when the PLL is locked (active-low)
endmodule
