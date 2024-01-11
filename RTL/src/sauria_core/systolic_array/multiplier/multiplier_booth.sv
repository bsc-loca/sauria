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

module multiplier_booth #(
    parameter APPROX_TYPE = 0,
    parameter M_APPROX = 16,
    parameter logic SIGNED = 0,
    parameter IA_W = 16,
    parameter IB_W = 16,
    parameter MUL_W = 32
)(
    // Clk, RST
	input logic 				i_clk,
    input logic                 i_en_ff,
	input logic					i_rstn,

	// Data Inputs
    input  logic [IA_W-1:0]   	i_a,	// Activation operand
	input  logic [IB_W-1:0]		i_b,	// Weight operand

	// Data Outputs 
	output logic [MUL_W-1:0]  	o_prod 	// Mult output
);

// ----------
// SIGNALS
// ----------

// Largest width operand
localparam IN_W = `max2(IA_W, IB_W) + (!SIGNED);   // If unsigned we pad 1 zero bit to force unsignedness (ASSUMTION - WHEN WE USE UNSIGNED, THE NUMBER OF BITS IS ODD DUE TO FP IMPLICIT BIT)

// Inputs and product
logic signed [IN_W-1:0] a;
logic signed [IN_W-1:0] b;

// BOOTH SIGNALS
localparam                              N_PARTIAL = (IN_W/2);       // Number of partial products

logic [0:N_PARTIAL-1][2:0]              r_groups;                   // Radix-4 groups
logic [0:N_PARTIAL-1]                   r_neg;                      // Radix-4 neg bit
logic [0:N_PARTIAL-1]                   r_two;                      // Radix-4 two bit
logic [0:N_PARTIAL-1]                   r_zero;                     // Radix-4 zero bit

logic signed [0:N_PARTIAL-1][IN_W:0]    pproducts;                  // Partial products
logic signed [2*IN_W-1:0]               final_sum;

// Force unsignedness when needed
generate
    
    // Signed (values stay the same, bits are extended accordingly)
    if (SIGNED) begin
        assign a = $signed(i_a);
        assign b = $signed(i_b);

    // Unsigned (0 padding at MSBs)
    end else begin
        assign a = {1'b0, i_a};
        assign b = {1'b0, i_b};
    end

endgenerate

// ***************************
//    4-RADIX BOOTH ENCODER
// ***************************

always_comb begin : Booth_Encoder

    for (integer j=0; j<N_PARTIAL; j++) begin

        if (j==0) begin
            r_groups[j] = {a[2*j+1], a[2*j], 1'b0};

        end else begin
            r_groups[j] = {a[2*j+1], a[2*j], a[2*j-1]};
        end
    end
end

// *********************************
//    PARTIAL PRODUCTS GENERATION
// *********************************

always_comb begin : Pprod_gen

    for (integer j=0; j<N_PARTIAL; j++) begin

        // ----------------------------------------------------------------------------
        // GENUS-INFERRED LOGIC - As good as * itself, cannot use approximation :(
        // case (r_groups[j])
        //    3'b000 : pproducts[j] = 0;
        //    3'b001 : pproducts[j] =  b;
        //    3'b010 : pproducts[j] =  b;
        //    3'b011 : pproducts[j] =  2*b;
        //    3'b100 : pproducts[j] = -2*b;
        //    3'b101 : pproducts[j] = -b;
        //    3'b110 : pproducts[j] = -b;
        //    default: pproducts[j] = 0;
        // endcase
        // -----------------------------------------------------------------------------

        // Generate flags
        case (r_groups[j])

            3'b000 : begin           // 0
                r_neg[j] = 0;
                r_two[j] = 0;
                r_zero[j] = 1;
            end
            3'b001 : begin           // b
                r_neg[j] = 0;
                r_two[j] = 0;
                r_zero[j] = 0;
            end
            3'b010 : begin           // b
                r_neg[j] = 0;
                r_two[j] = 0;
                r_zero[j] = 0;
            end
            3'b011 : begin           // 2b
                r_neg[j] = 0;
                r_two[j] = 1;
                r_zero[j] = 0;
            end
            3'b100 : begin           // -2b
                r_neg[j] = 1;
                r_two[j] = 1;
                r_zero[j] = 0;
            end
            3'b101 : begin           // -b
                r_neg[j] = 1;
                r_two[j] = 0;
                r_zero[j] = 0;
            end
            3'b110 : begin           // -b
                r_neg[j] = 1;
                r_two[j] = 0;
                r_zero[j] = 0;
            end
            default: begin           // 0
                r_neg[j] = 0;
                r_two[j] = 0;
                r_zero[j] = 1;
            end

        endcase

        // Perform operand inversion and shift bitwise
        for (integer k=0; k<(IN_W+1); k++) begin

            // APPROXIMATE REGION
            if ((APPROX_TYPE>0) && (k < M_APPROX-(2*j))) begin
            
                // APPROXIMATE ABM-M1
                if (APPROX_TYPE==1) begin

                    // Boundary, MSB (extend sign bit!)
                    if (k==IN_W) begin
                        pproducts[j][k] = (~b[IN_W-1] & r_neg[j]) | (b[IN_W-1] & ~r_neg[j] & ~r_zero[j]);

                    // Normal case
                    end else begin
                        pproducts[j][k] = (~b[k] & r_neg[j]) | (b[k] & ~r_neg[j] & ~r_zero[j]);
                    end

                // APPROXIMATE ABM-M3
                end else begin
                    
                    // We just OR everything in the approximate region, and leave LSBs to zero
                    if (k==0) begin
                        pproducts[j][0] = b[0] & ~r_zero[j];
                    
                    // Normal case
                    end else if (k<IN_W) begin
                        pproducts[j][k] = (pproducts[j][k-1] | b[k]) & ~r_zero[j];
                        pproducts[j][k-1] = 1'b0;

                    // Boundary, MSB (extend sign bit!)
                    end else begin
                        pproducts[j][k] = (pproducts[j][k-1] | b[IN_W-1]) & ~r_zero[j];
                        pproducts[j][k-1] = 1'b0;
                    end
                end

            // EXACT REGION
            end else begin

                if (k==0) begin
                    pproducts[j][k] = (((b[k] & ~r_two[j]) | (1'b0 & r_two[j])) ^ r_neg[j]) & ~r_zero[j];

                // Boundary, MSB (extend sign bit!)
                end else if (k==IN_W) begin
                    pproducts[j][k] = (((b[IN_W-1] & ~r_two[j]) | (b[k-1] & r_two[j])) ^ r_neg[j]) & ~r_zero[j];

                // Normal case
                end else begin
                    pproducts[j][k] = (((b[k] & ~r_two[j]) | (b[k-1] & r_two[j])) ^ r_neg[j]) & ~r_zero[j];
                end
            end
        end

        // Sign correction bits, only if exact multiplier
        if (APPROX_TYPE==0) begin
            pproducts[j] = pproducts[j] + r_neg[j];

        end else begin
            
            // ABM-M1 => OR LSB (fixes problem if no carry, avoids sum)
            if (APPROX_TYPE==1) begin
                pproducts[j][0] = pproducts[j][0] | r_neg[j];

            // ABM-M3 => Sign correction bits only in fully exact region
            end else begin
                
                if (M_APPROX-(2*j) <= 0) begin
                    pproducts[j] = pproducts[j] + r_neg[j];

                end
            end
        end
    end
end

// *********************************
//    PARTIAL PRODUCTS REDUCTION
// *********************************

always_comb begin : Pprod_reduction

    final_sum = 0;

    for (integer j=0; j<N_PARTIAL; j++) begin
        final_sum = $signed(final_sum) + ($signed(pproducts[j]) * $signed(2**(2*j)));
    end
end

// ************
//    OUTPUT
// ************

assign o_prod = final_sum;

endmodule
