`timescale 1ns/1ps
// =====================================================
// Asynchronous FIFO (dual clock)
// - Gray-coded pointers + 2-flop synchronizers
// - Flags: full, empty, overflow, underflow
// - DEPTH should be a power-of-2
// =====================================================
module async_fifo #(
  parameter integer DATA_W = 8,
  parameter integer DEPTH  = 16
)(
  // write domain
  input  wire                  wr_clk_i,
  input  wire                  wr_rst_ni,   // async, active-low
  input  wire                  wr_en_i,
  input  wire [DATA_W-1:0]     wr_data_i,
  output wire                  full_o,
  output reg                   overflow_o,

  // read domain
  input  wire                  rd_clk_i,
  input  wire                  rd_rst_ni,   // async, active-low
  input  wire                  rd_en_i,
  output reg  [DATA_W-1:0]     rd_data_o,
  output wire                  empty_o,
  output reg                   underflow_o
);

  // ------- clog2 for vector widths -------
  function integer clog2; input integer v; integer i; begin
    v=v-1; for(i=0; v>0; i=i+1) v=v>>1; clog2=i; end endfunction
  localparam integer A_W = clog2(DEPTH); // address width
  // pointers are A_W+1 wide (extra wrap bit)
  reg [A_W:0] wbin, wgray, rbin, rgray;

  // memory (simple reg array; synthesis maps to dual-port RAM)
  reg [DATA_W-1:0] mem [0:DEPTH-1];

  // ---------- bin<->gray helpers ----------
  function [A_W:0] bin2gray; input [A_W:0] b; begin
    bin2gray = (b >> 1) ^ b;
  end endfunction

  // ---------- Synchronizers ----------
  // sync read gray into write clock domain
  reg [A_W:0] rgray_wq1, rgray_wq2;
  always @(posedge wr_clk_i or negedge wr_rst_ni) begin
    if (!wr_rst_ni) begin
      rgray_wq1 <= { (A_W+1){1'b0} };
      rgray_wq2 <= { (A_W+1){1'b0} };
    end else begin
      rgray_wq1 <= rgray;
      rgray_wq2 <= rgray_wq1;
    end
  end

  // sync write gray into read clock domain
  reg [A_W:0] wgray_rq1, wgray_rq2;
  always @(posedge rd_clk_i or negedge rd_rst_ni) begin
    if (!rd_rst_ni) begin
      wgray_rq1 <= { (A_W+1){1'b0} };
      wgray_rq2 <= { (A_W+1){1'b0} };
    end else begin
      wgray_rq1 <= wgray;
      wgray_rq2 <= wgray_rq1;
    end
  end

  // ---------- Write domain ----------
  wire [A_W:0] wbin_next  = wbin + (wr_en_i & ~full_o);
  wire [A_W-1:0] waddr    = wbin[A_W-1:0];
  wire [A_W:0] wgray_next = bin2gray(wbin_next);

  // full when next write gray equals read gray synced with inverted MSBs
  // (classic Cummings full test)
  wire full_next = (wgray_next == {~rgray_wq2[A_W:A_W-1], rgray_wq2[A_W-2:0]});
  assign full_o  = full_next;

  always @(posedge wr_clk_i or negedge wr_rst_ni) begin
    if (!wr_rst_ni) begin
      wbin       <= { (A_W+1){1'b0} };
      wgray      <= { (A_W+1){1'b0} };
      overflow_o <= 1'b0;
    end else begin
      overflow_o <= 1'b0;
      if (wr_en_i) begin
        if (!full_next) begin
          mem[waddr] <= wr_data_i;
          wbin  <= wbin_next;
          wgray <= wgray_next;
        end else begin
          overflow_o <= 1'b1;
        end
      end
    end
  end

  // ---------- Read domain ----------
  wire [A_W:0] rbin_next  = rbin + (rd_en_i & ~empty_o);
  wire [A_W-1:0] raddr    = rbin[A_W-1:0];
  wire [A_W:0] rgray_next = bin2gray(rbin_next);

  // empty when next read gray equals write gray synced into read domain
  wire empty_next = (rgray_next == wgray_rq2);
  assign empty_o  = (rgray == wgray_rq2); // current empty flag

  always @(posedge rd_clk_i or negedge rd_rst_ni) begin
    if (!rd_rst_ni) begin
      rbin        <= { (A_W+1){1'b0} };
      rgray       <= { (A_W+1){1'b0} };
      rd_data_o   <= { DATA_W{1'b0} };
      underflow_o <= 1'b0;
    end else begin
      underflow_o <= 1'b0;
      if (rd_en_i) begin
        if (!empty_o) begin
          rd_data_o <= mem[raddr];
          rbin  <= rbin_next;
          rgray <= rgray_next;
        end else begin
          underflow_o <= 1'b1;
        end
      end
    end
  end

endmodule
