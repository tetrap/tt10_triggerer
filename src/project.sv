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
  localparam CNT_WIDTH = 24;

  reg [CNT_WIDTH-1:0] master_cnt;

  counter#(.CNT_WIDTH(CNT_WIDTH))cnt0(
      .clk(clk),
      .rst_n(rst_n),

      .cnt(master_cnt)
  );


  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = ui_in + uio_in + master_cnt[17:10];  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule
