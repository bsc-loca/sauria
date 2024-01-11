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

module wallace_8 #(
	parameter integer APPROX_TYPE = 0   	    // Type of Approximate Structure
)(
	// Data Inputs
    input   logic [7:0]   	i_a,
	input   logic [7:0]	    i_b,
		
	// Data Outputs 
	output  logic [15:0]     o_ab 	            // Mult output
);

// ----------
// SIGNALS
// ----------

// Low & High operand regions
logic [3:0] AL, AH, BL, BH;

// Multiplier outputs
logic [7:0] acc_ALxBL, acc_ALxBH, acc_AHxBL, acc_AHxBH;

// Partial sums
logic [5:0] partial1;
logic [5:0] partial2;
logic [5:0] partial3;

// Approximate computing usage parameters
localparam integer APPROX_0 = APPROX_TYPE;
localparam integer APPROX_1 = APPROX_TYPE;
localparam integer APPROX_2 = APPROX_TYPE;
localparam integer APPROX_3 = (APPROX_TYPE==2)? 2 : 0;      // AHxBH can only be Aprox if TYPE=2

// ---------------------
// Multiplier Tree
// ---------------------

assign AL = i_a[3:0];
assign AH = i_a[7:4];
assign BL = i_b[3:0];
assign BH = i_b[7:4];

// Lower-level multipliers
wallace_4 #(.APPROX_TYPE(APPROX_0)) ALxBL
    (.i_a(AL), .i_b(BL), .o_ab(acc_ALxBL));

wallace_4 #(.APPROX_TYPE(APPROX_1)) ALxBH
    (.i_a(AL), .i_b(BH), .o_ab(acc_ALxBH));

wallace_4 #(.APPROX_TYPE(APPROX_2)) AHxBL
    (.i_a(AH), .i_b(BL), .o_ab(acc_AHxBL));

wallace_4 #(.APPROX_TYPE(APPROX_3)) AHxBH
    (.i_a(AH), .i_b(BH), .o_ab(acc_AHxBH));

// ---------------------
// Partial Sums
// ---------------------

// First Block:               LSBs          +      LSBs         +     MSBs
assign partial1 	    = acc_ALxBH[3:0]    + acc_AHxBL[3:0]    + acc_ALxBL[7:4];

// Second Block:             Carry          +      LSBs         +     MSBs          +      MSBs
assign partial2	        = partial1[5:4]     + acc_AHxBH[3:0]    + acc_ALxBH[7:4]    + acc_AHxBL[7:4];

// Third Block:               MSBs          +      Carry
assign partial3         = acc_AHxBH[7:4]    + partial2[5:4];

// ---------------------
// Outputs
// ---------------------

assign o_ab = {partial3[3:0], partial2[3:0], partial1[3:0], acc_ALxBL[3:0]};

endmodule
