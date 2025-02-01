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

  // https://ww1.microchip.com/downloads/en/DeviceDoc/22040A.pdf
  // SPI Serial EEPROM Family Data Sheet
  localparam EEPROM_READ_COMMAND = 8'b00000011;

  localparam CYCLE_START = 0;
  localparam EEPROM_CS = 1;
  localparam EEPROM_COPI = 2;
  localparam EEPROM_CIPO = 3;
  localparam STACK_OUT2 = 4;
  localparam STACK_OUT = 5;
  localparam TOS_OUT = 6;
  localparam TIMER_OUTPUT = 7;

  reg [3:0] fetch_prev_state;
  reg [3:0] fetch_state;
  reg [2:0] fetch_count;

  reg [7:0] uo_out_reg;
  reg [7:0] uio_oe_reg;
  reg [7:0] uio_out_reg;
  reg [7:0] ui_in_reg;
  reg [7:0] ui_in_prev_reg;


  // List all unused inputs to prevent warnings
  wire [15:0]_unused = {ena, eeprom_copi, eeprom_cs, timer_out, cycle_end_addr, stack_out, stack_out2};

  localparam FETCH_STATE_INIT = 4'h0;
  localparam FETCH_STATE_CS_EEPROM_HIGH = 4'h1;
  localparam FETCH_STATE_CS_EEPROM = 4'h3;
  localparam FETCH_STATE_READ_PROG_LAST_ADDR_2OF2 = 4'h4;
  localparam FETCH_STATE_READ_INSTR = 4'h5;
  localparam FETCH_STATE_READ_PERIOD_A_BYTE2OF3 = 4'h6;
  localparam FETCH_STATE_READ_PERIOD_A_BYTE3OF3 = 4'h7;
  localparam FETCH_STATE_READ_PERIOD_B_BYTE2OF3 = 4'h8;
  localparam FETCH_STATE_READ_PERIOD_B_BYTE3OF3 = 4'h9;
  localparam FETCH_STATE_READ_PROG_LAST_ADDR = 4'hA;
  localparam FETCH_STATE_READ_RESET_VECTOR = 4'hB;
  localparam FETCH_STATE_SEND_ADDRESS = 4'hC;
  localparam FETCH_STATE_SEND_READ_CMD = 4'hD;
  localparam FETCH_STATE_SEND_ADDRESS_2OF2 = 4'hE;
  localparam FETCH_STATE_READ_RESET_VECTOR_2OF2 = 4'hF;

  localparam INSTR_CLR    = 8'hf0;
  localparam INSTR_SETALL = 8'hf1;
  localparam INSTR_SWAP   = 8'hf2;
  localparam INSTR_ROT    = 8'hf3;

  localparam INSTR_CLASS_STACK = 2'b00;
  localparam INSTR_CLASS_SETUP = 2'b01;
  localparam INSTR_CLASS_LOGIC = 2'b10;
  localparam INSTR_CLASS_OTHER = 2'b11;

  localparam INSTR_SETUP_PERIOD_A = 8'h70;
  localparam INSTR_SETUP_PERIOD_B = 8'h71;
  localparam INSTR_SETUP_CLOCKDIV_74 = 4'h4;
  localparam INSTR_SETUP_MODE_74 = 4'h5;

  localparam [3:0]INSTR_STACK_PUSH_74 = 4'b0000;
  localparam [3:0]INSTR_STACK_POP_74 = 4'b0001;
  localparam [3:0]INSTR_STACK_SET_74 = 4'b0010;
  localparam [3:0]INSTR_STACK_RESET_74 = 4'b0011;

  localparam [4:0]INSTR_OTHER_RISING_73 = 5'b11100;
  localparam [4:0]INSTR_OTHER_FALLING_73 = 5'b11101;


  localparam INSTR_MSB = 7;

  reg [9:0]cycle_start_addr;
  reg [9:0]cycle_end_addr;
  reg [9:0] cur_addr;
  reg [7:0]instr;
  wire [1:0]instr_class;
  wire [2:0]regid;
  wire [3:0]instr_clock_div;
  wire instr_timer_mode_bit;


  localparam STACK_MSB = 15;
  reg [STACK_MSB:0]stack = 16'b0;
  wire stack_out; assign stack_out = uio_out_reg[STACK_OUT];
  wire stack_out2; assign stack_out2 = uio_out_reg[STACK_OUT2];
  wire tos; assign tos = stack[0];

  reg [15:0] timer_clock_counter;
  reg [3:0] timer_clock_divisor;
  reg [15:0] timer_counter;
  reg [15:0] timer_period_a;
  reg [15:0] timer_period_b;
  reg timer_enabled;
  reg timer_phase;
  reg timer_mode;

  assign uo_out[7:0] = uo_out_reg[7:0];
  assign uio_out[7:0] = uio_out_reg[7:0];
  assign uio_oe[7:0] = uio_oe_reg[7:0];

  // Giving these names just makes it easier to find in the vcd.
  wire eeprom_cs; assign eeprom_cs = uio_out[EEPROM_CS];
  wire eeprom_copi; assign eeprom_copi = uio_out[EEPROM_COPI];
  wire eeprom_cipo; assign eeprom_cipo = uio_in[EEPROM_CIPO];
  wire timer_out; assign timer_out = uio_out[TIMER_OUTPUT];
  wire cycle_start;
  reg cycle_should_start;
  assign cycle_start = uio_in[CYCLE_START] || cycle_should_start;

  assign instr_class[1:0] = instr[INSTR_MSB -: 2];
  assign instr_clock_div = instr[3:0];
  assign instr_timer_mode_bit = instr[0];

  assign regid = instr[2:0];

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
            timer_enabled <= timer_mode == TIMER_MODE_CYCLE;
            uio_out_reg[TIMER_OUTPUT] <= timer_period_b == 0 ? uio_out_reg[TIMER_OUTPUT] : ~uio_out_reg[TIMER_OUTPUT];
          end else begin
            timer_counter <= timer_counter + 1;
            timer_phase <= timer_phase;
            timer_enabled <= timer_enabled;
            uio_out_reg[TIMER_OUTPUT] <= uio_out_reg[TIMER_OUTPUT];
          end
        end else begin
          timer_phase <= timer_phase;
          timer_enabled <= timer_enabled;
          timer_counter <= timer_counter;
          uio_out_reg[TIMER_OUTPUT] <= uio_out_reg[TIMER_OUTPUT];
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
      timer_clock_divisor <= 4'b0000;
      timer_counter <= 16'b0;
      timer_period_a <= 16'b1;
      timer_period_b <= 16'h2;
      timer_enabled <= 1'b0;
      timer_phase <= 1'b0;
      timer_mode <= 1'b0;
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
          cur_addr <= cycle_start_addr;
          fetch_count <= 3'h7;
          cycle_should_start <= 0;
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
              FETCH_STATE_SEND_ADDRESS: fetch_state <= FETCH_STATE_SEND_ADDRESS_2OF2;
              FETCH_STATE_SEND_ADDRESS_2OF2: begin
                case (cycle_start_addr)
                  10'h00: fetch_state <= FETCH_STATE_READ_RESET_VECTOR;
                  default: fetch_state <= FETCH_STATE_READ_INSTR;
                endcase
              end
              FETCH_STATE_READ_RESET_VECTOR: fetch_state <= FETCH_STATE_READ_RESET_VECTOR_2OF2;
              FETCH_STATE_READ_RESET_VECTOR_2OF2: fetch_state <= FETCH_STATE_READ_PROG_LAST_ADDR;
              FETCH_STATE_READ_PROG_LAST_ADDR: fetch_state <= FETCH_STATE_READ_PROG_LAST_ADDR_2OF2;
              FETCH_STATE_READ_PROG_LAST_ADDR_2OF2: fetch_state <= FETCH_STATE_READ_INSTR;
              FETCH_STATE_READ_INSTR: begin
                // Past the end of the program or wrapped the address space.
                if (cur_addr >= cycle_end_addr || cur_addr == 0) begin
                  fetch_state <= FETCH_STATE_CS_EEPROM_HIGH;
                  cycle_should_start <= 1'b1;
                end else if (instr == INSTR_SETUP_PERIOD_A) begin
                  fetch_state <= FETCH_STATE_READ_PERIOD_A_BYTE2OF3;
                end else if (instr == INSTR_SETUP_PERIOD_B) begin
                  fetch_state <= FETCH_STATE_READ_PERIOD_B_BYTE2OF3;
                end else begin 
                  fetch_state <= FETCH_STATE_READ_INSTR;
                end
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
        cycle_start_addr <= cycle_start_addr;
        case (fetch_prev_state)
          // I need to redo this to have it pull in 2 bytes if I continue
          // with this idea.
          FETCH_STATE_READ_RESET_VECTOR: cycle_start_addr[9:8] <= instr[1:0];
          FETCH_STATE_READ_RESET_VECTOR_2OF2: cycle_start_addr[7:0] <= instr;
          FETCH_STATE_READ_PROG_LAST_ADDR: cycle_end_addr[9:8] <= instr[1:0];
          FETCH_STATE_READ_PROG_LAST_ADDR_2OF2: cycle_end_addr[7:0] <= instr;
          default: cycle_start_addr <= cycle_start_addr;
        endcase
        case (fetch_prev_state)
          FETCH_STATE_READ_INSTR: begin
            case (instr_class)
              INSTR_CLASS_STACK: begin
                case (instr[7:4])
                  INSTR_STACK_PUSH_74: begin
                    stack[STACK_MSB:1] <= stack[STACK_MSB-1:0];
                    if (instr[3] == 1'b0) stack[0] <= ui_in_reg[regid];
                    else if (instr[3] == 1'b1) stack[0] <= uo_out_reg[regid];
                  end
                  INSTR_STACK_POP_74: begin
                    stack[STACK_MSB-1:0] <= stack[STACK_MSB:1];
                    if (instr[3] == 1'b0) timer_enabled <= stack[0];
                    else if (instr[3] == 1'b1) uo_out_reg[regid] <= stack[0];
                  end
                  INSTR_STACK_SET_74: begin
                    stack[STACK_MSB-1:0] <= stack[STACK_MSB:1];
                    if (instr[3] == 1'b0) timer_enabled <= stack[0] ? 1 : timer_enabled;
                    else if (instr[3] == 1'b1) uo_out_reg[regid] <= stack[0] ? 1 : uo_out_reg[regid];
                  end
                  INSTR_STACK_RESET_74: begin
                    stack[STACK_MSB-1:0] <= stack[STACK_MSB:1];
                    if (instr[3] == 1'b0) timer_enabled <= stack[0] ? 0 : timer_enabled;
                    else if (instr[3] == 1'b1) uo_out_reg[regid] <= stack[0] ? 0 : uo_out_reg[regid];
                  end
                  default: begin
                    stack <= stack;
                  end
                endcase
              end
              INSTR_CLASS_LOGIC: begin
                if (instr[5:4]== 2) stack[STACK_MSB - 1: 1] <= stack[STACK_MSB:2];
                else if (instr[5:4]== 0) stack[STACK_MSB:1] <= stack[STACK_MSB - 1:0];
                stack[0] <= instr[3'h3 - stack[1:0]];
              end
              INSTR_CLASS_OTHER: begin
                case (instr[7:3])
                  INSTR_OTHER_RISING_73: begin
                    stack[STACK_MSB:1] <= stack[STACK_MSB - 1:0];
                    stack[0] <= ui_in_reg[regid] == 1 && ui_in_prev_reg[regid] == 0;
                  end
                  INSTR_OTHER_FALLING_73: begin
                    stack[STACK_MSB:1] <= stack[STACK_MSB - 1:0];
                    stack[0] <= ui_in_reg[regid] == 0 && ui_in_prev_reg[regid] == 1;
                  end
                  default:
                case (instr)
                  INSTR_CLR: stack <= 16'h0000;
                  INSTR_SETALL: stack <= 16'hffff;
                  INSTR_SWAP: begin
                    stack[1] <= stack[0];
                    stack[0] <= stack[1];
                  end
                  INSTR_ROT: begin
                    stack[0] <= stack[1];
                    stack[1] <= stack[2];
                    stack[2] <= stack[0];
                  end
                  default: stack[STACK_MSB:0] <= stack[STACK_MSB:0];
                endcase
              endcase
              end
              INSTR_CLASS_SETUP: begin
                stack <= stack;
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
      end else begin
        cycle_start_addr <= cycle_start_addr;
      end
  end
  endtask

  task fetch_read_bit();
    begin
      //instr[INSTR_MSB:1] <= instr[INSTR_MSB-1:0];
      instr[fetch_count] <= eeprom_cipo;
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
      // Send it out after the computation is done.
      if (fetch_count < 6 && fetch_count > 1) begin
        uio_out_reg[STACK_OUT] <= stack[((fetch_count - 2) * 2) + 1];
        uio_out_reg[STACK_OUT2] <= stack[(fetch_count - 2) * 2];
      end else begin
        uio_out_reg[STACK_OUT] <= 1'b0;
        uio_out_reg[STACK_OUT2] <= 1'b0;
      end
      uio_out_reg[TOS_OUT] <= tos;
    end
  endtask

  task fetch_readwrite();
    begin
      case (fetch_state)
        FETCH_STATE_CS_EEPROM: fetch_write_bit(EEPROM_READ_COMMAND);
        FETCH_STATE_SEND_READ_CMD: fetch_write_bit(EEPROM_READ_COMMAND);
        FETCH_STATE_SEND_ADDRESS_2OF2: fetch_write_bit(cycle_start_addr[7:0]);
        FETCH_STATE_SEND_ADDRESS: fetch_write_bit({6'b0, cycle_start_addr[9:8]});
        FETCH_STATE_READ_RESET_VECTOR: fetch_read_bit();
        FETCH_STATE_READ_RESET_VECTOR_2OF2: fetch_read_bit();
        FETCH_STATE_READ_PROG_LAST_ADDR: fetch_read_bit();
        FETCH_STATE_READ_PROG_LAST_ADDR_2OF2: fetch_read_bit();
        FETCH_STATE_READ_INSTR: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_A_BYTE2OF3: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_A_BYTE3OF3: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_B_BYTE2OF3: fetch_read_bit();
        FETCH_STATE_READ_PERIOD_B_BYTE3OF3: fetch_read_bit();
        default: begin end
      endcase
    end
  endtask

  reg cycle_in_prev;

  // negedge for processing and clocking data out.
  always @(negedge clk) begin
    if (!rst_n) begin
      fetch_state <= FETCH_STATE_INIT;
      fetch_prev_state <= FETCH_STATE_INIT;
      fetch_count <= 3'h7;
      uo_out_reg <= 8'b0;
      uio_oe_reg <=
        (8'b0 << CYCLE_START) +
        (8'b1 << EEPROM_CS) +
        (8'b1 << EEPROM_COPI) +
        (8'b0 << EEPROM_CIPO) +
        (8'b1 << STACK_OUT2) +
        (8'b1 << TOS_OUT) +
        (8'b1 << STACK_OUT) +
        (8'b1 << TIMER_OUTPUT) +
        8'b0;
      uio_out_reg <= (1 << EEPROM_CS);
      instr <= 8'b0;
      cycle_start_addr <= 10'b0;
      cycle_end_addr <= 10'b0;
      stack <= 16'b0;
      timer_reset();
      cur_addr <= 10'b0;
      cycle_should_start <= 1'b0;
    end else begin
      if (!timer_enabled) timer_reset();
      timer_update();
      fetch_cycle_update();
      fetch_readwrite();
      fetch_cycle_execute();
      write_stack();

    end
  end

  // posedge for clocking data in.
  always @(posedge clk) begin
    if (!rst_n) begin
      ui_in_reg <= ui_in;
      ui_in_prev_reg <= ui_in;
      cycle_in_prev <= 0;
    end else begin
      cycle_in_prev <= cycle_start;

      if (cycle_start == 1 && cycle_in_prev == 0) begin
        ui_in_reg <= ui_in;
        ui_in_prev_reg <= ui_in_reg;
      end else begin
        ui_in_reg <= ui_in_reg;
        ui_in_prev_reg <= ui_in_prev_reg;
      end
    end
  end
endmodule
