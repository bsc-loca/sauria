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

module adder_gear #(
    parameter R = 16,
    parameter P = 16,
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

// GeAr Parameters
localparam N_BITS = `max2(IP_W,OC_W);
localparam L = R+P;         // Actual sub-adder length
localparam k = int'($ceil(1+((N_BITS-L)/R)));

localparam N_BITS_EFF = L + (k-1)*R;

// Input wires (adapted to max width)
logic signed [N_BITS-1:0]       p,c;

// Sub-Adder inputs and ouputs
logic signed [0:k-1][L-1:0]    subadd_p, subadd_c;
logic signed [0:k-1][L:0]      subadd_o;

// Expanded sum output
logic signed [N_BITS_EFF-1:0] sum;

// INPUT MANAGEMENT
assign p = signed'(i_p);
assign c = signed'(i_c);

// SUB-ADDERS
genvar i;
generate

    for (i=0; i < k; i++) begin : subadders

        // Inputs assigned with according Overlap (acc. to P)
        assign subadd_p[i] = p[i*R+:L];
        assign subadd_c[i] = c[i*R+:L];

        // Sub-adders are just normal adders
        assign subadd_o[i] = subadd_p[i] + subadd_c[i];

        // First (LSB) sub-adder contributes L LSBs to final value
        if (i==0) begin

            assign sum[L-1:0] = subadd_o[0][L-1:0];

        // Each of the other subadders contributes R bits (P bits are discarded from the result)
        end else begin
            
            assign sum[P+(i*R)+:R] = subadd_o[i][L-1:P];

        end
    end

endgenerate

// Final output
assign o_c = sum;

endmodule
