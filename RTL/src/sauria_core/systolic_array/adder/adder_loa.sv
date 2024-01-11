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

// Macro for MAX of 2 parameters
`define max2(a,b)  ((a) > (b) ? (a) : (b))

// --------------------
// MODULE DECLARATION
// --------------------

module adder_loa #(
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

// Actual bits we compute exactly
localparam EXACT_W = `max2(IP_W,OC_W)-A_APPROX;

// LOW-BITS
logic [A_APPROX-1:0]     p_low, c_low, or_low;

logic carry_lower;

// HIGH-BITS -  Signed casting
logic signed [EXACT_W-1:0]     p_high;
logic signed [EXACT_W-1:0]     c_high, sum_high;

generate
    if (A_APPROX>0) begin
        
        // Assign LSBs to lower part
        assign p_low = i_p[A_APPROX-1:0];
        assign c_low = i_c[A_APPROX-1:0];

        // LOW-BITS - Inexact part (OR)
        assign or_low = p_low | c_low;

        // Assign MSBs to higher part (cast for sign extension)
        assign p_high = signed'(i_p[IP_W-1:A_APPROX]);
        assign c_high = signed'(i_c[OC_W-1:A_APPROX]);

        // Carry from lower part is the AND of the last LSB bits
        assign carry_lower = p_low[A_APPROX-1] & c_low[A_APPROX-1];

        // HIGH-BITS - Exact part
        assign sum_high = p_high + c_high + carry_lower;

        // Ensemble resulr
        assign o_c = {sum_high, or_low};

    // If no approximation is used (boring), just do the sum and bypass everything
    end else begin
        assign o_c = signed'(i_c) + signed'(i_p);
    end
endgenerate

endmodule
