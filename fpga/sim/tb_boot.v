// Full-design boot sim: bring the whole MSX top alive (clocks, reset, SDRAM), observe boot.
// Build sim_msx.v with -DBRINGUP_LEDS so led[] = PLL-lock / heartbeat / SDRAM / reset / flash-idle.
//   ./sim/gen_full_sim.sh   (after EXTRA_DEFINES=-DBRINGUP_LEDS ./build_ecp5.sh)
//   iverilog -g2012 -o sim/simboot sim/tb_boot.v sim/sim_msx.v sim/ecp5_prims_sim.v sim/sdram_model.v
//   vvp sim/simboot
`timescale 1ns/1ps
module tb_boot;
    reg ex_clk_27m = 0;               // the 50 MHz board oscillator (port name is historical)
    reg s1 = 1'b0, s2 = 1'b0;
    reg mspi_miso_r = 1'b0;           // SPI flash MISO — dummy (0) for now; real C-BIOS = flash model
    wire mspi_miso; assign mspi_miso = mspi_miso_r;
    reg [5:0] joya = 6'h3f, joyb = 6'h3f;
    reg uart_rx = 1'b1;

    wire [15:0] IO_sdram_dq;
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [12:0] O_sdram_addr; wire [1:0] O_sdram_ba, O_sdram_dqm;
    wire [5:0] led; wire ws2812_led;
    wire [2:0] data_p, data_n; wire clk_p, clk_n;
    wire mspi_cs, mspi_mosi;   // ECP5: mspi_sclk is via USRMCLK, not a port
    wire sd_sclk, sd_cmd, uart_tx, usb_uart_tx;
    wire [4:0] m0s;
    wire spi_sclk, spi_csn, spi_dir, spi_irqn;
    tri1 spi_dat; tri1 sd_dat0, sd_dat1, sd_dat2, sd_dat3;

    always #10 ex_clk_27m = ~ex_clk_27m;   // 50 MHz

    top dut (
        .ex_clk_27m(ex_clk_27m), .s1(s1), .s2(s2),
        .m0s(m0s), .spi_sclk(spi_sclk), .spi_csn(spi_csn), .spi_dir(spi_dir),
        .spi_dat(spi_dat), .spi_irqn(spi_irqn),
        .led(led), .ws2812_led(ws2812_led),
        .data_p(data_p), .data_n(data_n), .clk_p(clk_p), .clk_n(clk_n),
        .mspi_cs(mspi_cs), .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi),
        .sd_sclk(sd_sclk), .sd_cmd(sd_cmd),
        .sd_dat0(sd_dat0), .sd_dat1(sd_dat1), .sd_dat2(sd_dat2), .sd_dat3(sd_dat3),
        .uart_tx(uart_tx), .uart_rx(uart_rx), .usb_uart_tx(usb_uart_tx),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n), .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm), .joya(joya), .joyb(joyb)
    );

    sdram_model sdram (
        .clk(O_sdram_clk), .cke(O_sdram_cke), .cs_n(O_sdram_cs_n),
        .ras_n(O_sdram_ras_n), .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n),
        .ba(O_sdram_ba), .addr(O_sdram_addr), .dqm(O_sdram_dqm), .dq(IO_sdram_dq)
    );

    // reset pulse on s1, then release
    initial begin s1 = 1'b1; #2000 s1 = 1'b0; end

    // liveness probes: count SDRAM clock edges, flash SPI edges, and sample the status LEDs
    integer sdr_edges = 0, flash_edges = 0;
    always @(posedge O_sdram_clk) sdr_edges = sdr_edges + 1;
    always @(negedge mspi_cs)    flash_edges = flash_edges + 1;  // flash selects (clk is now via USRMCLK)

    initial begin
        $display("t=0 starting full-design boot sim");
        #50000  $display("  50us:  led=%b sdram_clk_edges=%0d flash_spi_edges=%0d", led, sdr_edges, flash_edges);
        #150000 $display("  200us: led=%b sdram_clk_edges=%0d flash_spi_edges=%0d", led, sdr_edges, flash_edges);
        #300000 $display("  500us: led=%b sdram_clk_edges=%0d flash_spi_edges=%0d", led, sdr_edges, flash_edges);
        $display("DONE (sim executed). led[0]=PLLlock led[1]=heartbeat led[2]=sdram led[4]=flash-idle (active-low)");
        $finish;
    end
    initial begin #4000000 $display("TIMEOUT"); $finish; end
endmodule
