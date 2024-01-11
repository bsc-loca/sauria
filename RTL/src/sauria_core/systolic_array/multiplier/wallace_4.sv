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

module wallace_4 #(
	parameter integer APPROX_TYPE = 0   	    // Type of Approximate Structure
)(
	// Data Inputs
    input   logic [3:0]   	i_a,
	input   logic [3:0]	    i_b,
		
	// Data Outputs 
	output  logic [7:0]     o_ab 	            // Mult output
);

// ----------
// SIGNALS
// ----------

// Low & High operand regions
logic [1:0] AL, AH, BL, BH;

// Multiplier outputs
logic [3:0] acc_ALxBL, acc_ALxBH, acc_AHxBL, acc_AHxBH;

// Partial sums
logic [3:0] partial1;
logic [3:0] partial2;
logic [3:0] partial3;

// Approximate computing usage parameters
localparam integer APPROX_0 = (APPROX_TYPE==0)? 0 : 1;      // Lower ones can only be Exact if TYPE=0
localparam integer APPROX_1 = (APPROX_TYPE==0)? 0 : 1;
localparam integer APPROX_2 = (APPROX_TYPE==0)? 0 : 1;
localparam integer APPROX_3 = (APPROX_TYPE==2)? 1 : 0;      // AHxBH can only be Aprox if TYPE=2

// ---------------------
// Multiplier Tree
// ---------------------

assign AL = i_a[1:0];
assign AH = i_a[3:2];
assign BL = i_b[1:0];
assign BH = i_b[3:2];

// Lower-level multipliers
mul_2x2 #(.APPROX(APPROX_0)) ALxBL
    (.i_a(AL), .i_b(BL), .o_ab(acc_ALxBL));

mul_2x2 #(.APPROX(APPROX_1)) ALxBH
    (.i_a(AL), .i_b(BH), .o_ab(acc_ALxBH));

mul_2x2 #(.APPROX(APPROX_2)) AHxBL
    (.i_a(AH), .i_b(BL), .o_ab(acc_AHxBL));

mul_2x2 #(.APPROX(APPROX_3)) AHxBH
    (.i_a(AH), .i_b(BH), .o_ab(acc_AHxBH));

// ---------------------
// Partial Sums
// ---------------------

// First Block:               LSBs          +      LSBs         +     MSBs
assign partial1 	    = acc_ALxBH[1:0]    + acc_AHxBL[1:0]    + acc_ALxBL[3:2];

// Second Block:             Carry          +      LSBs         +     MSBs          +      MSBs
assign partial2	        = partial1[3:2]     + acc_AHxBH[1:0]    + acc_ALxBH[3:2]    + acc_AHxBL[3:2];

// Third Block:               MSBs          +      Carry
assign partial3         = acc_AHxBH[3:2]    + partial2[3:2];

// ---------------------
// Outputs
// ---------------------

assign o_ab = {partial3[1:0], partial2[1:0], partial1[1:0], acc_ALxBL[1:0]};

endmodule
