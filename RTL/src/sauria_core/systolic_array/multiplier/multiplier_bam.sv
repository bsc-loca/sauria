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

module multiplier_bam #(
    parameter APPROX_TYPE = 0,
    parameter VBL = 0,
    parameter HBL = 0,
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

localparam IN_W = `max2(IA_W, IB_W);

// Sign management (for sign operation only)
logic a_sign, b_sign, prod_sign;

// Inputs
logic signed [IN_W-1:0] a;
logic signed [IN_W-1:0] b;

// Intermediate signals on the array
logic [IN_W:0][2*IN_W:0] s_array, c_array;

// Final product in binary
logic [MUL_W-1:0]   product;

// ------------------
// INPUT MANAGEMENT
// ------------------

// Force unsignedness when needed
generate
    
    // Signed (negate bits when needed)
    if (SIGNED) begin
        assign a_sign = i_a[IA_W-1];
        assign b_sign = i_b[IB_W-1];

        assign prod_sign = a_sign ^ b_sign;

        assign a = (a_sign)? {1'b0, -i_a[IA_W-2:0]} : {1'b0, i_a[IA_W-2:0]};
        assign b = (b_sign)? {1'b0, -i_b[IB_W-2:0]} : {1'b0, i_b[IB_W-2:0]};

    // Unsigned (values stay the same)
    end else begin
        assign a = i_a;
        assign b = i_b;
    end

endgenerate

// -----------------------------------
// BROKEN ARRAY MULTIPLIER STRUCTURE
// -----------------------------------

genvar x,y;
generate
    for (x=0; x < IN_W; x++) begin : x_axis
        for (y=0; y < 2*IN_W; y++) begin : y_axis

            // On first row, the s and c arrays are initialized to zero
            if (x==0) begin
                assign s_array[x][y] = 1'b0;
                assign c_array[x][y] = 1'b0;
            end

            // Active region (there are cells)
            if (((y-x)<IN_W) && (y>=x) && (x>=HBL) && (y>=VBL)) begin
            
                bam_cell #(
                ) bam_cell_i(
                    .i_a(a[x]),                     // Horizontal 
                    .i_b(b[y-x]),                   // Diagonal 

                    .i_s(s_array[x][y]),
                    .i_cin(c_array[x][y]),

                    .o_s(s_array[x+1][y]),          // Vertical
                    .o_cout(c_array[x+1][y+1])      // Diagonal
                );

            // Inactive region (cells omitted, signals shortcircuited)
            end else begin
                
                // Sum propagates down
                assign s_array[x+1][y] =    s_array[x][y];

                // Carry set to zero
                assign c_array[x+1][y+1] =  1'b0;

            end
        end
    end
endgenerate

// -----------------------------------
// MERGING ADDER
// -----------------------------------

// Lower half of the output is just the final S value
assign product[IN_W-1:0] = s_array[IN_W][IN_W-1:0];

// Upper half is the sum of S and C arrays at that point
assign product[2*IN_W-1:IN_W] = s_array[IN_W][2*IN_W-1:IN_W] + c_array[IN_W][2*IN_W-1:IN_W];

// -----------------------
// OUTPUT MANAGEMENT
// -----------------------

// Handle sign when needed
generate
    
    // Signed (negate bits when needed)
    if (SIGNED) begin
        assign o_prod = (prod_sign)? -product : product;

    // Unsigned (values stay the same)
    end else begin
        assign o_prod = product;
    end

endgenerate

endmodule
