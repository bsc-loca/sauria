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

module adder_ideal #(
    parameter IP_W = 16,
    parameter OC_W = 16
)(
	// Data Inputs
    input  logic [IP_W-1:0]   	i_p,	    // First operand
	input  logic [OC_W-1:0]		i_c,	    // Second operand
    input  logic                i_carry,    // Carry in
		
	// Data Outputs 
	output logic [OC_W-1:0]     o_c 	        // Sum output
);

// ---------------------
// Combinational part
// ---------------------

// Cast to signed when needed for sign extension
logic signed                carry;
logic signed [IP_W-1:0]     p;
logic signed [OC_W-1:0]     c, sum;

assign carry = i_carry;
assign p = i_p;
assign c = i_c;

// EXACT SUM
assign sum = p + c + carry;
assign o_c = sum;

endmodule
