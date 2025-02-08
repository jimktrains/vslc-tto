/*
* Copyright (c) 2025 James Keener
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_jimktrains_vslc_timer(
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
