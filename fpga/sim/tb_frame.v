// C-BIOS boot + VRAM frame dump. Pre-loads C-BIOS into the SDRAM model at the BIOS/sub-ROM
// regions (skipping the slow 512KB flash copy via SIM_FAST_BOOT's shrunk GOAULD_ROM_SIZE),
// runs the boot, and watches the CPU execute C-BIOS + the VDP write VRAM.
//   EXTRA_DEFINES="-DSIM_FAST_BOOT -DSIM_FAST_INIT" ./sim/gen_full_sim.sh
//   iverilog -g2012 -o sim/simframe sim/tb_frame.v sim/sim_msx.v sim/ecp5_prims_sim.v sim/sdram_model.v
//   vvp sim/simframe
`timescale 1ns/1ps
module tb_frame;
    reg ex_clk_27m = 0, s1 = 0, s2 = 0;
    reg mspi_miso_r = 0; wire mspi_miso; assign mspi_miso = mspi_miso_r;
    reg [5:0] joya = 6'h3f, joyb = 6'h3f;
    reg uart_rx = 1;
    wire [15:0] IO_sdram_dq;
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [12:0] O_sdram_addr; wire [1:0] O_sdram_ba, O_sdram_dqm;
    wire [5:0] led; wire ws2812_led; wire [2:0] data_p, data_n; wire clk_p, clk_n;
    wire mspi_cs, mspi_mosi, sd_sclk, sd_cmd, uart_tx, usb_uart_tx;  // ECP5: mspi_sclk is via USRMCLK, not a port
    wire [4:0] m0s; wire spi_sclk, spi_csn, spi_dir, spi_irqn;
    tri1 spi_dat, sd_dat0, sd_dat1, sd_dat2, sd_dat3;

    always #10 ex_clk_27m = ~ex_clk_27m;   // 50 MHz

    top dut (
        .ex_clk_27m(ex_clk_27m), .s1(s1), .s2(s2), .m0s(m0s),
        .spi_sclk(spi_sclk), .spi_csn(spi_csn), .spi_dir(spi_dir), .spi_dat(spi_dat), .spi_irqn(spi_irqn),
        .led(led), .ws2812_led(ws2812_led), .data_p(data_p), .data_n(data_n), .clk_p(clk_p), .clk_n(clk_n),
        .mspi_cs(mspi_cs), .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi),
        .sd_sclk(sd_sclk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1), .sd_dat2(sd_dat2), .sd_dat3(sd_dat3),
        .uart_tx(uart_tx), .uart_rx(uart_rx), .usb_uart_tx(usb_uart_tx),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n), .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm), .joya(joya), .joyb(joyb)
    );
    sdram_model sdram (
        .clk(O_sdram_clk), .cke(O_sdram_cke), .cs_n(O_sdram_cs_n), .ras_n(O_sdram_ras_n),
        .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n), .ba(O_sdram_ba), .addr(O_sdram_addr),
        .dqm(O_sdram_dqm), .dq(IO_sdram_dq)
    );

    // ---- pre-load C-BIOS into the SDRAM model (BIOS@0x760000, sub@0x768000) ----
    reg [7:0] biosrom [0:32767];
    reg [7:0] subrom  [0:16383];
    integer j, A, w;
    function integer wordidx(input integer a);
        wordidx = (((a>>21)&3)<<22) | (((a>>1)&13'h0FFF)<<9) | ((a>>13)&9'h0FF);
    endfunction
    initial begin
        $readmemh("sim/cbios_main.hex", biosrom);
        $readmemh("sim/cbios_sub.hex",  subrom);
        for (j=0; j<32768; j=j+1) begin
            A = 24'h760000 + j; w = wordidx(A);
            if (A[0]==0) sdram.mem[w][7:0] = biosrom[j]; else sdram.mem[w][15:8] = biosrom[j];
        end
        for (j=0; j<16384; j=j+1) begin
            A = 24'h768000 + j; w = wordidx(A);
            if (A[0]==0) sdram.mem[w][7:0] = subrom[j]; else sdram.mem[w][15:8] = subrom[j];
        end
        $display("pre-loaded C-BIOS: 32K BIOS @0x760000, 16K sub @0x768000");
    end

    initial begin s1 = 1; #2000 s1 = 0; end

    // observe: SDRAM reads to the BIOS region (bank3) = CPU executing C-BIOS; VDP VRAM writes
    integer bios_reads = 0, vram_writes = 0;
    wire [2:0] cmd = {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n};
    always @(posedge O_sdram_clk) if (O_sdram_cke && !O_sdram_cs_n) begin
        if (cmd==3'b101 && O_sdram_ba==3 && O_sdram_addr[8:0] < 9'h0E0) bios_reads = bios_reads+1;   // read, bank3, col<0xE0 = BIOS/sub
        if (cmd==3'b100 && O_sdram_ba==3 && O_sdram_addr[8:5]==4'b1110) vram_writes = vram_writes+1;  // write, bank3, col 0xE0+ = VRAM
    end

    // live status (flushed each report so the run can be monitored)
    integer sf;
    task report;
        begin
            $fdisplay(sf, "t=%0d us  bios_reads=%0d  vram_writes=%0d", $time/1000000, bios_reads, vram_writes);
            $fflush(sf);
        end
    endtask

    // read one VRAM byte from the SDRAM model (VDP mapping: bank3, row=V[11:1], col={111,V[16:12]}).
    function [7:0] vram_byte(input integer V);
        integer wi; reg [15:0] w;
        begin
            wi = (3<<22) | (((V>>1)&11'h7FF)<<9) | (9'h0E0 | ((V>>12)&5'h1F));
            w = sdram.mem[wi];
            vram_byte = V[0] ? w[15:8] : w[7:0];
        end
    endfunction

    // dump the low 8KB of VRAM (name/pattern tables) as bytes — integer counter, no overflow.
    task dump_vram;
        integer fd, V, nz;
        begin
            fd = $fopen("sim/vram_dump.txt", "w"); nz = 0;
            for (V=0; V<8192; V=V+1) begin
                $fwrite(fd, "%02x\n", vram_byte(V));
                if (vram_byte(V) !== 8'h00 && vram_byte(V) !== 8'hxx) nz = nz+1;
            end
            $fclose(fd);
            $fdisplay(sf, "dumped sim/vram_dump.txt (non-zero bytes in low 8KB = %0d)", nz); $fflush(sf);
        end
    endtask

    integer k;
    initial begin
        sf = $fopen("sim/frame_status.txt", "w");
        for (k=0; k<40; k=k+1) begin
            #2000000 report;                       // every 2ms
            if (vram_writes > 400) begin           // screen is being drawn -> dump early and stop
                dump_vram; $fdisplay(sf,"EARLY-DONE screen drawn"); $fflush(sf); $finish;
            end
        end
        dump_vram; $fdisplay(sf,"DONE (80ms) bios_reads=%0d vram_writes=%0d", bios_reads, vram_writes); $fflush(sf);
        $finish;
    end
endmodule
