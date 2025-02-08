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
  input timer_enabled,
  output timer_output,
  output [9:0]timer_counter_w
);
  reg [9:0] timer_counter;
  reg timer_phase;
  reg timer_output_r;
  

  assign timer_output = timer_output_r;
  assign timer_counter_w = timer_counter;

  always @(posedge clk) begin
    if (!rst_n) begin
      timer_counter <= 0;
    end else begin
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
