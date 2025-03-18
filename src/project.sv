/*
 * Copyright (c) 2025 Krzysztof Skrzynecki
 * SPDX-License-Identifier: Beerware
 */

`default_nettype none

module counter#(
    parameter CNT_WIDTH = 24
)(
    input wire clk,
    input wire rst_n,

    output reg [CNT_WIDTH-1:0] cnt
);
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      cnt <= 0;
    end else begin
      cnt <= cnt+1;
    end
  end
endmodule

module output_shifter#(
    parameter OUT_WORD_WIDTH = 24
)(
    input wire clk,
    input wire tx_ena,

    input wire dat_clk,

    input wire [OUT_WORD_WIDTH-1:0] word_to_tx,

    output reg was_input_just_fetched,
    output wire tx_dat
);
  reg [OUT_WORD_WIDTH-1:0] tx_word;

  reg prev_ena, prev_dat_clk;

  always @(posedge clk) begin
    prev_ena <= tx_ena;
    prev_dat_clk <= dat_clk;
    was_input_just_fetched <= 0;

    if(tx_ena & (!prev_ena)) begin //rising edge
      tx_word <= word_to_tx;
      was_input_just_fetched <= 1;
    end else begin
      if((!dat_clk) & prev_dat_clk) begin //change data on falling edge, because device will read on rising
        tx_word <= {tx_word[OUT_WORD_WIDTH-2:0], 1'b0};
      end
    end
  end

  assign tx_dat = tx_word[OUT_WORD_WIDTH-1];
endmodule

module latcher#(
    parameter OUT_WORD_WIDTH = 24,
    parameter CNT_WIDTH = 24
)(
    input wire clk,
    input wire trigger,
    input wire clear,

    input wire [CNT_WIDTH-1:0] cnt,

    output reg [OUT_WORD_WIDTH-1:0] latched_time,
    output reg is_out_valid
);

  reg prev_trigger;
  always @(posedge clk) begin
    prev_trigger <= trigger;

    if(trigger & (!prev_trigger) & (!is_out_valid)) begin // rising edge of trigger and out is empty
      latched_time <= cnt;
      is_out_valid <= 1;
    end else begin
      if(clear) begin
        is_out_valid <= 0;
      end
    end
  end
endmodule

module falling_mem_cell#(
  parameter MEM_WIDTH = 24
)(
  input wire clk,
  input wire rst_n,
  input wire is_in,
  input wire if_next_used,
  input wire [MEM_WIDTH-1:0] din,

  output reg is_out,
  output reg [MEM_WIDTH-1:0] dout
);
  wire if_latch_new_data;
  wire if_will_be_data;
  //is_in | is_out | if_next_used  || if_latch | if_will_be_data
  //    0        0              0 ||        0                 0
  //    0        0              1 ||        0                 0
  //    0        1              0 ||        0                 0
  //    0        1              1 ||        0                 1
  //    1        0              0 ||        1                 1
  //    1        0              1 ||        1                 1
  //    1        1              0 ||        0                 0
  //    1        1              1 ||        0                 1

  assign if_latch_new_data = (is_in & (!is_out));
  assign if_will_be_data = (is_out & if_next_used) | if_latch_new_data;

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      is_out <= 0;
    end else begin
      if(if_latch_new_data) begin
        dout <= din;
      end

      is_out <= if_will_be_data;
    end
  end
endmodule

module falling_mem#(
  parameter MEM_WIDTH = 24,
  parameter NUM_CELLS = 4
)(
  input wire clk,
  input wire rst_n,
  input wire is_in,
  input wire if_next_used, //mem assumes that when next is not used, it will read the data, so last cell can get new data
  input wire [MEM_WIDTH-1:0] din,

  output wire is_out,
  output wire is_mem_full,
  output wire [MEM_WIDTH-1:0] dout
);
  wire [MEM_WIDTH-1:0] mem_regs [NUM_CELLS:0];

  wire [NUM_CELLS:-1] data_is_avail_flag;

  assign data_is_avail_flag[NUM_CELLS] = is_in;
  assign is_out = data_is_avail_flag[0];

  assign is_mem_full = data_is_avail_flag[NUM_CELLS-1];

  assign data_is_avail_flag[-1]=if_next_used;

  assign mem_regs[NUM_CELLS] = din;

  genvar i;
  generate // mem propagates downwards, towards 0
      for (i = 0; i < NUM_CELLS; i = i + 1) begin : shift_gen
        falling_mem_cell#(
          .MEM_WIDTH(MEM_WIDTH)
        )mem(
          .clk(clk),
          .rst_n(rst_n),
          .is_in(data_is_avail_flag[i+1]),
          .if_next_used(data_is_avail_flag[i-1]),
          .din(mem_regs[i+1]),

          .is_out(data_is_avail_flag[i]),
          .dout(mem_regs[i])
        );
      end
  endgenerate

  assign dout = mem_regs[0];

endmodule

module single_channel_with_buffer#(
  parameter OUT_WORD_WIDTH = 24,
  parameter CNT_WIDTH = 24,
  parameter NUM_MEM_CELLS = 4
)(
  input wire clk,
  input wire rst_n,
  input wire [CNT_WIDTH-1:0] cnt,
  input wire trigg,
  input wire is_timestamp_popped_from_q,

  output wire is_timestamp_present_on_q,
  output wire [OUT_WORD_WIDTH-1:0] timestamp_on_queue
);
  wire is_timestamp_present;
  wire is_mem_full;

  reg [OUT_WORD_WIDTH-1:0] timestamp_on_latch;

  latcher#(.OUT_WORD_WIDTH(OUT_WORD_WIDTH), .CNT_WIDTH(CNT_WIDTH))ltch(
    .clk(clk),
    .trigger(trigg),
    .clear(!is_mem_full),

    .cnt(cnt),

    .latched_time(timestamp_on_latch),
    .is_out_valid(is_timestamp_present)
  );

  falling_mem#(
    .MEM_WIDTH(OUT_WORD_WIDTH),
    .NUM_CELLS(NUM_MEM_CELLS)
  )mem(
    .clk(clk),
    .rst_n(rst_n),
    .is_in(is_timestamp_present),
    .if_next_used(!is_timestamp_popped_from_q),
    .din(timestamp_on_latch),

    .is_out(is_timestamp_present_on_q),
    .is_mem_full(is_mem_full),
    .dout(timestamp_on_queue)
  );
endmodule

module triggerer(
  input wire clk,
  input wire rst_n,
  input wire DAT_CLK,
  input wire DAT_ENA,
  input wire TRIGG_0,

  output wire DAT_RDY,
  output wire DAT_OUT
);
  localparam CNT_WIDTH = 24;
  localparam OUT_WORD_WIDTH = 24;
  localparam NUM_MEM_CELLS = 4; //per channel

  reg [CNT_WIDTH-1:0] master_cnt;

  wire [OUT_WORD_WIDTH-1:0] timestamp_on_queue;
  wire is_timestamp_popped_from_q;
  wire is_timestamp_present_on_q;

  counter#(.CNT_WIDTH(CNT_WIDTH))cnt0(
    .clk(clk),
    .rst_n(rst_n),

    .cnt(master_cnt)
  );

  single_channel_with_buffer#(
    .OUT_WORD_WIDTH(OUT_WORD_WIDTH),
    .CNT_WIDTH(CNT_WIDTH),
    .NUM_MEM_CELLS(NUM_MEM_CELLS)
  )trigg_channel(
    .clk(clk),
    .rst_n(rst_n),
    .cnt(master_cnt),
    .trigg(TRIGG_0),
    .is_timestamp_popped_from_q(is_timestamp_popped_from_q),

    .is_timestamp_present_on_q(is_timestamp_present_on_q),
    .timestamp_on_queue(timestamp_on_queue)
  );

  assign DAT_RDY = is_timestamp_present_on_q;

  output_shifter#(
    .OUT_WORD_WIDTH(OUT_WORD_WIDTH)
  )shft(
    .clk(clk),
    .tx_ena(DAT_ENA),
    .dat_clk(DAT_CLK),

    .word_to_tx(timestamp_on_queue),
    .was_input_just_fetched(is_timestamp_popped_from_q),

    .tx_dat(DAT_OUT)
  );
endmodule

module tt_um_tetrap_triggerer (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  // inputs
  wire DAT_CLK;
  wire DAT_ENA;
  wire TRIGG_0;

  // outputs
  wire DAT_RDY;
  wire DAT_OUT;

  assign DAT_CLK = ui_in[0];
  assign DAT_ENA = ui_in[1];
  assign TRIGG_0 = ui_in[2];

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = {6'b0, DAT_RDY, DAT_OUT};  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  triggerer trgg(
    .clk(clk),
    .rst_n(rst_n),
    .DAT_CLK(DAT_CLK),
    .DAT_ENA(DAT_ENA),
    .TRIGG_0(TRIGG_0),

    .DAT_RDY(DAT_RDY),
    .DAT_OUT(DAT_OUT)
  );

  // List all unused inputs to prevent warnings
  wire _unused = &{&ui_in, &uio_in, ena, 1'b0};
endmodule
