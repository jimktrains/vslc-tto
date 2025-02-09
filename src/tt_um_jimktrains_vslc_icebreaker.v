/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc_icebreaker (
	input  CLK,
	input  BTN_N,
  input  BTN1,
  input  BTN2,
  input  BTN3,
  output P1A1,
  output P1A2,
  output P1A3,
  output P1A4,
  output P1A7,
  output P1A8,
  output P1A9,
  output P1A10,
  output LED1,
  output LED2,
  output LED3,
  output LED4,
  output LED5,
  output LEDR_N,
  output LEDG_N,
  output LED_BLU_N,
  output LED_GRN_N,
  output LED_RED_N,
  output FLASH_IO0,
  output FLASH_IO1,
  inout [7:0]uio
);
wire [7:0]ledout;
wire addr_strobe;

wire [7:0] uio_oe;
wire [7:0] uio_in;
wire [7:0] uio_out;

wire [7:0] ui_in;
wire [7:0] uo_out;

assign ui_in[0] = BTN_N;
assign ui_in[1] = BTN1;
assign ui_in[2] = BTN2;
assign ui_in[3] = BTN3;

assign LED1 = uo_out[0];
assign LED2 = uo_out[1];
assign LED3 = uo_out[2];
assign LED4 = uo_out[3];
assign LED5 = uo_out[4];
assign LEDR_N = !uo_out[5];
assign LEDG_N = !uo_out[6];
assign LED_BLU_N = !uo_out[7];

assign uio[0] = uio_oe[0] ? uio_out[0] : 1'bz;
assign uio[1] = uio_oe[1] ? uio_out[1] : 1'bz;
assign uio[2] = uio_oe[2] ? uio_out[2] : 1'bz;
assign uio[3] = uio_oe[3] ? uio_out[3] : 1'bz;
assign uio[4] = uio_oe[4] ? uio_out[4] : 1'bz;
assign uio[5] = uio_oe[5] ? uio_out[5] : 1'bz;
assign uio[6] = uio_oe[6] ? uio_out[6] : 1'bz;
assign uio[7] = uio_oe[7] ? uio_out[7] : 1'bz;
assign uio_in[0] = uio[0];
assign uio_in[1] = uio[1];
assign uio_in[2] = uio[2];
assign uio_in[3] = uio[3];
assign uio_in[4] = uio[4];
assign uio_in[5] = uio[5];
assign uio_in[6] = uio[6];
assign uio_in[7] = uio[7];

wire ena = 1;

reg [31:0]counter = 0;

reg rst_n = 0;
assign LED_GRN_N = BTN_N;//counter[23];
assign LED_RED_N = 1;

reg a,b,c,d,e,f,g, en1, en2, dp;

assign {P1A1, FLASH_IO0, P1A2, P1A3, P1A4, P1A7, P1A8, P1A9, P1A10, FLASH_IO1} =  {en1, en2, a,f,b,g,c,d,e,dp};

tt_um_jimktrains_vslc_core core(
  ui_in,
  uo_out,
  uio_in,
  uio_out,
  uio_oe,
  ena,
  CLK,
  rst_n,
  8,
  20,
  ledout,
  addr_strobe,
  scan_cycle_clk
);

wire scan_cycle_clk;

always @(posedge CLK) begin
  counter <= counter + 1;
  rst_n <= rst_n ? rst_n : counter < 8;
  if (!counter[6]) {en1, en2, a,b,c,d,e,f,g,dp} <= {1'b0,1'b1,encode7seg({4'b0, ledout[3:0]}), addr_strobe};
  else {en1, en2, a,b,c,d,e,f,g, dp} <= {1'b1,1'b0,encode7seg({4'b0, ledout[7:4]}), scan_cycle_clk};
end

  function [6:0]encode7seg(input [7:0]chr);
    case(chr)
	          8'h0: encode7seg = 7'b1111110;
	          8'h1: encode7seg = 7'b0110000;
	          8'h2: encode7seg = 7'b1101101;
	          8'h3: encode7seg = 7'b1111001;
	          8'h4: encode7seg = 7'b0110011;
	          8'h5: encode7seg = 7'b1011011;
	          8'h6: encode7seg = 7'b1011111;
	          8'h7: encode7seg = 7'b1110000;
	          8'h8: encode7seg = 7'b1111111;
	          8'h9: encode7seg = 7'b1111011;
	          8'ha: encode7seg = 7'b1110111;
	          8'hb: encode7seg = 7'b0011111;
	          8'hc: encode7seg = 7'b1001110;
	          8'hd: encode7seg = 7'b0111101;
	          8'he: encode7seg = 7'b1001111;
	          8'hf: encode7seg = 7'b1000111;
          default: encode7seg = 7'h00;
    endcase
  endfunction
endmodule
