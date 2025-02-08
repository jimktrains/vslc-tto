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
  function [7:0]encode7seg(input [7:0]c);
    case(c)
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

  reg [9:0] counter;
  wire [3:0] spi_clk_div;
  wire [3:0] timer_clock_divisor;
  assign spi_clk_div = 2;
  assign timer_clock_divisor = 0;
  wire spi_clk = clk && spi_clk_div == 0 ? clk : counter[spi_clk_div-1];
  wire timer_clk = timer_clock_divisor == 0 ? clk : counter[timer_clock_divisor-1];
  wire eeprom_rw;

  eeprom_reader eereader(
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


  executor exec(
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
    counter <= rst_n_sync ? counter + 1 : 0;
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

module eeprom_reader(
  input clk,
  input rst_n,
  input goto_address,
  input [15:0]address,
  input hold_n,
  input cipo,
  output copi,
  output chip_select_n,
  output rw,
  output read_ready,
  output [7:0]byte_read,
  output [15:0]address_read,
  output [3:0]bitc
);
  reg goto_addr_prev;
  reg [3:0]bit_counter;
  reg [7:0]read_buf;

  assign bitc = bit_counter;

  assign byte_read = read_buf;
  assign read_ready = bit_counter == 0 && comm_state == COMM_READ;
  reg [15:0]address_reading;

  assign address_read = address_reading;

  assign copi = comm_state == COMM_INSTR ? EEPROM_READ_INSTR[bit_counter[2:0]] : address[bit_counter];
  assign chip_select_n = comm_state == COMM_RESET;

  localparam EEPROM_READ_INSTR = 8'b00000011;

  reg [2:0]comm_state;
  localparam COMM_RESET = 3'h0;
  localparam COMM_INSTR = 3'h1;
  localparam COMM_ADDR  = 3'h2;
  localparam COMM_READ  = 3'h3;

  assign rw = comm_state != COMM_READ;

  always @(negedge clk) begin
    if (!rst_n) begin
      comm_state <= COMM_RESET;
      goto_addr_prev <= 0;
      bit_counter <= 7;
    end else if (hold_n) begin
      if (!goto_addr_prev && goto_address) {comm_state, bit_counter} <= {COMM_RESET, 4'h7};
      else
        casez ({comm_state, bit_counter})
          {COMM_RESET, 4'b?}: {comm_state, bit_counter} <= {COMM_INSTR, 4'h7};
          {COMM_INSTR, 4'b0}: {comm_state, bit_counter} <= {COMM_ADDR, 4'hF};
          {COMM_ADDR, 4'b0}: {comm_state, bit_counter} <= {COMM_READ, 4'h7};
          {COMM_READ, 4'b0}: {comm_state, bit_counter} <= {COMM_READ, 4'h7};
          default: {comm_state, bit_counter}  <= {comm_state, bit_counter - 4'b1};
        endcase

      goto_addr_prev <= goto_address;
    end
  end
  always @(posedge clk) begin
    if (!rst_n) begin
      read_buf <= 0;
      address_reading <= address;
    end else if (hold_n) begin
      if (comm_state == COMM_RESET) read_buf <= 0;
      else read_buf[bit_counter[2:0]] <= cipo;

      address_reading <= (comm_state == COMM_READ && bit_counter == 7) ? address_reading + 1 : (
                         comm_state == COMM_ADDR ? address - 1 : (
                         address_reading));
    end
  end
endmodule

module executor(
  input timer_clk,
  input clk,
  input instr_ready,
  input rst_n,
  input [7:0] instr,
  input [7:0] ui_in,
  input [7:0] ui_in_prev,
  input [2:0] timer_reg,
  output [7:0] uo_out,
  output [15:0] stack_o
);
  reg [9:0] timer_period_a;
  reg [9:0] timer_period_b;
  wire timer_enabled;
  wire timer_output;


  timer tim0(
    timer_clk,
    rst_n,
    timer_period_a,
    timer_period_b,
    timer_set,
    timer_reset,
    timer_enabled,
    timer_output
  );

  reg [15:0]stack;
  reg [7:0]uo_out_reg;
  reg timer_set;
  reg timer_reset;
  assign stack_o = stack;
  assign uo_out = uo_out_reg;
  wire tos = stack[0];
  wire nos = stack[1];
  wire hos = stack[2];

  wire instr_reg_a = instr[7:6] == 0;
  // wire instr_reg_b = instr[7:6] == 1;
  wire instr_logic = instr[7:6] == 2;
  wire instr_other = instr[7:6] == 3;

  wire [2:0]regid = instr[2:0];
  wire instr_push = instr_reg_a && instr[5:4] == 0;
  wire ioreg = instr[3] && instr_push;
  wire instr_pop = instr_reg_a && instr[5:4] == 1;
  wire instr_set = instr_reg_a && instr[5:4] == 2;
  wire instr_reset = instr_reg_a && instr[5:4] == 3;
  wire instr_push_type = instr_push;
  wire instr_pop_type = (instr_pop || instr_set || instr_reset);
  wire toreg = instr[3] && instr_pop_type;
  wire push_result = ioreg ? uo_out[regid] : ui_in[regid];

  // Every logic operation conceptually pops once or twice, or we pop none
  // for pushing constant data only.
  // However, since we then push  two results only if we've popped twice or
  // otherwise once, we only need to shift the stack right zero
  // or one times. For pushing constant data we need to be able to shift
  // left once.
  // wire shift_none    = instr_logic && instr[5:4] == 0;
  wire shift_right_1 = (instr_logic && instr[5:4] == 1) || instr_pop_type;
  wire shift_left_1  = (instr_logic && instr[5:4] == 3) || instr_push_type;

  wire [3:0]logic_table = instr[3:0];
  wire logic_result = logic_table[2'b11 - {nos, tos}];
  // I'm curious if this uses fewer gates than the above.
  //wire logic_result = (instr[0] &  nos &  tos) |
  //                    (instr[1] &  nos & ~tos) |
  //                    (instr[2] & ~nos &  tos) |
  //                    (instr[3] & ~nos & ~tos);

  wire instr_stack = (instr_other && instr[5:4] == 2'b11);
  wire instr_temporal = (instr_other && instr[5:4] == 2'b10);
  wire instr_swap = instr_stack && (logic_table == 4'b0010);
  wire instr_rot = instr_stack && (logic_table == 4'b0011);
  wire instr_clr = instr_stack && (logic_table == 4'b0000);
  wire instr_setall = instr_stack && (logic_table == 4'b0001);

  wire has_1_result = instr_logic || instr_push_type || instr_temporal || has_2_result;
  wire has_2_result = instr_swap || has_3_result;
  wire has_3_result = instr_rot;

  wire expected_prev_state = instr[3];
  wire temporal_result = (ui_in[regid] == ~expected_prev_state) &&
                         (ui_in_prev[regid] == expected_prev_state);

  wire res2 = (instr_rot && tos);
  wire res1 = (instr_swap && tos) ||
              (instr_rot && hos);
  wire res0 = (instr_logic && logic_result) ||
              (instr_push_type && push_result) ||
              (instr_swap && nos) ||
              (instr_rot && nos) ||
              (instr_temporal && temporal_result);

  wire should_set_enable_timer = (instr_pop_type && toreg == 0 && tos && (instr_pop || instr_set));
  wire should_reset_enable_timer = (instr_pop_type && toreg == 0 && ((!tos && instr_pop) || (tos && instr_reset)));

  always @(negedge clk) begin
    if (!rst_n) begin
      stack <= 16'b0;
      uo_out_reg <= 8'b0;
      timer_set <= 1'b0;
      timer_reset <= 1'b1;
      timer_period_a <= 2;
      timer_period_b <= 3;
    end else if (instr_ready) begin
          stack[15] <= instr_clr ? 0 : (
                       instr_setall ? 1 : (
                       shift_left_1 ? stack[14] : (
                       shift_right_1 ? 0 : stack[15])));
          stack[14:3] <= instr_clr ? 12'b0 : (
                         instr_setall ? 12'hFFF : (
                         shift_left_1 ? stack[13:2] : (
                         shift_right_1 ? stack[15:4] : stack[14:3])));
          stack[2] <= instr_clr ? 0 : (
                      instr_setall ? 1 : (
                      has_3_result ? res2 : (
                      shift_left_1 ? stack[1] : (
                      shift_right_1 ? stack[3] : stack[2]))));
          stack[1] <= instr_clr ? 0 : (
                      instr_setall ? 1 : (
                      has_2_result ? res1 : (
                      shift_left_1 ? stack[0] : (
                      shift_right_1 ? stack[2] : stack[1]))));
          stack[0] <= instr_clr ? 0 : (
                      instr_setall ? 1 : (
                      has_1_result ? res0 : (
                      shift_left_1 ? 0 : (
                      shift_right_1 ? stack[1] : stack[0]))));

          if (!(timer_enabled && regid == timer_reg)) begin
            uo_out_reg[regid] <= !instr_pop_type ? uo_out_reg[regid]: (
              instr_pop ? stack[0] : (
              !stack[0] ? uo_out_reg[regid] : (
              instr_set ? 1 : (
              instr_reset ? 0 : uo_out_reg[regid]))));
          end

          timer_set <= should_set_enable_timer;
          timer_reset <= should_reset_enable_timer;

          // We need to manually reset the timer output because `timer_output`
          // isn't directly tied to the output because I wanted to be able
          // to read the timer's value as a register.
          uo_out_reg[timer_reg] <= should_reset_enable_timer ? 0 : (
                                   timer_enabled ? timer_output :
                                   uo_out_reg[timer_reg]);
        end else begin
          if (timer_enabled) uo_out_reg[timer_reg] <= timer_output;
        end
    end
endmodule

module timer(
  input clk,
  input rst_n,
  input [9:0] timer_period_a,
  input [9:0] timer_period_b,
  input timer_set,
  input timer_reset,
  output timer_enabled,
  output timer_output
);
  reg [9:0] timer_counter;
  reg timer_phase;
  reg timer_output_r;
  reg timer_set_prev;
  reg timer_reset_prev;
  reg timer_enabled_r;

  wire timer_should_set;
  wire timer_should_reset;

  assign timer_output = timer_output_r;
  assign timer_should_set = (timer_set && !timer_set_prev);
  assign timer_should_reset = (timer_reset && !timer_reset_prev);
  assign timer_enabled = timer_enabled_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      timer_enabled_r <= 0;
      timer_counter <= 0;
    end else begin
      timer_set_prev <= timer_set;
      timer_reset_prev <= timer_reset;
      timer_enabled_r <= timer_should_set || (timer_enabled_r && !timer_should_reset);

      if (timer_enabled) begin
          if (timer_phase == 1'b0 && timer_counter == timer_period_a) begin
            timer_counter <= 10'b0;
            timer_phase <= 1'b1;
            timer_output_r <= ~timer_output_r;
          end else if (timer_phase == 1'b1 && timer_counter == timer_period_b) begin
            timer_counter <= 10'b0;
            timer_phase <= 1'b0;
            timer_output_r <= timer_period_b == 0 ? timer_output : ~timer_output;
          end else begin
            timer_counter <= timer_counter + 1;
          end
      end else begin
        timer_phase <= 1'b0;
        timer_output_r <= 1'b0;
      end
    end
  end
endmodule
