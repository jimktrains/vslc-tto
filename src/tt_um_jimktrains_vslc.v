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

  reg [7:0] uo_out_reg = 0;
  assign uo_out = uo_out_reg;

  reg [7:0] uio_out_reg = 0;
  assign uio_out = uio_out_reg;

  reg [7:0] uio_oe_reg = 0;
  assign uio_oe = uio_oe_reg;

  function get_input;
    input [3:0] id;
    begin
      if(id > 7) get_input = uio_in[id[2:0]];
      else get_input = ui_in[id[2:0]];
    end
  endfunction
  task set_output;
    input [3:0] id;
    input val;
    begin
      if(id > 7) uio_out_reg[id[2:0]] <= val;
      else uo_out_reg[id[2:0]] <= val;
    end
  endtask
  task toggle_output;
    input [3:0] id;
    begin
      if(id > 7) uio_out_reg[id[2:0]] <= ~uio_out_reg[id[2:0]];
      else uo_out_reg[id[2:0]] <= ~uo_out_reg[id[2:0]];
    end
  endtask

  reg [5:0]code_addr = 0;
  reg [3:0]codemem[0:32];

  // List all unused inputs to prevent warnings
  wire _unused = ena;

  reg [1:0]state = 0;
  reg [3:0]instr = 0;
  reg [31:0]stack = 0;

  reg [3:0] timer_clock_divisor = 1;
  reg [15:0] timer_clock = 0;
  reg [15:0] timer_counter = 0;
  reg [15:0] timer_period_a = 1;
  reg [15:0] timer_period_b = 2;
  reg [3:0] timer_ouput = 15;
  reg timer_phase = 0;
  reg timer_mode = 0;
  reg timer_enabled = 1;

  localparam INSTR_PUSH = 0;
  localparam INSTR_POP = 1;
  localparam INSTR_SET = 2;
  localparam INSTR_RESET = 3;
  localparam INSTR_SETUP_REG = 4;
  localparam INSTR_SETUP_CLOCK = 5;
  localparam INSTR_SET_TIMER = 6;
  localparam INSTR_RESET_TIMER = 7;


  localparam INSTR_NOT = 8;
  localparam INSTR_AND = 9;
  localparam INSTR_OR = 10;
  localparam INSTR_XOR = 11;
  localparam INSTR_IMPL = 12;
  localparam INSTR_BIMP = 13;
  localparam INSTR_NAND = 14;
  localparam INSTR_NOP = 15;

  localparam TIMER_MODE_CYCLE = 0;
  localparam TIMER_MODE_ONESHOT = 1;

  reg in_reset=0;
  always @(posedge clk) begin
    if(!rst_n) begin
      if(!in_reset) begin
        in_reset <= 1;
        uio_out_reg <= 0;
        uio_oe_reg <= 0;
        uo_out_reg <= 0;
        code_addr <= 0;
        state <=0;
      end
      else begin
        codemem[code_addr] <= ui_in[3:0];
        code_addr <= code_addr + 1;
      end
    end else if (in_reset & rst_n) begin
      in_reset <= 0;
      code_addr <= 0;
      stack <= 0;
      state <=0;
    end else begin
      if(timer_enabled == 1) begin
        uio_oe_reg[timer_ouput[2:0]] <= 1;
        // The right-shift feels like a huge hack due to me not fully
        // groking the clocking semantics.
        if(timer_clock < ((16'd1 << timer_clock_divisor) >> 1)) begin
          timer_clock <= timer_clock + 1;
        end
        else begin
          timer_clock <= 0;
          timer_counter <= timer_counter + 1;
          if(timer_phase == 0) begin
            if(timer_period_a == 0) begin
              timer_enabled <= 0;
              timer_counter <= 0;
              toggle_output(timer_ouput);
            // The minus 1 feels like a huge hack due to me not fully
            // groking the clocking semantics.
            end else if(timer_counter >= (timer_period_a - 1)) begin
              timer_phase <= 1;
              timer_counter <= 0;
              toggle_output(timer_ouput);
            end
          end
          else if(timer_phase == 1) begin
            if(timer_period_b == 0) begin
              timer_phase <= 0;
              timer_counter <= 0;
              if(timer_mode == TIMER_MODE_ONESHOT) timer_enabled <= 0;
            // The minus 1 feels like a huge hack due to me not fully
            // groking the clocking semantics.
            end else if(timer_counter >= (timer_period_b - 1)) begin
              timer_phase <= 0;
              timer_counter <= 0;
              if(timer_mode == TIMER_MODE_ONESHOT) timer_enabled <= 0;
              toggle_output(timer_ouput);
            end
          end
        end
      end
      if(state == 0) begin
        set_output(12, ~uio_out[0]);
        set_output(8, codemem[code_addr][0]);
        set_output(9, codemem[code_addr][1]);
        set_output(10, codemem[code_addr][2]);
        set_output(11, codemem[code_addr][3]);
        instr <= codemem[code_addr];
        if (codemem[code_addr] < INSTR_NOT) begin
          if(codemem[code_addr] == INSTR_PUSH) state <= 1;
          else if(codemem[code_addr] == INSTR_POP) state <= 1;
        end else begin
          if(codemem[code_addr] == INSTR_NOT) stack[0] <= ~stack[0];
          else if(codemem[code_addr] == INSTR_NOP) begin end
          else begin
            // If I `stack[1] = ...` in the ifs
            // and then `stack <= stack >> 1` at the end, this doesn't
            // work. I kind of sort of think I understand why, but I'm still
            // not 100% sure.
            if(codemem[code_addr] == INSTR_AND) stack[0] <= stack[0] & stack[1];
            else if(codemem[code_addr] == INSTR_OR) stack[0] <= stack[0] | stack[1];
            else if(codemem[code_addr] == INSTR_XOR) stack[0] <= stack[0] ^ stack[1];
            else if(codemem[code_addr] == INSTR_IMPL) stack[0] <= !stack[0] | stack[1];
            else if(codemem[code_addr] == INSTR_BIMP) stack[0] <= (stack[0] & stack[1]) | (!stack[0] & !stack[1]);
            else if(codemem[code_addr] == INSTR_NAND) stack[0] <= !(stack[0] & stack[1]);
            stack[30:1] <= stack[31:2];
          end
        end
      end
      else begin
        if (state == 1) begin
          state <= 0;
          if (codemem[code_addr] < 8) begin
            if(instr == INSTR_PUSH) begin
              stack <= stack << 1;
              stack[0] <= get_input(codemem[code_addr]);
            end else if(instr == INSTR_POP) begin
              set_output(codemem[code_addr], stack[0]);
              stack <= stack >> 1;
            end else if(instr == INSTR_SET) begin
              if(stack[0]) set_output(codemem[code_addr], 1);
              stack <= stack >> 1;
            end else if(instr == INSTR_RESET) begin
              if(stack[0]) set_output(codemem[code_addr], 0);
              stack <= stack >> 1;
            end
          end
        end
      end
      // If we are at the end of the code, then start a new cycle.
      if(code_addr == 31) stack <= 0;
      code_addr <= code_addr + 1;
    end
  end

endmodule
