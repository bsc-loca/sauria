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

module feed_registers #(
    parameter N_REGS = 1,
    parameter I_W = 16
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [I_W-1:0]          i_din,              // Input data
	
	// Control Inputs
    input logic                     i_clear,            // Clear signal
    input logic                     i_pipeline_en,      // Systolic Array pipeline enable

    // Data Outputs
	output logic [I_W-1:0]          o_dout              // Output data

);

// ----------
// SIGNALS
// ----------

logic [0:N_REGS][I_W-1:0] 	        reg_q /*verilator split_var*/;

// ------------------------
// Registers instantiation
// ------------------------

genvar k;
generate
    // Generate one instance per position
    for (k=1; k<N_REGS+1; k=k+1) begin
        // Normal FF behavior
		always_ff @(posedge i_clk or negedge i_rstn) begin : shift_reg
			if(~i_rstn) begin
				reg_q[k] <= 0;
			end else begin
				
				// Synchronous reset
				if(i_clear)begin
					reg_q[k] <= 0;
				end else if(i_pipeline_en) begin
					reg_q[k] <= reg_q[k-1];
				end
			end
		end
    end
endgenerate

// -------------------
// IO Mapping
// -------------------

assign reg_q[0] = i_din;
assign o_dout = reg_q[N_REGS];

endmodule 
