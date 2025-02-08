/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc_executor(
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


  tt_um_jimktrains_vslc_timer tim0(
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
