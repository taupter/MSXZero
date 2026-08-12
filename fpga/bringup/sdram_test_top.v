// sdram_test_top.v — standalone SDRAM memtest harness for IcePi Zero bring-up (stage 4).
//
// Purpose: exercise the REAL memory_ctrl (src/memory.v) against the physical SDRAM in isolation —
// no VDP/Z80. It replicates the VDP dot-clock cadence memory.v locks to, runs a write pass then a
// read/compare pass over the same address set the sim memtest proved (byte lanes, rows, high bits,
// banks 0/1/2 = full 8 MB), and reports PASS/FAIL on the LEDs. This is the "never works first try"
// stage: if the LEDs say PASS on hardware, the SDRAM data path + capture phase are good.
//
// Clocks match the real design: memory_ctrl.clk_27m <- clk_54, clk_108m <- clk_108.
// Build: bringup/build_sdram_test.sh -> bringup/sdram_test.bit
//
// LEDs (active-low on the carrier): led[0]=running  led[1]=PASS  led[2]=FAIL  led[3]=done  led[4]=heartbeat

module sdram_test_top (
    input  wire        ex_clk_27m,      // 50 MHz oscillator (M1)
    // SDRAM (16-bit, IcePi)
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [15:0] IO_sdram_dq,
    output wire [12:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [1:0]  O_sdram_dqm,
    output wire [4:0]  led
);
    // ---- clocks ----
    wire clk_108, clk_108_n, clk_135, clk_54, clk_27, locked;
    clocks_ecp5 clocks (
        .clkin_50(ex_clk_27m),
        .clk_108(clk_108), .clk_108_n(clk_108_n), .clk_135(clk_135),
        .clk_54(clk_54), .clk_27(clk_27), .locked(locked)
    );
    // Power-on reset: hold reset LOW for 255 clk_54 cycles AFTER lock, so memory.v's synchronous
    // reset (always @(posedge clk_27m) if(!bus_reset_n)) actually runs on real clock edges before
    // release. (Tying reset straight to `locked` releases it the same edge the clock starts, so the
    // reset branch never fires and ram_busy stays X — real bug, not just a sim artifact.)
    reg [7:0] rstcnt = 8'd0;
    reg       bus_reset_n = 1'b0;
    always @(posedge clk_54) begin
        if (!locked)               begin rstcnt <= 8'd0;        bus_reset_n <= 1'b0; end
        else if (rstcnt != 8'hFF)  begin rstcnt <= rstcnt + 1'b1; bus_reset_n <= 1'b0; end
        else                        bus_reset_n <= 1'b1;
    end

    // ---- VDP dot-state cadence (from vdp_ssg.vhd, as tb_memory.v replicates) ----
    // Advance one dot-state every 8 clk_108 cycles; memory.v's ff_sdr_seq (8 states) fits each
    // DH-high window. DH high with DL high (state 00->) = CPU access phase.
    reg [1:0] dotstate = 2'b00;
    reg [2:0] dcnt = 3'd0;
    reg video_dhclk = 1'b0, video_dlclk = 1'b0;
    always @(posedge clk_108) begin
        dcnt <= dcnt + 3'd1;
        if (dcnt == 3'd7) begin
            dcnt <= 3'd0;
            case (dotstate)
                2'b00: begin dotstate <= 2'b01; video_dhclk <= 1'b0; video_dlclk <= 1'b1; end
                2'b01: begin dotstate <= 2'b11; video_dhclk <= 1'b1; video_dlclk <= 1'b0; end
                2'b11: begin dotstate <= 2'b10; video_dhclk <= 1'b0; video_dlclk <= 1'b0; end
                2'b10: begin dotstate <= 2'b00; video_dhclk <= 1'b1; video_dlclk <= 1'b1; end
            endcase
        end
    end

    // ---- memory controller (the real one) ----
    reg  [7:0]  ram_din = 0;
    reg         ram_req = 0, ram_write = 0;
    reg  [22:0] ram_addr = 0;
    wire [7:0]  ram_dout;
    wire        ram_busy;
    memory_ctrl mem1 (
        .clk_27m(clk_54), .clk_108m(clk_108), .bus_reset_n(bus_reset_n),
        .video_dhclk(video_dhclk), .video_dlclk(video_dlclk),
        .ram_din(ram_din), .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr),
        .vram_din(8'h00), .vram_write(1'b0), .vram_addr(17'h0),
        .bus_rfsh_n(1'b1),
        .ram_dout(ram_dout), .vram_dout(), .ram_busy(ram_busy),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n), .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm)
    );

    // ---- the proven test vectors (same as sim memtest: byte lanes, rows, high bits, banks 0/1/2) ----
    localparam integer NVEC = 9;
    function [22:0] vaddr(input [3:0] i);
        case (i)
            4'd0: vaddr = 23'h000100; 4'd1: vaddr = 23'h000101; 4'd2: vaddr = 23'h001000;
            4'd3: vaddr = 23'h002001; 4'd4: vaddr = 23'h040000; 4'd5: vaddr = 23'h100000;
            4'd6: vaddr = 23'h1FFFFF; 4'd7: vaddr = 23'h200100; default: vaddr = 23'h400100;
        endcase
    endfunction
    function [7:0] vdata(input [3:0] i);
        case (i)
            4'd0: vdata = 8'hA5; 4'd1: vdata = 8'h5A; 4'd2: vdata = 8'h3C;
            4'd3: vdata = 8'h11; 4'd4: vdata = 8'h22; 4'd5: vdata = 8'h33;
            4'd6: vdata = 8'h44; 4'd7: vdata = 8'h55; default: vdata = 8'h66;
        endcase
    endfunction

    // sync the 108-domain handshake signals into the clk_54 FSM domain (2-FF)
    reg dh0, dh1, dl0, dl1, bz0, bz1;
    always @(posedge clk_54) begin
        dh0 <= video_dhclk; dh1 <= dh0;
        dl0 <= video_dlclk; dl1 <= dl0;
        bz0 <= ram_busy;    bz1 <= bz0;
    end
    wire cpu_window = dh1 & dl1 & ~bz1;   // CPU access phase, controller idle

    // ---- memtest FSM (clk_54) ----
    localparam S_INIT=0, S_WSET=1, S_WACC=2, S_WDONE=3, S_RSET=4, S_RACC=5, S_RCMP=6, S_END=7;
    reg [2:0]  st = S_INIT;
    reg [3:0]  idx = 0;
    reg [23:0] initcnt = 0;
    reg        passed = 0, failed = 0;
    reg [23:0] hb = 0;                      // heartbeat

    always @(posedge clk_54) begin
        hb <= hb + 1;
        if (!bus_reset_n) begin
            st <= S_INIT; idx <= 0; initcnt <= 0; passed <= 0; failed <= 0;
            ram_req <= 0; ram_write <= 0;
        end else case (st)
            S_INIT: begin                   // wait out SDRAM power-on init
                initcnt <= initcnt + 1;
`ifdef SIM_FAST_INIT
                if (initcnt == 24'd15_000) begin st <= S_WSET; idx <= 0; end
`else
                if (initcnt == 24'd2_000_000) begin st <= S_WSET; idx <= 0; end
`endif
            end
            // ---- write pass ----
            S_WSET: begin
                ram_addr <= vaddr(idx); ram_din <= vdata(idx); ram_write <= 1'b1;
                if (cpu_window) begin ram_req <= 1'b1; st <= S_WACC; end
            end
            S_WACC: if (bz1) st <= S_WDONE;             // controller accepted
            S_WDONE: if (!bz1) begin                    // completed
                ram_req <= 1'b0;
                if (idx == NVEC-1) begin st <= S_RSET; idx <= 0; end
                else begin idx <= idx + 1; st <= S_WSET; end
            end
            // ---- read/compare pass ----
            S_RSET: begin
                ram_addr <= vaddr(idx); ram_write <= 1'b0;
                if (cpu_window) begin ram_req <= 1'b1; st <= S_RACC; end
            end
            S_RACC: if (bz1) st <= S_RCMP;
            S_RCMP: if (!bz1) begin
                ram_req <= 1'b0;
                if (ram_dout != vdata(idx)) failed <= 1'b1;
                if (idx == NVEC-1) begin st <= S_END; passed <= ~failed & (ram_dout == vdata(idx)); end
                else begin idx <= idx + 1; st <= S_RSET; end
            end
            S_END: begin passed <= ~failed; end
        endcase
    end

    // active-low LEDs: [0]=running [1]=PASS [2]=FAIL [3]=done [4]=heartbeat
    wire done = (st == S_END);
    assign led = ~{ hb[22], done, failed, (done & ~failed), (st != S_END) };
endmodule
