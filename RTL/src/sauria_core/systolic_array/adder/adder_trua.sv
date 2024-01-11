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

module adder_trua #(
    parameter A_APPROX = 0,
    parameter IP_W = 16,
    parameter OC_W = 16
)(
	// Data Inputs
    input  logic [IP_W-1:0]   	i_p,	    // First operand
	input  logic [OC_W-1:0]		i_c,	    // Second operand
    input  logic                i_carry,    // Carry in (IGNORED)
		
	// Data Outputs 
	output logic [OC_W-1:0]     o_c 	        // Sum output
);

// ---------------------
// Combinational part
// ---------------------

// Signed casting
logic signed [IP_W-1:0]     p;
logic signed [OC_W-1:0]     c, sum;

// TRUNCATE THE VALUES (set to zero all LSBs from bit A_APPROX)
generate
    if (A_APPROX>0) begin
        assign p = {i_p[IP_W-1:A_APPROX], {A_APPROX{1'b0}}};
        assign c = {i_c[OC_W-1:A_APPROX], {A_APPROX{1'b0}}};

    // Must handle the APPROX=zero case differenty to avoid inserting one dummy zero (left-shifting)
    end else begin
        assign p = i_p;
        assign c = i_c;
    end
endgenerate

// EXACT SUM on MSBs
assign sum = p + c;
assign o_c = sum;

endmodule
