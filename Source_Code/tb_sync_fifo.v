`timescale 1ns/1ps
// =====================================================
// Testbench: sync_fifo
// - Covers overflow, underflow, simultaneous R/W, random bursts
// =====================================================
module tb_sync_fifo;

  parameter integer DATA_W = 8;
  parameter integer DEPTH  = 16;

  reg                   clk;
  reg                   rst_n;
  reg                   wr_en;
  reg  [DATA_W-1:0]     wr_data;
  wire                  full;
  wire                  overflow;
  reg                   rd_en;
  wire [DATA_W-1:0]     rd_data;
  wire                  empty;
  wire                  underflow;
  wire [31:0]           count;

  // DUT
  sync_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .wr_en_i     (wr_en),
    .wr_data_i   (wr_data),
    .full_o      (full),
    .overflow_o  (overflow),
    .rd_en_i     (rd_en),
    .rd_data_o   (rd_data),
    .empty_o     (empty),
    .underflow_o (underflow),
    .count_o     (count)
  );

  // clock
  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // model expected order using simple array + indices
  reg [DATA_W-1:0] model_q [0:DEPTH*4-1];
  integer qi, qo, qcount;

  task push_model; input [DATA_W-1:0] d; begin
    model_q[qi] = d; qi = qi + 1; qcount = qcount + 1;
  end endtask

  task pop_check; input [DATA_W-1:0] d; begin
    if (qcount == 0) begin
      $display("[%0t] MODEL UNDERFLOW!", $time);
      $finish;
    end
    if (model_q[qo] !== d) begin
      $display("[%0t] MISMATCH exp=0x%02h got=0x%02h", $time, model_q[qo], d);
      $finish;
    end
    qo = qo + 1; qcount = qcount - 1;
  end endtask

  task tick; begin @(posedge clk); #1; end endtask

  integer i;

  initial begin
    // init
    wr_en=0; wr_data=0; rd_en=0; qi=0; qo=0; qcount=0;
    rst_n = 0; repeat (5) tick(); rst_n = 1; tick();

    // 1) Fill to full
    $display("FILL to FULL");
    for (i=0;i<DEPTH;i=i+1) begin
      wr_data = i; wr_en = 1; rd_en = 0; tick();
      push_model(i);
    end
    wr_en = 0; tick();
    if (!full) begin $display("ERROR: full not set after fill"); $finish; end

    // 2) Overflow attempt
    wr_data = 8'hEE; wr_en = 1; tick();
    if (!overflow) begin $display("ERROR: overflow flag not set"); $finish; end
    wr_en = 0; tick();

    // 3) Simultaneous R/W for a few cycles (should keep occupancy ~constant)
    $display("SIMULTANEOUS R/W");
    for (i=0;i<8;i=i+1) begin
      wr_data = (8'hA0 + i);
      wr_en = 1; rd_en = 1; tick();
      // model: first pop then push (matches FIFO behavior of reading old, writing new)
      pop_check(rd_data);
      push_model(8'hA0 + i);
    end
    wr_en=0; rd_en=0; tick();

    // 4) Drain all data
    $display("DRAIN ALL");
    while (!empty) begin
      rd_en = 1; tick(); pop_check(rd_data);
    end
    rd_en = 0; tick();
    if (!empty) begin $display("ERROR: empty not set"); $finish; end

    // 5) Underflow attempt
    rd_en = 1; tick();
    if (!underflow) begin $display("ERROR: underflow flag not set"); $finish; end
    rd_en = 0; tick();

    // 6) Random burst mixes
    $display("RANDOM BURSTS");
    for (i=0;i<200;i=i+1) begin
      // random write
      if ($random & 1) begin
        wr_data = $random;
        wr_en   = ~full;
        if (wr_en) push_model(wr_data);
      end else begin
        wr_en = 0;
      end
      // random read
      if ($random & 1) begin
        rd_en = ~empty;
        if (rd_en) begin tick(); pop_check(rd_data); rd_en=0; wr_en=0; end
        else tick();
      end else begin
        tick();
      end
    end

    $display("\nSYNC FIFO TESTS PASSED ✅");
    $finish;
  end

endmodule
