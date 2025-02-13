/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc_core (
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n,
  output wire addr_strobe,
  output wire scan_cycle_clk_w
);
  assign addr_strobe = eeprom_read_ready;
  wire instr_ready;

  wire [7:0] eeprom_read_buf;
  wire [9:0] eeprom_addr_read;
  wire eeprom_read_ready;

  reg eeprom_restart_read;

  wire eeprom_cs_n;
  assign uio_out[EEPROM_CS] = eeprom_cs_n;
  wire [3:0]bit_counter;

  reg rst_n_sync_reg;
  wire rst_n_sync;
  assign rst_n_sync = rst_n_sync_reg;

  reg eeprom_hold_n;
  wire eeprom_hold_n_w;
  assign eeprom_hold_n_w = eeprom_hold_n;

  reg [3:0] spi_clk_div;
  reg [15:0] counter;

  // I think that this is frowned upon and actually creates multiple
  // clock domains. However, everything "below" this module uses this
  // as it's primary clock.
  //
  // The only exception is that counter is used to derive some other
  // internal clock strobes.
  wire spi_clk;
  assign spi_clk = spi_clk_div == 0 ? clk : counter[spi_clk_div-1];
  wire eeprom_rw;

  tt_um_jimktrains_vslc_eeprom_reader eereader(
    clk,
    spi_clk,
    rst_n_sync,
    eeprom_restart_read,
    eeprom_start_addr,
    eeprom_hold_n_w,
    cipo,
    copi,
    eeprom_cs_n,
    eeprom_rw,
    eeprom_read_ready,
    eeprom_read_buf,
    eeprom_addr_read,
    bit_counter
  );


  tt_um_jimktrains_vslc_executor exec(
    clk,
    counter,
    instr_ready,
    rst_n_sync,
    eeprom_read_buf,
    ui_in_reg_w,
    ui_in_prev_reg_w,
    uo_out
  );

  wire _unused = ena;

  // uio_out
  localparam SPI_SD                = 3'h0;
  localparam SPI_CLK               = 3'h1;
  localparam EEPROM_CS             = 3'h2;
  localparam STACK_OUT             = 3'h3;
  localparam TOS_OUT               = 3'h4;
  localparam SCAN_CYCLE_OUT        = 3'h5;
  localparam EEPROM_HOLD           = 3'h6;
  localparam SCAN_CYCLE_TRIGGER_IN = 3'h7;

  // uo_out
  localparam TIMER_OUTPUT          = 3'h7;

  wire copi;
  wire cipo;
  wire scan_cycle_trigger_in;

  assign uio_oe[SPI_SD]  = eeprom_rw;
  assign uio_oe[EEPROM_HOLD] = 1;
  assign uio_oe[EEPROM_CS] = 1;
  assign uio_oe[STACK_OUT]  = 0;
  assign uio_oe[SPI_CLK]  = 1;
  assign uio_oe[SCAN_CYCLE_OUT] = 1;
  assign uio_oe[TOS_OUT] = 0;
  assign uio_oe[SCAN_CYCLE_TRIGGER_IN]  = 0;

  assign cipo = uio_in[SPI_SD];
  assign uio_out[SPI_SD] = copi;
  assign uio_out[EEPROM_HOLD] = eeprom_hold_n;
  assign uio_out[STACK_OUT] = 1;
  assign uio_out[SPI_CLK]  = spi_clk;
  assign uio_out[SCAN_CYCLE_OUT]  = scan_cycle_clk;
  assign uio_out[TOS_OUT]  = 1;
  assign uio_out[SCAN_CYCLE_TRIGGER_IN]  = 0;
  assign scan_cycle_trigger_in = uio_in[SCAN_CYCLE_TRIGGER_IN];

  reg [7:0]ui_in_reg;
  reg [7:0]ui_in_prev_reg;

  wire [7:0]ui_in_reg_w;
  wire [7:0]ui_in_prev_reg_w;

  assign ui_in_reg_w = ui_in_reg;
  assign ui_in_prev_reg_w = ui_in_prev_reg;

  // reg [7:1]instr_buf;
  // wire [7:0]instr = {instr_buf, cipo};

  reg [9:0]start_addr;
  wire [9:0] eeprom_start_addr = start_addr;
  reg [9:0]end_addr;

  wire auto_scan_cycle;
  assign auto_scan_cycle = eeprom_restart_read;

  reg scan_cycle_trigger_in_reg;
  assign scan_cycle_clk_w = scan_cycle_clk;
  reg scan_cycle_clk;
  reg scan_cycle_clk_prev;

  assign instr_ready = eeprom_read_ready && (eeprom_addr_read > 3);

  always @(posedge clk) begin
    scan_cycle_trigger_in_reg <= scan_cycle_trigger_in;
    if (!rst_n_sync) begin
      counter <= 0;
      ui_in_reg <= ui_in;
      ui_in_prev_reg <= ui_in;
      scan_cycle_clk_prev <= 0;
      spi_clk_div <= 3;
      scan_cycle_clk <= 0;
    end else begin
      counter <= counter + 1;
      scan_cycle_clk <= auto_scan_cycle || scan_cycle_trigger_in_reg;
      scan_cycle_clk_prev <= scan_cycle_clk;
      if (scan_cycle_clk && !scan_cycle_clk_prev) begin
        ui_in_reg <= ui_in;
        ui_in_prev_reg <= ui_in_reg;
      end
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

        eeprom_restart_read <= end_addr != 10'b0 && eeprom_addr_read >= end_addr;
      end else begin
        eeprom_restart_read <= eeprom_restart_read;
      end

    end
  end
endmodule
