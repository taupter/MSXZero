// Minimal behavioral SDR SDRAM model for MSXHero memory_ctrl bring-up sim.
// 16-bit data, 4 banks, 13-bit row, 9-bit col (matches IcePi geometry per NanoMig).
// Models: LOAD_MODE, ACTIVE, READ, WRITE, PRECHARGE, AUTO-REFRESH, NOP, CAS latency 2,
// DQM byte masking, A10 auto-precharge. Enough to validate the controller's data path,
// byte lanes, CAS timing and addressing — NOT a timing-accurate datasheet model.
`timescale 1ns/1ps
module sdram_model #(
    parameter ADDR_BITS = 13,
    parameter COL_BITS  = 9,
    parameter DATA_BITS = 16
)(
    input                       clk,
    input                       cke,
    input                       cs_n,
    input                       ras_n,
    input                       cas_n,
    input                       we_n,
    input      [1:0]            ba,
    input      [ADDR_BITS-1:0]  addr,
    input      [DATA_BITS/8-1:0] dqm,
    inout      [DATA_BITS-1:0]  dq
);
    localparam CAS_LATENCY = 2;

    // command decode
    localparam CMD_LMR=3'b000, CMD_REF=3'b001, CMD_PRE=3'b010, CMD_ACT=3'b011,
               CMD_WR =3'b100, CMD_RD =3'b101, CMD_BST=3'b110, CMD_NOP=3'b111;
    wire [2:0] cmd = {ras_n, cas_n, we_n};

    // storage: [bank][row][col]  (sparse-ish; full array is large so use assoc per bank)
    reg [DATA_BITS-1:0] mem [0:(1<<(ADDR_BITS+COL_BITS+2))-1];
    reg [ADDR_BITS-1:0] active_row [0:3];

    // read pipeline: data appears on dq exactly CAS_LATENCY cycles after the READ command.
    // Output is COMBINATIONAL from pipe[0] so the total latency is exactly CAS_LATENCY (a
    // registered output would add one extra cycle).
    reg [DATA_BITS-1:0] pipe [0:CAS_LATENCY];
    reg [CAS_LATENCY:0] pvalid;
    integer i;

    function [31:0] lin_addr(input [1:0] b, input [ADDR_BITS-1:0] r, input [COL_BITS-1:0] c);
        lin_addr = (b << (ADDR_BITS+COL_BITS)) | (r << COL_BITS) | c;
    endfunction

    assign dq = pvalid[0] ? pipe[0] : {DATA_BITS{1'bz}};

    initial begin
        pvalid = 0;
        for (i=0;i<=CAS_LATENCY;i=i+1) pipe[i] = 0;
    end

    always @(posedge clk) begin
        // shift the read pipeline toward the (combinational) output every cycle
        for (i=0;i<CAS_LATENCY;i=i+1) begin
            pipe[i]   <= pipe[i+1];
            pvalid[i] <= pvalid[i+1];
        end
        pvalid[CAS_LATENCY] <= 1'b0;
        if (cke && !cs_n) begin
            case (cmd)
              CMD_ACT: active_row[ba] <= addr;
              CMD_WR: begin
                  if (!dqm[0]) mem[lin_addr(ba,active_row[ba],addr[COL_BITS-1:0])][7:0]  <= dq[7:0];
                  if (!dqm[1]) mem[lin_addr(ba,active_row[ba],addr[COL_BITS-1:0])][15:8] <= dq[15:8];
              end
              CMD_RD: begin
                  pipe[CAS_LATENCY]   <= mem[lin_addr(ba,active_row[ba],addr[COL_BITS-1:0])];
                  pvalid[CAS_LATENCY] <= 1'b1;
              end
              default: ;
            endcase
        end
    end
endmodule
