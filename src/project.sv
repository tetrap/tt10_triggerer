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

    output wire tx_dat
);
  reg [OUT_WORD_WIDTH-1:0] tx_word;

  reg prev_ena, prev_dat_clk;

  always @(posedge clk) begin
    prev_ena <= tx_ena;
    prev_dat_clk <= dat_clk;

    if(tx_ena & (!prev_ena)) begin //rising edge
      tx_word <= word_to_tx;
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
    //input wire clear,

    input wire [CNT_WIDTH-1:0] cnt,

    output reg [OUT_WORD_WIDTH-1:0] latched_time
    //output reg is_out_busy
);

  reg prev_trigger;
  always @(posedge clk) begin
    prev_trigger <= trigger;

    if(trigger & (!prev_trigger)) begin
      latched_time <= cnt;
    end
  end
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
  
  reg [CNT_WIDTH-1:0] master_cnt;

  reg [OUT_WORD_WIDTH-1:0] out_reg;

  counter#(.CNT_WIDTH(CNT_WIDTH))cnt0(
    .clk(clk),
    .rst_n(rst_n),

    .cnt(master_cnt)
  );

  latcher#(.OUT_WORD_WIDTH(OUT_WORD_WIDTH), .CNT_WIDTH(CNT_WIDTH))ltch(
    .clk(clk),
    .trigger(TRIGG_0),
    .cnt(master_cnt),

    .latched_time(out_reg)
  );

  output_shifter#(
    .OUT_WORD_WIDTH(OUT_WORD_WIDTH)
  )shft(
    .clk(clk),
    .tx_ena(DAT_ENA),
    .dat_clk(DAT_CLK),

    .word_to_tx(out_reg),

    .tx_dat(DAT_OUT)
  );

  assign DAT_RDY = 0;

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
  wire _unused = &{ena, 1'b0};
endmodule
