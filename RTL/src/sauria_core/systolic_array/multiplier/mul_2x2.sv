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

module mul_2x2 #(
	parameter APPROX = 0   	// Set to 1 to have approximate version (UDM)
)(
	// Data Inputs
    input   logic [1:0]   	i_a,
	input   logic [1:0]		i_b,
		
	// Data Outputs 
	output  logic [3:0]  	o_ab 	// Mult output
);

// ----------
// SIGNALS
// ----------

logic [3:0] 	ab_prod;
logic 			and_0_0, and_0_1, and_1_0, and_1_1, and_cross;

// ---------------------
// Combinational part
// ---------------------

generate
	// Exact Multiplier
	if (APPROX == 0) begin

		
		// AND Gates
		assign and_0_0 = i_a[0] & i_b[0];
		assign and_0_1 = i_a[0] & i_b[1];
		assign and_1_0 = i_a[1] & i_b[0];
		assign and_1_1 = i_a[1] & i_b[1];
		assign and_cross = and_0_1 & and_1_0;

		// 2x2 Multiplier Gates
		assign ab_prod[0] = and_0_0;
		assign ab_prod[1] = and_0_1 ^ and_1_0;
		assign ab_prod[2] = and_1_1 ^ and_cross;
		assign ab_prod[3] = and_1_1 & and_cross;

	// Approximate Multiplier (UDM)
	end else if (APPROX == 1) begin
		
		// AND Gates
		assign and_0_0 = i_a[0] & i_b[0];
		assign and_0_1 = i_a[0] & i_b[1];
		assign and_1_0 = i_a[1] & i_b[0];
		assign and_1_1 = i_a[1] & i_b[1];

		// 2x2 Multiplier Gates
		assign ab_prod[0] = and_0_0;
		assign ab_prod[1] = and_0_1 | and_1_0;
		assign ab_prod[2] = and_1_1;
		assign ab_prod[3] = 0;

	end
endgenerate

// ---------------------
// Outputs
// ---------------------

assign o_ab = ab_prod;

endmodule
