`timescale 1ns/1ps
// =====================================================
// Synchronous FIFO (single clock)
// - Parameters: DATA_W, DEPTH (power-of-2 recommended)
// - Flags: full, empty, overflow, underflow
// - Clean simultaneous read/write behavior
// =====================================================
module sync_fifo #(
  parameter integer DATA_W = 8,
  parameter integer DEPTH  = 16
)(
  input  wire                  clk_i,
  input  wire                  rst_ni,       // async reset, active-low

  input  wire                  wr_en_i,
  input  wire [DATA_W-1:0]     wr_data_i,
  output wire                  full_o,
  output reg                   overflow_o,

  input  wire                  rd_en_i,
  output reg  [DATA_W-1:0]     rd_data_o,
  output wire                  empty_o,
  output reg                   underflow_o,

  output wire [31:0]           count_o       // occupancy (for debug)
);

  // ------- clog2 for vector widths -------
  function integer clog2; input integer v; integer i; begin
    v = v-1; for (i=0; v>0; i=i+1) v=v>>1; clog2=i;
  end endfunction
  localparam integer A_W = clog2(DEPTH);            // address bits
  // use an extra MSB on pointers to detect wrap
  reg [A_W:0] wptr, rptr;                            // A_W+1 bits
  wire [A_W-1:0] waddr = wptr[A_W-1:0];
  wire [A_W-1:0] raddr = rptr[A_W-1:0];

  // -------- memory array --------
  reg [DATA_W-1:0] mem [0:DEPTH-1];

  // -------- flags --------
  assign empty_o = (wptr == rptr);
  assign full_o  = (wptr[A_W]     != rptr[A_W]) &&
                   (wptr[A_W-1:0] == rptr[A_W-1:0]);

  assign count_o = (wptr - rptr); // unsigned subtraction (A_W+1 wide)

  // -------- write path --------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wptr       <= { (A_W+1){1'b0} };
      overflow_o <= 1'b0;
    end else begin
      overflow_o <= 1'b0;
      if (wr_en_i) begin
        if (!full_o) begin
          mem[waddr] <= wr_data_i;
          wptr       <= wptr + {{A_W{1'b0}},1'b1};
        end else begin
          overflow_o <= 1'b1; // write attempted on full
        end
      end
    end
  end

  // -------- read path --------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rptr        <= { (A_W+1){1'b0} };
      rd_data_o   <= { DATA_W{1'b0} };
      underflow_o <= 1'b0;
    end else begin
      underflow_o <= 1'b0;
      if (rd_en_i) begin
        if (!empty_o) begin
          rd_data_o <= mem[raddr];
          rptr      <= rptr + {{A_W{1'b0}},1'b1};
        end else begin
          underflow_o <= 1'b1; // read attempted on empty
        end
      end
    end
  end

endmodule
