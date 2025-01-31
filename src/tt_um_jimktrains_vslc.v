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


  localparam TIMER_MODE_CYCLE = 0;
  localparam TIMER_MODE_ONESHOT = 1;
  localparam TIMER_OUTPUT = 7;

  // https://ww1.microchip.com/downloads/en/DeviceDoc/22040A.pdf
  // SPI Serial EEPROM Family Data Sheet
  localparam EEPROM_READ_COMMAND = 8'b00000011;
  localparam EEPROM_SCK = 0;
  localparam EEPROM_CS = 1;
  localparam EEPROM_COPI = 2;
  localparam EEPROM_CIPO = 3;
  localparam STACK_OUT = 6;

  reg [3:0] fetch_prev_state = 4'b0;
  reg [3:0] fetch_state = 4'b0;
  reg [2:0] fetch_count = 3'b0;
  reg [7:0] cur_addr = 8'b0;

  reg [7:0] uo_out_reg = 8'b0;
  reg [7:0] uio_oe_reg = 8'b0;
  reg [7:0] uio_out_reg = 8'b0;
  reg [7:0] uio_in_reg = 8'b0;
  reg [7:0] ui_in_reg = 8'b0;


  // List all unused inputs to prevent warnings
  wire [8:0]_unused = {ena, eeprom_oe_copi, eeprom_oe_sck, eeprom_oe_cs, eeprom_copi, eeprom_cs, eeprom_sck, timer_out, stack_out};

  localparam FETCH_STATE_INIT = 4'h0;
  localparam FETCH_STATE_CS_EEPROM_HIGH = 4'h1;
  localparam FETCH_STATE_CYCLE_CS_EEPROM = 4'h2;
  localparam FETCH_STATE_CS_EEPROM = 4'h3;
  localparam FETCH_STATE_READ_INSTR = 4'h5;
  localparam FETCH_STATE_READ_PERIOD_A_BYTE2OF3 = 4'h6;
  localparam FETCH_STATE_READ_PERIOD_A_BYTE3OF3 = 4'h7;
  localparam FETCH_STATE_READ_PERIOD_B_BYTE2OF3 = 4'h8;
  localparam FETCH_STATE_READ_PERIOD_B_BYTE3OF3 = 4'h9;
  localparam FETCH_STATE_READ_PROG_LAST_ADDR = 4'hA;
  localparam FETCH_STATE_READ_RESET_VECTOR = 4'hB;
  localparam FETCH_STATE_SEND_ADDRESS = 4'hC;
  localparam FETCH_STATE_SEND_READ_CMD = 4'hD;

  localparam INSTR_PUSH_74     = 4'h0;
  localparam INSTR_POP_74      = 5'h1;
  localparam INSTR_SET_74      = 5'h2;
  localparam INSTR_RESET_74    = 5'h3;

  localparam INSTR_CLASS_STACK = 2'b00;
  localparam INSTR_CLASS_SETUP = 2'b01;
  localparam INSTR_CLASS_LOGIC = 2'b10;
  localparam INSTR_CLASS_OTHER = 2'b11;

  localparam INSTR_SETUP_PERIOD_A = 8'h70;
  localparam INSTR_SETUP_PERIOD_B = 8'h71;
  localparam INSTR_SETUP_CLOCKDIV_74 = 4'h4;
  localparam INSTR_SETUP_MODE_74 = 4'h5;

  localparam [3:0]INSTR_STACK_PUSH_73 = 4'b0000;
  localparam [3:0]INSTR_STACK_POP_73 = 4'b0001;
  localparam [3:0]INSTR_STACK_SET_73 = 4'b0010;
  localparam [3:0]INSTR_STACK_RESET_73 = 4'b0011;


  localparam INSTR_MSB = 7;

  reg [7:0]cycle_start_addr = 8'b0;
  reg [7:0]cycle_end_addr = 8'b0;
  reg [7:0]instr = 8'b0;
  wire [1:0]instr_class;
  wire [2:0]regid;
  wire [3:0]instr_clock_div;
  wire instr_timer_mode_bit;


  localparam STACK_MSB = 15;
  reg [STACK_MSB:0]stack = 16'b0;
  wire stack_out; assign stack_out = uio_out_reg[STACK_OUT];

  reg [15:0] timer_clock_counter = 16'b0;
  reg [3:0] timer_clock_divisor = 4'b0;
  reg [15:0] timer_counter = 16'b0;
  reg [15:0] timer_period_a = 16'b0;
  reg [15:0] timer_period_b = 16'b0;
  reg timer_enabled = 1'b0;
  reg timer_phase = 1'b0;
  reg timer_mode = 1'b0;

  assign uo_out[7:0] = uo_out_reg[7:0];
  assign uio_out[7:2] = uio_out_reg[7:2];
  assign uio_out[EEPROM_CS] = uio_out_reg[EEPROM_CS];
  assign uio_out[0] = clk & !uio_out_reg[EEPROM_CS];
  assign uio_oe[7:0] = uio_oe_reg[7:0];

  // Giving these names just makes it easier to find in the vcd.
  wire eeprom_cs; assign eeprom_cs = uio_out[EEPROM_CS];
  wire eeprom_sck; assign eeprom_sck = uio_out[EEPROM_SCK];
  wire eeprom_copi; assign eeprom_copi = uio_out[EEPROM_COPI];
  wire eeprom_oe_cs; assign eeprom_oe_cs = uio_oe_reg[EEPROM_CS];
  wire eeprom_oe_sck; assign eeprom_oe_sck = uio_oe_reg[EEPROM_SCK];
  wire eeprom_oe_copi; assign eeprom_oe_copi = uio_oe_reg[EEPROM_COPI];
  wire timer_out; assign timer_out = uio_out[TIMER_OUTPUT];

  assign instr_class[1:0] = instr[INSTR_MSB -: 2];
  assign instr_clock_div = instr[3:0];
  assign instr_timer_mode_bit = instr[0];

  assign regid = instr[INSTR_MSB-5 -:3];

  always @(*) begin
  end

  task timer_update();
    begin
      if (timer_enabled) begin
        if (timer_clock_counter[timer_clock_divisor] == 1'b1) begin
          timer_clock_counter <= 0;
          if (timer_phase == 1'b0 && timer_counter == timer_period_a) begin
            timer_counter <= 16'b0;
            timer_phase <= 1'b1;
            timer_enabled <= timer_enabled;
            uio_out_reg[TIMER_OUTPUT] <= ~uio_out_reg[TIMER_OUTPUT];
          end else if (timer_phase == 1'b1 && timer_counter == timer_period_b) begin
            timer_counter <= 16'b0;
            timer_phase <= 1'b0;
            uio_out_reg[TIMER_OUTPUT] <= timer_period_b == 0 ? uio_out_reg[TIMER_OUTPUT] : ~uio_out_reg[TIMER_OUTPUT];
            if (timer_mode == TIMER_MODE_ONESHOT) timer_reset();
          end else begin
            timer_phase <= timer_phase;
            timer_enabled <= timer_enabled;
            uio_out_reg[TIMER_OUTPUT] <= uio_out_reg[TIMER_OUTPUT];
            timer_counter <= timer_counter + 1;
          end
        end else begin
          timer_clock_counter <= timer_clock_counter + 1;
        end
      end else begin
        timer_reset();
      end
    end
  endtask

  task timer_reset();
    begin
      timer_clock_counter <= 16'b0;
      timer_clock_divisor <= 4'b0;
      timer_counter <= 16'b0;
      timer_period_a <= 16'b1;
      timer_period_b <= 16'h2;
      timer_enabled <= 1'b0;
      timer_phase <= 1'b0;
      uio_out_reg[TIMER_OUTPUT] <= 1'b0;
    end
  endtask

  task fetch_cycle_update();
    begin
      case (fetch_state)
        FETCH_STATE_INIT: begin
          fetch_state <= FETCH_STATE_CS_EEPROM_HIGH;
          fetch_prev_state <= fetch_state;
        end
        FETCH_STATE_CS_EEPROM_HIGH: begin
          fetch_state <= FETCH_STATE_CS_EEPROM;
          fetch_prev_state <= fetch_state;
        end
        FETCH_STATE_CS_EEPROM: begin
          fetch_state <= FETCH_STATE_SEND_READ_CMD;
          fetch_prev_state <= fetch_state;
        end
        default: begin
          if (fetch_count == 3'b0) begin
            fetch_prev_state <= fetch_state;
            case (fetch_state)
              FETCH_STATE_SEND_READ_CMD: fetch_state <= FETCH_STATE_SEND_ADDRESS;
              FETCH_STATE_SEND_ADDRESS: begin
                case (cycle_start_addr)
                  8'h00: fetch_state <= FETCH_STATE_READ_RESET_VECTOR;
                  default: fetch_state <= FETCH_STATE_READ_INSTR;
                endcase
              end
              FETCH_STATE_READ_RESET_VECTOR: fetch_state <= FETCH_STATE_READ_PROG_LAST_ADDR;
              FETCH_STATE_READ_PROG_LAST_ADDR: fetch_state <= FETCH_STATE_READ_INSTR;
              FETCH_STATE_READ_INSTR: begin
                if (cur_addr > cycle_end_addr) fetch_state <= FETCH_STATE_CS_EEPROM_HIGH;
                else if (cur_addr == 0) fetch_state <= FETCH_STATE_CS_EEPROM_HIGH; // wrapped address
                else if (instr == INSTR_SETUP_PERIOD_A) fetch_state <= FETCH_STATE_READ_PERIOD_A_BYTE2OF3;
                else if (instr == INSTR_SETUP_PERIOD_B) fetch_state <= FETCH_STATE_READ_PERIOD_B_BYTE2OF3;
                else fetch_state <= FETCH_STATE_READ_INSTR;
              end
              FETCH_STATE_READ_PERIOD_A_BYTE2OF3: fetch_state <= FETCH_STATE_READ_PERIOD_A_BYTE3OF3;
              FETCH_STATE_READ_PERIOD_A_BYTE3OF3: fetch_state <= FETCH_STATE_READ_INSTR;
              FETCH_STATE_READ_PERIOD_B_BYTE2OF3: fetch_state <= FETCH_STATE_READ_PERIOD_B_BYTE3OF3;
              FETCH_STATE_READ_PERIOD_B_BYTE3OF3: fetch_state <= FETCH_STATE_READ_INSTR;
              default: fetch_state <= FETCH_STATE_INIT;
            endcase
          end
        end
      endcase
    end
  endtask

  task fetch_cycle_execute();
    begin
      // We want to do this right at the end off our cycle;
      case (fetch_state)
        FETCH_STATE_CS_EEPROM_HIGH: begin
          uio_out_reg[EEPROM_CS] <= 1'b1;
        end
        FETCH_STATE_CS_EEPROM: begin
          uio_out_reg[EEPROM_CS] <= 1'b0;
        end
        default: begin end
      endcase
      // We want to do this right at the start of the next cycle as that's
      // we we have everything that was read.
      if (fetch_count == 3'h7) begin
        case (fetch_prev_state)
          FETCH_STATE_READ_RESET_VECTOR: cycle_start_addr <= instr;
          FETCH_STATE_READ_PROG_LAST_ADDR: cycle_end_addr <= instr;
          FETCH_STATE_READ_INSTR: begin
            case (instr_class)
              INSTR_CLASS_STACK: begin
                casez (instr[7:4])
                  INSTR_STACK_PUSH_73: begin
                    stack[STACK_MSB:1] <= stack[STACK_MSB-1:0];
                    if (instr[3] == 1'b0) stack[0] <= ui_in_reg[regid];
                    else if (instr[3] == 1'b1) stack[0] <= uo_out_reg[regid];
                  end
                  INSTR_STACK_POP_73: begin
                    stack[STACK_MSB-1:0] <= stack[STACK_MSB:1];
                    if (instr[3] == 1'b0) timer_enabled <= stack[0];
                    else if (instr[3] == 1'b1) uo_out_reg[regid] <= stack[0];
                  end
                  INSTR_STACK_SET_73: begin
                    stack[STACK_MSB-1:0] <= stack[STACK_MSB:1];
                    if (instr[3] == 1'b0) timer_enabled <= stack[0] ? 1 : timer_enabled;
                    else if (instr[3] == 1'b1) uo_out_reg[regid] <= stack[0] ? 1 : uo_out_reg[regid];
                  end
                  INSTR_STACK_RESET_73: begin
                    stack[STACK_MSB-1:0] <= stack[STACK_MSB:1];
                    if (instr[3] == 1'b0) timer_enabled <= stack[0] ? 0 : timer_enabled;
                    else if (instr[3] == 1'b1) uo_out_reg[regid] <= stack[0] ? 0 : uo_out_reg[regid];
                  end
                  default: begin end
                endcase
              end
              INSTR_CLASS_LOGIC: begin
                uo_out_reg[7:4] <= instr[3:0];
                if (instr[5:4]== 2) stack[STACK_MSB - 1: 1] <= stack[STACK_MSB:2];
                else if (instr[5:4]== 0) stack[STACK_MSB:1] <= stack[STACK_MSB - 1:0];
                stack[0] <= instr[3'h3 - stack[1:0]];
              end
              INSTR_CLASS_OTHER: begin end
              INSTR_CLASS_SETUP: begin
                case (instr[7:4])
                  INSTR_SETUP_CLOCKDIV_74: timer_clock_divisor <= instr_clock_div;
                  INSTR_SETUP_MODE_74: timer_mode <= instr_timer_mode_bit;
                  default: begin end
                endcase
              end
            endcase
          end
          FETCH_STATE_READ_PERIOD_A_BYTE2OF3: timer_period_a[15:8] <= instr;
          FETCH_STATE_READ_PERIOD_A_BYTE3OF3: timer_period_a[7:0] <= instr;
          FETCH_STATE_READ_PERIOD_B_BYTE2OF3: timer_period_b[15:8] <= instr;
          FETCH_STATE_READ_PERIOD_B_BYTE3OF3: timer_period_b[7:0] <= instr;
          default: begin end
        endcase
      end
  end
  endtask

  task fetch_read_bit();
    begin
      instr[INSTR_MSB:1] <= instr[INSTR_MSB-1:0];
      instr[0] <= uio_in_reg[EEPROM_CIPO];
      fetch_count <= fetch_count - 1;
      cur_addr <= fetch_count == 0 ? cur_addr + 1 : cur_addr;
    end
  endtask

  task fetch_write_bit(input [7:0]towrite);
    begin
      uio_out_reg[EEPROM_COPI] <= towrite[fetch_count];
      fetch_count <= fetch_count - 1;
    end
  endtask

  task write_stack();
    begin
      uio_out_reg[STACK_OUT] <= stack[7-fetch_count];
    end
  endtask

  task fetch_readwrite();
    begin
      case (fetch_state)
        FETCH_STATE_CS_EEPROM: fetch_write_bit(EEPROM_READ_COMMAND);
        FETCH_STATE_SEND_READ_CMD: fetch_write_bit(EEPROM_READ_COMMAND);
        FETCH_STATE_SEND_ADDRESS: fetch_write_bit(cycle_start_addr);
        FETCH_STATE_READ_RESET_VECTOR: fetch_read_bit();
        FETCH_STATE_READ_PROG_LAST_ADDR: fetch_read_bit();
        FETCH_STATE_READ_INSTR: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_A_BYTE2OF3: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_A_BYTE3OF3: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_B_BYTE2OF3: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_B_BYTE3OF3: fetch_read_bit();
        default: begin end
      endcase
    end
  endtask

  always @(negedge clk) begin
    if (!rst_n) begin
      fetch_state <= FETCH_STATE_INIT;
      fetch_count <= 3'h7;
      uo_out_reg <= 8'b0;
      uio_oe_reg <= (1 << EEPROM_SCK) + (1 << EEPROM_CS) + (1 << EEPROM_COPI) + (1 << TIMER_OUTPUT) + (1 << STACK_OUT);
      uio_out_reg <= (1 << EEPROM_CS);
      instr <= 8'b0;
      cycle_start_addr <= 8'b0;
      cycle_end_addr <= 8'b0;
      stack <= 16'b0;
      timer_reset();
    end else begin
      timer_update();
      fetch_cycle_update();
      fetch_readwrite();
      fetch_cycle_execute();
      write_stack();
    end
  end

  always @(posedge clk) begin
    ui_in_reg <= ui_in;
    uio_in_reg <= uio_in;
  end

endmodule
