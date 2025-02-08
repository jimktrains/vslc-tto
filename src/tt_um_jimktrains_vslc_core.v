/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc_core(
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n,
  input  wire [7:0] spi_clk_div,
  input  wire [7:0] timer_clk_div,
  output wire [7:0] ledout,
  output wire addr_strobe
);
assign ledout = eeprom_read_buf;
assign addr_strobe = eeprom_read_ready;

  function [7:0]encode7seg(input [7:0]chr);
    case(chr)
          "A": encode7seg = 8'b00001000;
          "B": encode7seg = 8'b00000011;
          "C": encode7seg = 8'b01000110;
          "D": encode7seg = 8'b00100001;
          "E": encode7seg = 8'b00000110;
          "F": encode7seg = 8'b00001110;
          "G": encode7seg = 8'b01000010;
          "H": encode7seg = 8'b00001011;
          "I": encode7seg = 8'b01001111;
          "J": encode7seg = 8'b01100001;
          "K": encode7seg = 8'b00001010;
          "L": encode7seg = 8'b01000111;
          "M": encode7seg = 8'b01101010;
          "N": encode7seg = 8'b01001000;
          "O": encode7seg = 8'b01000000;
          "P": encode7seg = 8'b00001100;
          "Q": encode7seg = 8'b00011000;
          "R": encode7seg = 8'b01001100;
          "S": encode7seg = 8'b00010010;
          "T": encode7seg = 8'b00000111;
          "U": encode7seg = 8'b01000001;
          "V": encode7seg = 8'b01010001;
          "W": encode7seg = 8'b01010101;
          "X": encode7seg = 8'b00001001;
          "Y": encode7seg = 8'b00010001;
          "Z": encode7seg = 8'b00110100;
          "0": encode7seg = 8'b01000000;
          "1": encode7seg = 8'b01111001;
          "2": encode7seg = 8'b00100100;
          "3": encode7seg = 8'b00110000;
          "4": encode7seg = 8'b00011001;
          "5": encode7seg = 8'b00010010;
          "6": encode7seg = 8'b00000010;
          "7": encode7seg = 8'b01111000;
          "8": encode7seg = 8'b00000000;
          "9": encode7seg = 8'b00010000;
          default: encode7seg = 8'hff;
    endcase
  endfunction

  wire instr_ready;
  wire [15:0]stack;

  wire [7:0] eeprom_read_buf;
  wire [15:0] eeprom_addr_read;
  wire eeprom_read_ready;

  reg eeprom_restart_read;

  wire ecsn;
  assign uio_out[EEPROM_CS] = ecsn;
  wire [3:0]bit_counter;

  reg rst_n_sync_reg;
  wire rst_n_sync;
  assign rst_n_sync = rst_n_sync_reg;

  reg eeprom_hold_n;
  wire eeprom_hold_n_w;
  assign eeprom_hold_n_w = eeprom_hold_n;

  reg [31:0] counter;
  wire spi_clk = spi_clk_div == 0 ? clk : counter[spi_clk_div-1];
  wire timer_clk = timer_clk_div == 0 ? clk : counter[timer_clk_div-1];
  wire eeprom_rw;

  tt_um_jimktrains_vslc_eeprom_reader eereader(
    spi_clk,
    rst_n_sync,
    eeprom_restart_read,
    eeprom_start_addr,
    eeprom_hold_n_w,
    cipo,
    copi,
    ecsn,
    eeprom_rw,
    eeprom_read_ready,
    eeprom_read_buf,
    eeprom_addr_read,
    bit_counter
  );


  tt_um_jimktrains_vslc_executor exec(
    clk,
    timer_clk,
    instr_ready,
    rst_n_sync,
    eeprom_read_buf,
    ui_in_reg,
    ui_in_prev_reg,
    TIMER_OUTPUT,
    uo_out,
    stack
  );


  wire _unused = ena;

  // uio_out
  localparam SPI_SD                = 3'h0;
  localparam EEPROM_HOLD           = 3'h1;
  localparam EEPROM_CS             = 3'h2;
  localparam STACK_OUT             = 3'h3;
  localparam SPI_CLK            = 3'h4;
  localparam SCAN_CYCLE_OUT        = 3'h5;
  localparam INTF_STROBE           = 3'h6;
  localparam SCAN_CYCLE_TRIGGER_IN = 3'h7;

  // uo_out
  localparam TIMER_OUTPUT          = 3'h7;

  wire copi;
  wire cipo;
  wire scan_cycle_trigger_in;

  assign uio_oe[SPI_SD]  = eeprom_rw;
  assign uio_oe[EEPROM_HOLD] = 1;
  assign uio_oe[EEPROM_CS] = 1;
  assign uio_oe[STACK_OUT]  = 1;
  assign uio_oe[SPI_CLK]  = 1;
  assign uio_oe[SCAN_CYCLE_OUT] = 1;
  assign uio_oe[INTF_STROBE] = 1;
  assign uio_oe[SCAN_CYCLE_TRIGGER_IN]  = 0;

  assign cipo = uio_in[SPI_SD];
  assign uio_out[SPI_SD] = copi;
  assign uio_out[EEPROM_HOLD] = eeprom_hold_n;
  wire [3:0]stack_out_bit_idx;
  assign stack_out_bit_idx = {4'h7 - (4'h7 & bit_counter)};
  wire stack_out_bit;
  assign stack_out_bit = stack[stack_out_bit_idx];
  assign uio_out[STACK_OUT] = stack_out_bit;
  assign uio_out[SPI_CLK]  = spi_clk;
  assign uio_out[SCAN_CYCLE_OUT]  = scan_cycle_clk;
  assign uio_out[INTF_STROBE]  = stack[0];
  assign uio_out[SCAN_CYCLE_TRIGGER_IN]  = 0;
  assign scan_cycle_trigger_in = uio_in[SCAN_CYCLE_TRIGGER_IN];

  reg [7:0]ui_in_reg;
  reg [7:0]ui_in_prev_reg;


  // reg [7:1]instr_buf;
  // wire [7:0]instr = {instr_buf, cipo};

  reg [9:0]start_addr;
  wire [15:0] eeprom_start_addr = {6'b0, start_addr};
  reg [9:0]end_addr;

  wire auto_scan_cycle;
  assign auto_scan_cycle = eeprom_restart_read;

  reg scan_cycle_trigger_in_reg;
  wire scan_cycle_clk;
  assign scan_cycle_clk = auto_scan_cycle || scan_cycle_trigger_in_reg;

  assign instr_ready = eeprom_read_ready && (eeprom_addr_read > 3);

  always @(posedge clk) begin
    scan_cycle_trigger_in_reg <= scan_cycle_trigger_in;
    if (!rst_n_sync) begin
      counter <= 0;
    end else begin
      counter <= rst_n_sync ? counter + 1 : 0;
    end
  end
  always @(negedge clk) begin
    rst_n_sync_reg <= rst_n;
    if (!rst_n_sync) begin
      start_addr <= 0;
      end_addr <= 0;
      eeprom_restart_read <= 0;
      eeprom_hold_n <= 1;
    end else begin
      if (eeprom_read_ready) begin
        start_addr[9:8] <= (eeprom_addr_read == 0) ? eeprom_read_buf[1:0] : start_addr[9:8];
        start_addr[7:0] <= (eeprom_addr_read == 1) ? eeprom_read_buf : start_addr[7:0];
        end_addr[9:8] <= (eeprom_addr_read == 2) ? eeprom_read_buf[1:0] : end_addr[9:8];
        end_addr[7:0] <= (eeprom_addr_read == 3) ? eeprom_read_buf : end_addr[7:0];

        eeprom_restart_read <= end_addr != 10'b0 && eeprom_addr_read >= {6'b0, end_addr};
      end
    end
  end

  always @(posedge scan_cycle_clk) begin
    if (!rst_n_sync) begin
      ui_in_reg <= ui_in;
      ui_in_prev_reg <= ui_in;
    end else begin
      ui_in_reg <= ui_in;
      ui_in_prev_reg <= ui_in_reg;
    end
  end
endmodule
