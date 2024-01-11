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

module cnt_generic #(
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

	// Control Outputs
	output logic                    o_flag,         // Overflow flag (next position)

    // Data Outputs
	output logic [CNT_W-1:0]        o_cnt           // Counter output

);

// ----------
// SIGNALS
// ----------

// Counter value
logic [CNT_W-1:0]              cnt_d, cnt_q;

// -----------------
// Counter logic
// -----------------

// Combinational
always_comb begin

    cnt_d = cnt_q;
    o_flag = 0;

    // Synchronous reset
    if (i_clear) begin
        cnt_d = 0;
    end else begin
        
        // Up counting
        cnt_d = cnt_q + i_step;

        // Limit and overflow
        if (cnt_d >= i_lim) begin
            o_flag = 1;
            cnt_d = 0;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : cnt_reg
    if(~i_rstn) begin
        cnt_q <= 0;
    end else begin
        if (i_en || i_clear) begin
            cnt_q <= cnt_d;
        end
    end
end

// Output
assign o_cnt = cnt_q;

endmodule 
