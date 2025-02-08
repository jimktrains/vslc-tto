/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc (

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
wire [8:0]_unused;

assign _unused = {ledout, addr_strobe};

tt_um_jimktrains_vslc_core c(
  ui_in,
  uo_out,
  uio_in,
  uio_out,
  uio_oe,
  ena,
  clk,
  rst_n,
  8'h0,
  8'h0,
  ledout,
  addr_strobe
);
endmodule
