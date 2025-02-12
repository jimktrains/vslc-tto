/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc_servo(
  input clk,
  input rst_n,
  input [7:0] servo_set_val,
  input [7:0] servo_reset_val,
  input [15:0] servo_freq_val,
  input servo_enabled,
  input servo_value,
  output servo_output
);
  reg [15:0] servo_counter;
  reg servo_output_r;

  assign servo_output = servo_output_r;

  always @(posedge clk) begin
    if (!rst_n || !servo_enabled) begin
      servo_output_r <= 1'b1;
      servo_counter <= 0;
    end else begin
      if ((servo_value == 1'b1) && (servo_counter == {8'b0, servo_set_val})) begin
        servo_counter <= servo_counter + 1;
        servo_output_r <= 0;
      end else if ((servo_value == 1'b0) && (servo_counter == {8'b0, servo_reset_val})) begin
        servo_counter <= servo_counter + 1;
        servo_output_r <= 0;
      end else if (servo_counter == servo_freq_val) begin
        servo_counter <= 16'b0;
        servo_output_r <= 1;
      end else begin
        servo_counter <= servo_counter + 1;
        servo_output_r <= servo_output_r;
      end
    end
  end
endmodule
