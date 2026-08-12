// tb_sdram_test.v — validate the synthesizable SDRAM memtest FSM (sdram_test_top) against the
// behavioral sdram_model, before trusting it on hardware. Watches the PASS/FAIL LEDs.
//   iverilog -g2012 -DECP5 -DSIM_FAST_INIT -o bringup/tb_sdram_test \
//     bringup/tb_sdram_test.v bringup/sdram_test_top.v src/memory.v \
//     src/lattice/clocks_ecp5.v sim/ecp5_prims_sim.v sim/sdram_model.v
//   vvp bringup/tb_sdram_test
`timescale 1ns/1ps
module tb_sdram_test;
    reg ex_clk_27m = 0;
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [15:0] IO_sdram_dq; wire [12:0] O_sdram_addr; wire [1:0] O_sdram_ba, O_sdram_dqm;
    wire [4:0] led;

    always #10 ex_clk_27m = ~ex_clk_27m;   // 50 MHz

    sdram_test_top dut (
        .ex_clk_27m(ex_clk_27m),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n), .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm), .led(led)
    );
    sdram_model sdram (
        .clk(O_sdram_clk), .cke(O_sdram_cke), .cs_n(O_sdram_cs_n), .ras_n(O_sdram_ras_n),
        .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n), .ba(O_sdram_ba), .addr(O_sdram_addr),
        .dqm(O_sdram_dqm), .dq(IO_sdram_dq)
    );

    // led is active-low: [0]=running [1]=PASS [2]=FAIL [3]=done [4]=heartbeat
    wire running = ~led[0], pass = ~led[1], fail = ~led[2], done = ~led[3];
    initial begin
        // run until done or timeout
        wait (done);
        #100;
        if (pass && !fail) $display("SDRAM HARNESS: PASS");
        else               $display("SDRAM HARNESS: FAIL (pass=%b fail=%b)", pass, fail);
        $finish;
    end
    initial begin #4000000 $display("SDRAM HARNESS: TIMEOUT (done never asserted)"); $finish; end
endmodule
