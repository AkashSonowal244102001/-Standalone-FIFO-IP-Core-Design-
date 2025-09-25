`timescale 1ns/1ps
// =====================================================
// Testbench: async_fifo
// - Different write/read clocks
// - Covers overflow, underflow, simultaneous R/W, random bursts
// =====================================================
module tb_async_fifo;

  parameter integer DATA_W = 8;
  parameter integer DEPTH  = 16;

  reg                   wr_clk, rd_clk;
  reg                   wr_rst_n, rd_rst_n;
  reg                   wr_en;
  reg  [DATA_W-1:0]     wr_data;
  wire                  full;
  wire                  overflow;
  reg                   rd_en;
  wire [DATA_W-1:0]     rd_data;
  wire                  empty;
  wire                  underflow;

  // DUT
  async_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
    .wr_clk_i     (wr_clk),
    .wr_rst_ni    (wr_rst_n),
    .wr_en_i      (wr_en),
    .wr_data_i    (wr_data),
    .full_o       (full),
    .overflow_o   (overflow),

    .rd_clk_i     (rd_clk),
    .rd_rst_ni    (rd_rst_n),
    .rd_en_i      (rd_en),
    .rd_data_o    (rd_data),
    .empty_o      (empty),
    .underflow_o  (underflow)
  );

  // clocks: 80 MHz write, 60 MHz read (asynchronous)
  initial begin wr_clk=0; forever #6.25 wr_clk=~wr_clk; end
  initial begin rd_clk=0; forever #8.333 rd_clk=~rd_clk; end

  // simple scoreboard
  reg [DATA_W-1:0] model_q [0:DEPTH*8-1];
  integer qi, qo, qcount;

  task push_model; input [DATA_W-1:0] d; begin
    model_q[qi] = d; qi = qi + 1; qcount = qcount + 1;
  end endtask

  task pop_check; input [DATA_W-1:0] d; begin
    if (qcount == 0) begin
      $display("[%0t] MODEL UNDERFLOW (async)!", $time);
      $finish;
    end
    if (model_q[qo] !== d) begin
      $display("[%0t] ASYNC MISMATCH exp=0x%02h got=0x%02h", $time, model_q[qo], d);
      $finish;
    end
    qo = qo + 1; qcount = qcount - 1;
  end endtask

  // handy waiters
  task wr_tick; begin @(posedge wr_clk); #1; end endtask
  task rd_tick; begin @(posedge rd_clk); #1; end endtask

  integer i;

  initial begin
    wr_en=0; wr_data=0; rd_en=0;
    qi=0; qo=0; qcount=0;

    // resets
    wr_rst_n=0; rd_rst_n=0;
    repeat (5) wr_tick();
    repeat (5) rd_tick();
    wr_rst_n=1; rd_rst_n=1;

    // 1) Fill until full (write faster than read)
    for (i=0;i<DEPTH;i=i+1) begin
      @(posedge wr_clk);
      if (!full) begin wr_en=1; wr_data=i; push_model(i); end
      else wr_en=0;
    end
    wr_en=0;
    // overflow attempt
    @(posedge wr_clk); wr_en=1; wr_data=8'hEE;
    @(posedge wr_clk); wr_en=0;
    if (!overflow) begin $display("ERROR: async overflow not set"); $finish; end

    // 2) Start reading some data while still writing (simultaneous)
    for (i=0;i<20;i=i+1) begin
      @(posedge wr_clk);
      if (!full) begin wr_en=1; wr_data=(8'hA0+i); push_model(8'hA0+i); end
      else wr_en=0;
      @(posedge rd_clk);
      if (!empty) begin rd_en=1; @(posedge rd_clk); rd_en=0; pop_check(rd_data); end
    end
    wr_en=0;

    // 3) Drain completely
    while (!empty) begin
      @(posedge rd_clk); rd_en=1;
      @(posedge rd_clk); rd_en=0; pop_check(rd_data);
    end
    // underflow attempt
    @(posedge rd_clk); rd_en=1;
    @(posedge rd_clk); rd_en=0;
    if (!underflow) begin $display("ERROR: async underflow not set"); $finish; end

    // 4) Random bursts with unrelated clocks
    for (i=0;i<300;i=i+1) begin
      // random write on wr clock
      @(posedge wr_clk);
      if (($random & 3) != 0) begin
        wr_en   = ~full;
        wr_data = $random;
        if (wr_en) push_model(wr_data);
      end else wr_en=0;

      // random read on rd clock
      @(posedge rd_clk);
      if (($random & 3) != 0) begin
        rd_en = ~empty;
        if (rd_en) begin
          @(posedge rd_clk); rd_en=0; pop_check(rd_data);
        end
      end else rd_en=0;
    end

    $display("\nASYNC FIFO TESTS PASSED ✅");
    $finish;
  end

endmodule
