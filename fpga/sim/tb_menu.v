// Menu-boot sim: pre-loads the FULL goauld pack (built around C-BIOS, no copyrighted ROMs) into the
// SDRAM model at 0x700000, so every MSX slot is populated — Nextor, C-BIOS BIOS/sub, the boot MENU
// (auto-boot 'AB' ROM), WiFi ROM, logo, config. Unlike the bare-C-BIOS boot (empty slots), this lets
// the BIOS slot-scan find + run the menu. Watches for the VDP drawing a screen (vram_writes).
//   EXTRA_DEFINES="-DSIM_FAST_BOOT -DSIM_FAST_INIT" ./sim/gen_full_sim.sh
//   iverilog -g2012 -o sim/simmenu sim/tb_menu.v sim/sim_msx.v sim/ecp5_prims_sim.v sim/sdram_model.v
//   vvp sim/simmenu
`timescale 1ns/1ps
module tb_menu;
    reg ex_clk_27m = 0, s1 = 0, s2 = 0;
    reg mspi_miso_r = 0; wire mspi_miso; assign mspi_miso = mspi_miso_r;
    reg [5:0] joya = 6'h3f, joyb = 6'h3f;
    reg uart_rx = 1;
    wire [15:0] IO_sdram_dq;
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [12:0] O_sdram_addr; wire [1:0] O_sdram_ba, O_sdram_dqm;
    wire [5:0] led; wire ws2812_led; wire [2:0] data_p, data_n; wire clk_p, clk_n;
    wire mspi_cs, mspi_mosi, sd_sclk, sd_cmd, uart_tx, usb_uart_tx;
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

    // ---- pre-load the full goauld pack (C-BIOS build) into the SDRAM model at 0x700000 ----
    reg [7:0] pack [0:524293];
    integer j, A, w;
    function integer wordidx(input integer a);
        wordidx = (((a>>21)&3)<<22) | (((a>>1)&13'h0FFF)<<9) | ((a>>13)&9'h0FF);
    endfunction
    initial begin
        $readmemh("sim/goauld_cbios.hex", pack);
        for (j=0; j<524294; j=j+1) begin
            A = 24'h700000 + j; w = wordidx(A);
            if (A[0]==0) sdram.mem[w][7:0] = pack[j]; else sdram.mem[w][15:8] = pack[j];
        end
        $display("pre-loaded goauld pack (C-BIOS): 512K+6 @0x700000 (BIOS@0x760000, menu@0x76C000)");
    end

    initial begin s1 = 1; #2000 s1 = 0; end

    // observe: CPU ROM fetches (bank3, col<0xE0) and VDP VRAM writes (bank3, col 0xE0+)
    integer bios_reads = 0, vram_writes = 0;
    wire [2:0] cmd = {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n};
    always @(posedge O_sdram_clk) if (O_sdram_cke && !O_sdram_cs_n) begin
        if (cmd==3'b101 && O_sdram_ba==3 && O_sdram_addr[8:0] < 9'h0E0) bios_reads = bios_reads+1;
        if (cmd==3'b100 && O_sdram_ba==3 && O_sdram_addr[8:5]==4'b1110) vram_writes = vram_writes+1;
    end

    integer sf;
    task report;
        begin
            $fdisplay(sf, "t=%0d us  bios_reads=%0d  vram_writes=%0d", $time/1000000, bios_reads, vram_writes);
            $fflush(sf);
        end
    endtask

    function [7:0] vram_byte(input integer V);
        integer wi; reg [15:0] w;
        begin
            wi = (3<<22) | (((V>>1)&11'h7FF)<<9) | (9'h0E0 | ((V>>12)&5'h1F));
            w = sdram.mem[wi];
            vram_byte = V[0] ? w[15:8] : w[7:0];
        end
    endfunction

    task dump_vram;
        integer fd, V, nz;
        begin
            fd = $fopen("sim/menu_vram_dump.txt", "w"); nz = 0;
            for (V=0; V<8192; V=V+1) begin
                $fwrite(fd, "%02x\n", vram_byte(V));
                if (vram_byte(V) !== 8'h00 && vram_byte(V) !== 8'hxx) nz = nz+1;
            end
            $fclose(fd);
            $fdisplay(sf, "dumped sim/menu_vram_dump.txt (non-zero bytes in low 8KB = %0d)", nz); $fflush(sf);
        end
    endtask

    integer k;
    initial begin
        sf = $fopen("sim/menu_status.txt", "w");
        for (k=0; k<50; k=k+1) begin
            #2000000 report;                       // every 2ms, up to 100ms
            if (vram_writes > 400) begin
                dump_vram; $fdisplay(sf,"EARLY-DONE screen drawn"); $fflush(sf); $finish;
            end
        end
        dump_vram; $fdisplay(sf,"DONE (100ms) bios_reads=%0d vram_writes=%0d", bios_reads, vram_writes); $fflush(sf);
        $finish;
    end
endmodule
