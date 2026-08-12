// Bring-up sim for memory_ctrl (src/memory.v) + sdram_model.
// Verifies the ECP5 16-bit read path + geometry: CPU write -> read-back integrity.
// Run: iverilog -g2012 -DECP5 -DSIM_FAST_INIT -o tb sim/tb_memory.v sim/sdram_model.v src/memory.v
//      vvp tb
`timescale 1ns/1ps
module tb_memory;
    reg clk_108m = 0, clk_cpu = 0;
    reg bus_reset_n = 0;
    reg video_dhclk = 0, video_dlclk = 0;

    reg  [7:0]  ram_din = 0;
    reg         ram_req = 0, ram_write = 0;
    reg  [22:0] ram_addr = 0;
    reg  [7:0]  vram_din = 0;
    reg         vram_write = 0;
    reg  [16:0] vram_addr = 0;
    wire [7:0]  ram_dout;
    wire [15:0] vram_dout;
    wire        ram_busy;

    // SDRAM wires
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [12:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba, O_sdram_dqm;
    wire [15:0] IO_sdram_dq;

    // clocks: 108 MHz and a 54 MHz "cpu" clock (memory.v's clk_27m port)
    always #4.63 clk_108m = ~clk_108m;   // ~108 MHz
    always #9.26 clk_cpu  = ~clk_cpu;    // ~54 MHz

    memory_ctrl dut (
        .clk_27m(clk_cpu), .clk_108m(clk_108m), .bus_reset_n(bus_reset_n),
        .video_dhclk(video_dhclk), .video_dlclk(video_dlclk),
        .ram_din(ram_din), .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr),
        .vram_din(vram_din), .vram_write(vram_write), .vram_addr(vram_addr),
        .bus_rfsh_n(1'b1),
        .ram_dout(ram_dout), .vram_dout(vram_dout), .ram_busy(ram_busy),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n), .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba), .O_sdram_dqm(O_sdram_dqm)
    );

    sdram_model sdram (
        .clk(O_sdram_clk), .cke(O_sdram_cke), .cs_n(O_sdram_cs_n),
        .ras_n(O_sdram_ras_n), .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n),
        .ba(O_sdram_ba), .addr(O_sdram_addr), .dqm(O_sdram_dqm), .dq(IO_sdram_dq)
    );

    // Replicate the VDP dot-state machine (vdp_ssg.vhd) that generates dh/dl clk.
    // Sequence (DH,DL): entering 01=(0,1) 11=(1,0) 10=(0,0) 00=(1,1). memory.v's ff_sdr_seq
    // locks to video_dhclk (counts 000->111 while DH=1). DH rises with DL=0 entering 11 -> CPU
    // access; DH rises with DL=1 entering 00 -> VDP access. Advance one dot-state every 8
    // clk_108m cycles so ff_sdr_seq (8 states) fits in each DH-high window.
    reg [1:0] dotstate = 2'b00;
    integer dcnt = 0;
    always @(posedge clk_108m) begin
        dcnt <= dcnt + 1;
        if (dcnt >= 7) begin
            dcnt <= 0;
            case (dotstate)
                2'b00: begin dotstate <= 2'b01; video_dhclk <= 0; video_dlclk <= 1; end
                2'b01: begin dotstate <= 2'b11; video_dhclk <= 1; video_dlclk <= 0; end
                2'b11: begin dotstate <= 2'b10; video_dhclk <= 0; video_dlclk <= 0; end
                2'b10: begin dotstate <= 2'b00; video_dhclk <= 1; video_dlclk <= 1; end
            endcase
        end
    end

    // one CPU transaction (write or read); returns when ram_busy drops
    task cpu_access(input write, input [22:0] a, input [7:0] d);
    begin
        @(posedge clk_cpu);
        // wait for a request window (both dot clocks high) and controller idle
        wait (video_dhclk && video_dlclk && !ram_busy);
        ram_addr <= a; ram_din <= d; ram_write <= write; ram_req <= 1;
        wait (ram_busy);          // controller accepted
        wait (!ram_busy);         // completed
        @(posedge clk_cpu);
        ram_req <= 0;
        wait (video_dhclk==0);    // let it return to idle
        @(posedge clk_cpu);
    end
    endtask

    integer errors = 0;
    task check(input [22:0] a, input [7:0] exp);
    begin
        cpu_access(0, a, 8'hxx);
        if (ram_dout === exp) $display("  READ  addr=%h -> %h  OK", a, ram_dout);
        else begin $display("  READ  addr=%h -> %h  EXPECTED %h  ***FAIL***", a, ram_dout, exp); errors=errors+1; end
    end
    endtask

    // VDP/VRAM port: streaming (no handshake). Hold the signals stable across VDP phases
    // (video_dlclk==1) so the FSM performs the access. Writes are 8-bit (byte lane by
    // vram_addr[0]); reads return the full 16-bit word.
    task vram_wr(input [16:0] a, input [7:0] d);
    begin
        @(posedge clk_cpu);
        vram_addr <= a; vram_din <= d; vram_write <= 1;
        repeat (80) @(posedge clk_108m);   // ~2-3 VDP phases
        vram_write <= 0;
        repeat (16) @(posedge clk_108m);
    end
    endtask
    task vram_ck(input [16:0] a, input [15:0] exp);
    begin
        vram_addr <= a; vram_write <= 0;
        repeat (80) @(posedge clk_108m);   // wait for a VDP read + vram_dout latch
        if (vram_dout === exp) $display("  VRAM  addr=%h -> %h  OK", a, vram_dout);
        else begin $display("  VRAM  addr=%h -> %h  EXPECTED %h  ***FAIL***", a, vram_dout, exp); errors=errors+1; end
    end
    endtask

    initial begin
        $dumpfile("sim/tb_memory.vcd"); $dumpvars(0, tb_memory);
        bus_reset_n = 0;
        repeat (40) @(posedge clk_108m);
        bus_reset_n = 1;
        // wait for SDRAM init (RstSeq -> 31). Fast-init: ~256 clk per step * 32 steps.
        $display("waiting for SDRAM init...");
        repeat (12000) @(posedge clk_108m);
        $display("init done, starting memtest");

        // byte-lane test: adjacent bytes must not clobber each other
        cpu_access(1, 23'h000100, 8'hA5);
        cpu_access(1, 23'h000101, 8'h5A);   // other lane, same word
        check(23'h000100, 8'hA5);
        check(23'h000101, 8'h5A);

        // spread across rows / high address bits — catches geometry aliasing
        cpu_access(1, 23'h001000, 8'h3C);
        cpu_access(1, 23'h002001, 8'h11);
        cpu_access(1, 23'h040000, 8'h22);   // bit 18
        cpu_access(1, 23'h100000, 8'h33);   // bit 20
        cpu_access(1, 23'h1FFFFF, 8'h44);   // near top of 2MB
        check(23'h001000, 8'h3C);
        check(23'h002001, 8'h11);
        check(23'h040000, 8'h22);
        check(23'h100000, 8'h33);
        check(23'h1FFFFF, 8'h44);
        // re-read the first ones: confirm the later writes didn't alias over them
        check(23'h000100, 8'hA5);
        check(23'h000101, 8'h5A);

        // ---- VDP / VRAM port memtest (bank 3) ----
        // write both bytes of a word (even lane + odd lane), then read the 16-bit word
        vram_wr(17'h01000, 8'hAB);   // even addr -> low byte
        vram_wr(17'h01001, 8'hCD);   // odd  addr -> high byte
        vram_ck(17'h01000, 16'hCDAB);
        vram_wr(17'h00100, 8'h12);
        vram_wr(17'h00101, 8'h34);
        vram_ck(17'h00100, 16'h3412);
        vram_wr(17'h1FFFE, 8'h77);   // near top of 128KB VRAM
        vram_wr(17'h1FFFF, 8'h88);
        vram_ck(17'h1FFFE, 16'h8877);
        // confirm CPU RAM (bank 0) wasn't disturbed by VRAM (bank 3) writes
        check(23'h000100, 8'hA5);

        if (errors==0) $display("MEMTEST PASS (CPU + VRAM)");
        else           $display("MEMTEST FAIL (%0d errors)", errors);
        $finish;
    end

    // safety timeout
    initial begin #2000000 $display("TIMEOUT"); $finish; end

    // debug: count active SDRAM commands + report final init state
    integer cmdcnt = 0;
    always @(posedge clk_108m)
        if (dut.SdrCmd !== 4'b1111 && dut.SdrCmd !== 4'b0111) cmdcnt = cmdcnt + 1;
    reg printed_init = 0;
    always @(posedge clk_108m)
        if (dut.RstSeq == 5'd31 && !printed_init) begin
            printed_init <= 1; $display("  [dbg] init complete (RstSeq=31) at t=%0t", $time);
        end
    final $display("  [dbg] FINAL RstSeq=%0d active-cmds=%0d", dut.RstSeq, cmdcnt);
endmodule
