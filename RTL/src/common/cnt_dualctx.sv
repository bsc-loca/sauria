// Copyright 2023 Barcelona Supercomputing Center (BSC)
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Licensed under the Solderpad Hardware License v 2.1 (the “License”);
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at

// https://solderpad.org/licenses/SHL-2.1/

// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.

//
// Jordi Fornt <jfornt@bsc.es>

// ----------
// MACROS
// ----------

// --------------------
// MODULE DECLARATION
// --------------------

module cnt_dualctx #(
    parameter CNT_W = 8
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [CNT_W-1:0]        i_lim,          // Counter limit (exclusive)
    input  logic [CNT_W-1:0]        i_step,         // Counter step (exclusive)
	
	// Control Inputs
    input  logic					i_en,           // Counter Enable
    input  logic                    i_clear,        // Counter Clear (synchronous reset to zero)
    input  logic                    i_sel,          // Context selection

	// Control Outputs
	output logic                    o_flag,         // Overflow flag (next position)

    // Data Outputs
	output logic [CNT_W-1:0]        o_cnt           // Counter output

);

// ----------
// SIGNALS
// ----------

// Counter value
logic [CNT_W-1:0]              cnt_d1, cnt_q1, cnt_d2, cnt_q2, sum_insel, sum_outsel;

// -----------------
// Counter logic
// -----------------

// Combinational
always_comb begin

    cnt_d1 = cnt_q1;
    cnt_d2 = cnt_q2;
    o_flag = 0;

    // Input selection logic
    if (i_sel) begin
        sum_insel = cnt_q1;
    end else begin
        sum_insel = cnt_q2;
    end

    // Adder
    sum_outsel = sum_insel + i_step;

    // Synchronous reset
    if (i_clear) begin
        cnt_d1 = 0;
        cnt_d2 = 0;
    end else begin
        
        // Limit and overflow
        if (sum_outsel >= i_lim) begin
            o_flag = 1;
            sum_outsel = 0;
        end

        // Output selection logic
        if (i_sel) begin
            cnt_d1 = sum_outsel;
        end else begin
            cnt_d2 = sum_outsel;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : cnt_reg
    if(~i_rstn) begin
        cnt_q1 <= 0;
        cnt_q2 <= 0;
    end else begin
        if (i_en || i_clear) begin
            cnt_q1 <= cnt_d1;
            cnt_q2 <= cnt_d2;
        end
    end
end

// Output
assign o_cnt = (i_sel) ? cnt_q1 : cnt_q2;

endmodule 
