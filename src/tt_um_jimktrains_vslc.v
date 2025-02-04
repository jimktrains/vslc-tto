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
  wire instr_ready;
  wire [15:0]stack;
  assign instr_ready = (!rst_n && clk) || (cycle == CYCLE_EEPROM_READ && read_cycle_counter == 0);

  executor exec(
    clk,
    instr_ready,
    rst_n,
    instr,
    ui_in_reg,
    ui_in_prev_reg,
    TIMER_OUTPUT,
    uo_out,
    stack
  );
  wire _unused = ena;

  localparam SPI_COPI              = 3'h0;
  localparam SPI_CIPO              = 3'h1;
  localparam EEPROM_CS             = 3'h2;
  localparam STACK_OUT             = 3'h3;
  localparam IO_OUT_4              = 3'h4;
  localparam IO_OUT_5              = 3'h5;
  localparam TOS_OUT               = 3'h6;
  localparam SCAN_CYCLE_TRIGGER_IN = 3'h7;
  localparam TIMER_OUTPUT          = 3'h7;

  reg copi;
  wire cipo;
  wire eeprom_reset;
  wire scan_cycle_trigger_in;

  assign eeprom_reset = cycle == CYCLE_EEPROM_RESET;

  assign uio_oe[SPI_COPI]  = 1;
  assign uio_oe[SPI_CIPO]  = 0;
  assign uio_oe[EEPROM_CS] = 1;
  assign uio_oe[STACK_OUT]  = 1;
  assign uio_oe[IO_OUT_4]  = 0;
  assign uio_oe[IO_OUT_5]  = 0;
  assign uio_oe[TOS_OUT] = 1;
  assign uio_oe[SCAN_CYCLE_TRIGGER_IN]  = 0;

  assign cipo = uio_in[SPI_CIPO];
  assign uio_out[SPI_COPI] = copi;
  assign uio_out[SPI_CIPO] = 0;
  assign uio_out[EEPROM_CS] = eeprom_reset;
  assign uio_out[STACK_OUT] = stack[{1'b0, 3'h7 - (cycle_counter + 3'h1)}];
  assign uio_out[IO_OUT_4]  = 0;
  assign uio_out[IO_OUT_5]  = 0;
  assign uio_out[TOS_OUT]  = stack[0];
  assign uio_out[SCAN_CYCLE_TRIGGER_IN]  = 0;
  assign scan_cycle_trigger_in = uio_in[SCAN_CYCLE_TRIGGER_IN];

  reg [7:0]ui_in_reg;
  reg [7:0]ui_in_prev_reg;


  reg [7:0]instr;
  // reg [7:1]instr_buf;
  // wire [7:0]instr = {instr_buf, cipo};

  localparam CYCLE_EEPROM_RESET = 4'h0;
  localparam CYCLE_EEPROM_SEND_READ = 4'h1;
  localparam CYCLE_EEPROM_SEND_ADDRH = 4'h2;
  localparam CYCLE_EEPROM_SEND_ADDRL = 4'h3;
  localparam CYCLE_EEPROM_READ_VECTH = 4'h4;
  localparam CYCLE_EEPROM_READ_VECTL = 4'h5;
  localparam CYCLE_EEPROM_READ_ENDH = 4'h6;
  localparam CYCLE_EEPROM_READ_ENDL = 4'h7;
  localparam CYCLE_EEPROM_READ = 4'h8;

  reg [3:0]cycle;
  reg [2:0]cycle_counter;
  wire [2:0]read_cycle_counter;
  assign read_cycle_counter = cycle_counter + 1;


  localparam EEPROM_READ_INSTR = 8'b00000011;

  reg [9:0]start_addr;
  reg [9:0]end_addr;
  reg [9:0]cur_addr;

  wire [7:0]start_addr_h;
  wire [7:0]start_addr_l;
  assign start_addr_h = {6'b0, start_addr[9:8]};
  assign start_addr_l = start_addr[7:0];

  reg auto_scan_cycle;
  wire scan_cycle_clk = auto_scan_cycle || scan_cycle_trigger_in;

  always @(negedge clk) begin
    if (!rst_n) begin
      cycle_counter <= 7;
      start_addr <= 0;
      end_addr <= 0;
      cur_addr <= 0;
      copi <= 0;
      cycle <= CYCLE_EEPROM_RESET;
    end else begin

      copi <= (cycle == CYCLE_EEPROM_RESET) ? EEPROM_READ_INSTR[7] : (
              (cycle == CYCLE_EEPROM_SEND_READ) ? EEPROM_READ_INSTR[cycle_counter] : (
              (cycle == CYCLE_EEPROM_SEND_ADDRH ? start_addr_h[cycle_counter] :
              (cycle == CYCLE_EEPROM_SEND_ADDRL ? start_addr_l[cycle_counter] : 0))));

      cycle_counter <= (cycle == CYCLE_EEPROM_RESET) ? 6 : (cycle_counter - 1);

      casez ({cycle, read_cycle_counter})
        {CYCLE_EEPROM_RESET, 3'b?}: cycle <= CYCLE_EEPROM_SEND_READ;
        {CYCLE_EEPROM_SEND_READ, 3'b0}: cycle <= CYCLE_EEPROM_SEND_ADDRH;
        {CYCLE_EEPROM_SEND_ADDRH, 3'b0}: cycle <= CYCLE_EEPROM_SEND_ADDRL;
        {CYCLE_EEPROM_SEND_ADDRL, 3'b0}: cycle <= (start_addr == 0) ? CYCLE_EEPROM_READ_VECTH : CYCLE_EEPROM_READ ;
        {CYCLE_EEPROM_READ_VECTH, 3'b0}: cycle <= CYCLE_EEPROM_READ_VECTL;
        {CYCLE_EEPROM_READ_VECTL, 3'b0}: cycle <= CYCLE_EEPROM_READ_ENDH;
        {CYCLE_EEPROM_READ_ENDH, 3'b0}: cycle <= CYCLE_EEPROM_READ_ENDL;
        {CYCLE_EEPROM_READ_ENDL, 3'b0}: cycle <= CYCLE_EEPROM_READ;
        {CYCLE_EEPROM_READ, 3'b0}: cycle <= (cur_addr >= end_addr && cur_addr != 0) ?  CYCLE_EEPROM_RESET : CYCLE_EEPROM_READ;
        default: cycle <= cycle;
      endcase

      auto_scan_cycle <= cycle == CYCLE_EEPROM_RESET;

      cur_addr <= ((cycle == CYCLE_EEPROM_RESET) ||
      (cycle == CYCLE_EEPROM_SEND_READ) ||
      (cycle == CYCLE_EEPROM_SEND_ADDRH) ||
      (cycle == CYCLE_EEPROM_SEND_ADDRL) ||
        (read_cycle_counter != 0)) ? cur_addr : cur_addr + 1;

      if (read_cycle_counter == 0) begin
        if (cycle == CYCLE_EEPROM_READ_VECTH) begin
          start_addr[9:8] <= instr[1:0];
        end else if (cycle == CYCLE_EEPROM_READ_VECTL) begin
          start_addr[7:0] <= instr[7:0];
        end else if (cycle == CYCLE_EEPROM_READ_ENDH) begin
          end_addr[9:8] <= instr[1:0];
        end else if (cycle == CYCLE_EEPROM_READ_ENDL) begin
          end_addr[7:0] <= instr;
        end
      end
    end
  end

  always @(posedge scan_cycle_clk) begin
    if (!rst_n) begin
      ui_in_reg <= ui_in;
      ui_in_prev_reg <= ui_in;
    end else begin
      ui_in_reg <= ui_in;
      ui_in_prev_reg <= ui_in_reg;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      instr <= 0;

    end else begin
      instr[read_cycle_counter] <= cipo;
    end
  end
endmodule

module executor(
  input clk,
  input instr_ready,
  input rst_n,
  input [7:0] instr,
  input [7:0]ui_in,
  input [7:0]ui_in_prev,
  input [2:0]timer_reg,
  output [7:0]uo_out,
  output [15:0] stack_o
);
  reg [3:0] timer_clock_divisor;
  reg [9:0] timer_period_a;
  reg [9:0] timer_period_b;
  wire timer_enabled;
  wire timer_output;

  timer tim0(
    clk,
    rst_n,
    timer_clock_divisor,
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
      timer_clock_divisor <= 0;
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
  input [3:0] timer_clock_divisor,
  input [9:0] timer_period_a,
  input [9:0] timer_period_b,
  input timer_set,
  input timer_reset,
  output timer_enabled,
  output timer_output
);
  reg [9:0] timer_clock_counter;
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
      timer_clock_counter <= 0;
      timer_counter <= 0;
    end else begin
      timer_set_prev <= timer_set;
      timer_reset_prev <= timer_reset;
      timer_enabled_r <= timer_should_set || (timer_enabled_r && !timer_should_reset);

      if (timer_enabled) begin
        if (timer_clock_counter[timer_clock_divisor] == 1'b1) begin
          timer_clock_counter <= 0;
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
          timer_clock_counter <= timer_clock_counter + 1;
        end
      end else begin
        timer_clock_counter <= 10'b0;
        timer_counter <= 10'b0;
        timer_phase <= 1'b0;
        timer_output_r <= 1'b0;
      end
    end
  end
endmodule
