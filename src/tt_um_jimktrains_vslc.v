/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc
#(
  parameter SPI_CLK_DIV = 3,
  parameter TIMER_CLK_DIV = 7,
  parameter SERVO_CLK_DIV = 5
) (

  input  wire [7:0] ui_in,   // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n    // reset_n - low to reset
);

wire [7:0]ledout;
wire addr_strobe;
wire [9:0]_unused;
wire scan_cycle_clk;

assign _unused = {ledout, addr_strobe, scan_cycle_clk};

tt_um_jimktrains_vslc_core #(
  .SPI_CLK_DIV(SPI_CLK_DIV),
  .TIMER_CLK_DIV(TIMER_CLK_DIV),
  .SERVO_CLK_DIV(SERVO_CLK_DIV)
) core (
  ui_in,
  uo_out,
  uio_in,
  uio_out,
  uio_oe,
  ena,
  clk,
  rst_n,
  addr_strobe,
  scan_cycle_clk
);
endmodule
