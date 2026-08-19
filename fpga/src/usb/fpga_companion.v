module fpga_companion (
    input        clk,
    input        reset,

    // interface to external FPGA companion
    // Split bidirectional m0s pins; the buffer itself is instantiated in top.v.
    // abc9 cannot represent inout ports — see fpga/docs/abc9_issue.md.
    input  [4:0] m0s_i,
    output [4:0] m0s_o,
    output [4:0] m0s_oe,
    // and internal
    input	spi_sclk,
    input	spi_csn,
    output	spi_dir,
    input	spi_dat,
    output	spi_irqn,

    //USB keyboard data
    output [127:0] keyboard,
    output [7:0] joystick0,
    output [7:0] joystick0_console,
    output [7:0] joystick1,
    output [23:0] ws2812_color
);

wire mcu_hid_strobe;
wire mcu_sys_strobe;
wire mcu_osd_strobe;
wire mcu_sdc_strobe;

wire mcu_start;
wire spi_intn;
wire [7:0] mcu_data_out;
wire [7:0] sys_data_out;
wire [7:0] hid_data_out;

//assign m0s_i[4] = spi_intn;

// -------------------------- M0S MCU interface -----------------------
// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
// onboard connection to on-board BL616

assign spi_dir = spi_io_dout;
// bit 4 = spi_intn (driven), bits 3:1 = inputs from the dock, bit 0 = spi_io_dout (driven)
assign m0s_o  = { spi_intn, 3'b000, spi_io_dout };
assign m0s_oe = 5'b10001;
assign spi_irqn = spi_intn;

// by default the internal SPI is being used. Once there is
// a select from the external spi, then the connection is
// being switched
reg spi_ext;
always @(posedge clk) begin
    if(reset)
        spi_ext = 1'b0;
    else begin
        // spi_ext is activated once the m0s pins 2 (ss or csn) is
        // driven low by the m0s dock. This means that a m0s dock
        // is connected and the FPGA switches its inputs to the
        // m0s. Until then the inputs of the internal BL616 are
        // being used.
        if(m0s_i[2] == 1'b0)
            spi_ext = 1'b1;
    end
end

// switch between internal SPI connected to the on-board bl616
// or to the external one possibly connected to a M0S Dock
wire spi_io_din = spi_ext?m0s_i[1]:spi_dat;
wire spi_io_ss = spi_ext?m0s_i[2]:spi_csn;
wire spi_io_clk = spi_ext?m0s_i[3]:spi_sclk;

mcu_spi mcu (
        .clk(clk),
        .reset(reset),

        .spi_io_ss(spi_io_ss),
        .spi_io_clk(spi_io_clk),
        .spi_io_din(spi_io_din),
        .spi_io_dout(spi_io_dout),

        .mcu_sys_strobe(mcu_sys_strobe),
        .mcu_hid_strobe(mcu_hid_strobe),
        .mcu_osd_strobe(mcu_osd_strobe),
        .mcu_sdc_strobe(mcu_sdc_strobe),
        .mcu_start(mcu_start),
        .mcu_dout(mcu_data_out),
        .mcu_sys_din(sys_data_out),
        .mcu_hid_din(hid_data_out),
        .mcu_osd_din(8'b00000000),
        .mcu_sdc_din(8'b00000000)
        );

wire [7:0] int_ack;
wire hid_int;
wire hid_iack = int_ack[1];

hid hid_inst (
        .clk(clk),
        .reset(reset),

         // interface to receive user data from MCU (mouse, kbd, ...)
        .data_in_strobe(mcu_hid_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data_out),
        .data_out(hid_data_out),

        // input local db9 port events to be sent to MCU. Changes also trigger
        // an interrupt, so the MCU doesn't have to poll for joystick events
        //.db9_port( db9_joy ),
        .irq( hid_int ),
        .iack( hid_iack ),

        //.mouse(hid_mouse),
        .keyboard(keyboard),
        .joystick0(joystick0),
        .joystick0_console(joystick0_console),
        .joystick1(joystick1)
         );   


sysctrl sysctrl (
        .clk(clk),
        .reset(reset),

         // interface to send and receive generic system control
        .data_in_strobe(mcu_sys_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data_out),
        .data_out(sys_data_out),

        
        .int_out_n(spi_intn),
        .int_in( { 4'b0000, 1'b0, 1'b0, hid_int, 1'b0 }),
        .int_ack( int_ack ),

        .buttons( {1'b0, 1'b0} ),
        .leds(system_leds),
        .color(ws2812_color)
         );   

endmodule