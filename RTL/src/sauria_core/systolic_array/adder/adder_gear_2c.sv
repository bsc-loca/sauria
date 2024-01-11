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

module adder_gear_2c #(
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
localparam L = R+P;                             // Actual sub-adder length
localparam k = int'($ceil(1+((N_BITS-L)/R)));   // Number of sub-adders

localparam N_BITS_EFF = L + (k-1)*R;

// Input wires (adapted to max width)
logic signed [N_BITS-1:0]       p,c;

// Sub-Adder inputs and ouputs
logic signed [0:k-1][L-1:0]    subadd_p, subadd_c;
logic signed [0:k-1][L:0]      subadd_o;
logic signed [0:k-1][L-1:0]    subadd_o_corrected;

// Sub-Adder O signal and carry-out
logic [0:k-1] subadd_ones, subadd_cout;

// Correction carries
logic [0:k-1] carries;

// Expanded sum output
logic signed [N_BITS_EFF-1:0] sum;

// INPUT MANAGEMENT
assign p = signed'(i_p);
assign c = signed'(i_c);

// SUB-ADDERS
genvar i, bb;
generate

    for (i=0; i < k; i++) begin : subadders

        // Inputs assigned with according Overlap (acc. to P)
        assign subadd_p[i] = p[i*R+:L];
        assign subadd_c[i] = c[i*R+:L];

        // Sub-adders are just normal adders
        assign subadd_o[i] = subadd_p[i] + subadd_c[i];

        // Carry out signal
        assign subadd_cout[i] = subadd_o[i][L];

        // First (LSB) sub-adder
        if (i==0) begin

            // No correction is needed: Ones signal is irrelevant
            assign subadd_ones[0] = 1'b0;
            assign subadd_o_corrected[0] = subadd_o[0][L-1:0];

            // First (LSB) sub-adder contributes L LSBs to final value
            assign sum[L-1:0] = subadd_o_corrected[0];

            // Carry always propagated
            assign carries[0] = subadd_cout[0];

        // Higher sub-adders
        end else begin
            
            // Ones signal => AND all relevant output bits together (carry irrelevant)
            always_comb begin : and_bits
                for (integer b=0; b<L; b++) begin
                    if (b==0) begin
                        subadd_ones[i] = subadd_o[i][0];
                    end else begin
                        subadd_ones[i] = subadd_o[i][b] & subadd_ones[i];
                    end
                end
            end

            // APPLY CORRECTION TO ALL USEFUL BITS
            for (bb=0; bb < R; bb++) begin : corr_bits
                assign subadd_o_corrected[i][P+bb] = (subadd_o[i][P+bb] & (!subadd_ones[i])) | ((!carries[i-1]) & subadd_ones[i]);
            end

            // Lower P bits will be discarded so just tie to zero
            assign subadd_o_corrected[i][P-1:0] = '0; 

            // Each of the other subadders contributes R bits (P bits are discarded from the result)
            assign sum[P+(i*R)+:R] = subadd_o_corrected[i][L-1:P]; 

            // Carries signal for next adder: propagation gated by Ones signal
            assign carries[i] = subadd_cout[i] | (carries[i-1] & subadd_ones[i]);

        end
    end

endgenerate

// Final output
assign o_c = sum;

endmodule
