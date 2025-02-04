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

  localparam SPI_COPI    = 0;
  localparam SPI_CIPO    = 1;
  localparam EEPROM_CS   = 2;
  localparam STACK_OUT   = 3;
  localparam IO_OUT_4    = 4;
  localparam IO_OUT_5    = 5;
  localparam TOS_OUT     = 6;
  localparam SCAN_CYCLE_TRIGGER_IN    = 7;
  localparam TIMER_OUTPUT = 7;

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
  assign uio_out[TOS_OUT]  = tos;
  assign uio_out[SCAN_CYCLE_TRIGGER_IN]  = 0;
  assign scan_cycle_trigger_in = uio_in[SCAN_CYCLE_TRIGGER_IN];

  reg [7:0]ui_in_reg;
  reg [7:0]ui_in_prev_reg;
  reg [7:0]uo_out_reg;

  assign uo_out = uo_out_reg;


  reg timer_enabled;

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

  reg [15:0]stack;
  wire tos = stack[0];
  wire nos = stack[1];
  wire hos = stack[2];

  wire instr_reg_a = instr[7:6] == 0;
  wire instr_reg_b = instr[7:6] == 1;
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
  wire push_result = ioreg ? uo_out_reg[regid] : ui_in_reg[regid];

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
  wire temporal_result = (ui_in_reg[regid] == ~expected_prev_state) &&
                         (ui_in_prev_reg[regid] == expected_prev_state);

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
      uo_out_reg <= 0;
      timer_reset();
      stack <= 16'b0;
      copi <= 0;
      cycle <= CYCLE_EEPROM_RESET;
    end else begin
      timer_update();

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

      if (timer_enabled) uo_out_reg[TIMER_OUTPUT] <= timer_output;

      if (read_cycle_counter == 0) begin
        if (cycle == CYCLE_EEPROM_READ_VECTH) begin
          start_addr[9:8] <= instr[1:0];
        end else if (cycle == CYCLE_EEPROM_READ_VECTL) begin
          start_addr[7:0] <= instr[7:0];
        end else if (cycle == CYCLE_EEPROM_READ_ENDH) begin
          end_addr[9:8] <= instr[1:0];
        end else if (cycle == CYCLE_EEPROM_READ_ENDL) begin
          end_addr[7:0] <= instr;
        end else if (cycle == CYCLE_EEPROM_READ) begin
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

          if (!(timer_enabled && regid == TIMER_OUTPUT)) begin
            uo_out_reg[regid] <= !instr_pop_type ? uo_out_reg[regid]: (
              instr_pop ? stack[0] : (
              !stack[0] ? uo_out_reg[regid] : (
              instr_set ? 1 : (
              instr_reset ? 0 : uo_out_reg[regid]))));
          end

          timer_enabled <= should_set_enable_timer ? 1 : (should_reset_enable_timer ? 0 : timer_enabled);
          // We need to manually reset the timer output because `timer_output`
          // isn't directly tied to the output because I wanted to be able
          // to read the timer's value as a register.
          if (timer_enabled && should_reset_enable_timer) uo_out_reg[TIMER_OUTPUT] <= 0;
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




  localparam TIMER_MODE_CYCLE = 0;
  localparam TIMER_MODE_ONESHOT = 1;

  reg [3:0] timer_clock_divisor;
  reg [9:0] timer_clock_counter;
  reg [9:0] timer_counter;
  reg [9:0] timer_period_a;
  reg [9:0] timer_period_b;
  reg timer_phase;
  reg timer_mode;
  reg timer_output;

  task timer_update();
    begin
      if (timer_enabled) begin
        if (timer_clock_counter[timer_clock_divisor] == 1'b1) begin
          timer_clock_counter <= 0;
          if (timer_phase == 1'b0 && timer_counter == timer_period_a) begin
            timer_counter <= 10'b0;
            timer_phase <= 1'b1;
            timer_enabled <= timer_enabled;
            timer_output <= ~timer_output;
          end else if (timer_phase == 1'b1 && timer_counter == timer_period_b) begin
            timer_counter <= 10'b0;
            timer_phase <= 1'b0;
            timer_enabled <= timer_mode == TIMER_MODE_CYCLE;
            timer_output <= timer_period_b == 0 ? timer_output : ~timer_output;
          end else begin
            timer_counter <= timer_counter + 1;
            timer_phase <= timer_phase;
            timer_enabled <= timer_enabled;
            timer_output <= timer_output;
          end
        end else begin
          timer_phase <= timer_phase;
          timer_enabled <= timer_enabled;
          timer_counter <= timer_counter;
          timer_clock_counter <= timer_clock_counter + 1;
          timer_output <= timer_output;
        end
      end else begin
        timer_reset();
      end
    end
  endtask

  task timer_reset();
    begin
      timer_clock_counter <= 10'b0;
      timer_clock_divisor <= 4'b0000;
      timer_counter <= 10'b0;
      timer_period_a <= 10'b1;
      timer_period_b <= 10'h2;
      timer_enabled <= 1'b0;
      timer_phase <= 1'b0;
      timer_mode <= 1'b0;
      timer_output <= 1'b0;
    end
  endtask

endmodule
