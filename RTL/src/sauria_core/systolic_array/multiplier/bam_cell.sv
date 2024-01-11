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

module bam_cell #(

)(
	// Data Inputs
    input   logic	i_a,
	input   logic 	i_b,
	input  	logic 	i_s,
	input  	logic 	i_cin,
		
	// Data Outputs 
	output  logic 	o_s,
	output  logic 	o_cout
);

logic 			and_result;
logic [1:0] 	sum_result;

// ---------------------
// Combinational part
// ---------------------

// AND gate
assign and_result = i_a & i_b;

// Adder
assign sum_result = and_result + i_s + i_cin;

// Outputs
assign o_s = sum_result[0];
assign o_cout = sum_result[1];

endmodule
