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

module adder_generic #(
    parameter ADD_TYPE = 0,
    parameter A_APPROX = 0,
    parameter AA_APPROX = 0,
    parameter IP_W = 16,
    parameter OC_W = 16
)(
	// Data Inputs
    input  logic [IP_W-1:0]   	i_p,
    input  logic [OC_W-1:0]		i_c,
    input  logic                i_carry,
		
	// Data Outputs 
	output logic [OC_W-1:0]  	o_c 	// MAC output
);

// ------------------------
// CONDITIONAL GENERATION
// ------------------------

generate

    // *********************************************************************
    // ADD TYPE 0 => Directly instantiated Exact Adder
    // *********************************************************************

    if (ADD_TYPE == 0) begin

        adder_ideal #(
                .IP_W(IP_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(i_p),
                .i_c		(i_c),
                .i_carry    (i_carry),
                .o_c		(o_c));

    // *************************************************************
    // ADD TYPE 1 => GeAr
    // *************************************************************

    end else if (ADD_TYPE == 1) begin
        
        adder_gear #(
                .R(A_APPROX),
                .P(AA_APPROX),
                .IP_W(IP_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(i_p),
                .i_c		(i_c),
                .i_carry    (i_carry),
                .o_c		(o_c));

    // *************************************************************
    // ADD TYPE 1 => GeAr-p
    // *************************************************************

    end else if (ADD_TYPE == 2) begin
        
        adder_gear_2c #(
                .R(A_APPROX),
                .P(AA_APPROX),
                .IP_W(IP_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(i_p),
                .i_c		(i_c),
                .i_carry    (i_carry),
                .o_c		(o_c));

    // *************************************************************
    // ADD TYPE 2 => TruA
    // *************************************************************

    end else if (ADD_TYPE == 3) begin
        
        adder_trua #(
                .A_APPROX(A_APPROX),
                .IP_W(IP_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(i_p),
                .i_c		(i_c),
                .i_carry    (i_carry),
                .o_c		(o_c));

    // *************************************************************
    // ADD TYPE 3 => TruA-H
    // *************************************************************

    end else if (ADD_TYPE == 4) begin
        
        adder_truah #(
                .A_APPROX(A_APPROX),
                .IP_W(IP_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(i_p),
                .i_c		(i_c),
                .i_carry    (i_carry),
                .o_c		(o_c));

    // *************************************************************
    // ADD TYPE 4 => LOA
    // *************************************************************

    end else if (ADD_TYPE == 5) begin
        
        adder_loa #(
                .A_APPROX(A_APPROX),
                .IP_W(IP_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(i_p),
                .i_c		(i_c),
                .i_carry    (i_carry),
                .o_c		(o_c));

    end

endgenerate

endmodule
