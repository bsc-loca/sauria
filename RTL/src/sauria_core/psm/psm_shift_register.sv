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

module psm_shift_register #(
	parameter X = 3,
    parameter BUFF_W = 144
)(
    // Clk, RST
	input logic 				i_clk,
	input logic					i_rstn,

	// Control Inputs
	input  logic				i_shift,	// Shift Enable
	input  logic				i_clear,	// Shift Enable

	// Data Inputs
    input  logic [BUFF_W-1:0]   i_din,		// Input Data Bus
		
	// Data Outputs 
	output logic [BUFF_W-1:0]  	o_dout 		// Output Data Bus
);

// ----------
// SIGNALS
// ----------

logic [0:X][BUFF_W-1:0] 	reg_q /*verilator split_var*/;

// ------------------------
// Registers instantiation
// ------------------------

genvar k;
generate
    // Generate one instance per position
    for (k=1; k<X+1; k=k+1) begin
        // Normal FF behavior
		always_ff @(posedge i_clk or negedge i_rstn) begin : shift_reg
			if(~i_rstn) begin
				reg_q[k] <= 0;
			end else begin
				
				// Synchronous reset
				if(i_clear)begin
					reg_q[k] <= 0;
				end else if(i_shift) begin
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
assign o_dout = reg_q[X];

endmodule
