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

module multiplier_wallace #(
	parameter APPROX_TYPE = 0 ,         // Type of Approximate Structure (0 = Exact, 1 = Partially exact, 2 = Fully Aprox)
	parameter STAGES = 1,
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

logic sign_i_a, sign_i_b;
logic sign_out;

logic [IA_W-1:0]    abs_i_a;
logic [IB_W-1:0]    abs_i_b;

logic [15:0]        wallace_i_a, wallace_i_b;
logic [31:0]        wallace_out, wallace_out_signed;

logic [MUL_W-1:0]    prod_out;

// -------------------------------------------------------------------------
// Input signal mapping => The Wallace Tree is defined for 16-bit operands
// -------------------------------------------------------------------------

generate
    // Deal with signs only if SIGNED operation
    if (SIGNED) begin
        // Detect signs
        assign sign_i_a = i_a[IA_W-1];
        assign sign_i_b = i_b[IB_W-1];

        // Absolute value of A input => If input is negative, we invert
        assign abs_i_a = (sign_i_a)? (0 - i_a) : i_a;

        // Absolute value of B input => If input is negative, we invert
        assign abs_i_b = (sign_i_b)? (0 - i_b) : i_b;

        // Bit mapping of active bits
        assign wallace_i_a = {'0, abs_i_a[IA_W-2:0]};
        assign wallace_i_b = {'0, abs_i_b[IB_W-2:0]};

    // If unsigned operation, just short-circuit the signals
    end else begin
        assign sign_i_a = 0;
        assign sign_i_b = 0;
        assign abs_i_a = i_a;
        assign abs_i_b = i_b;
        assign wallace_i_a = {'0, abs_i_a[IA_W-1:0]};
        assign wallace_i_b = {'0, abs_i_b[IB_W-1:0]};
    end
endgenerate

// ----------------------------
// Wallace Tree Instantiation
// ----------------------------

wallace_16 #(
    .APPROX_TYPE (APPROX_TYPE)
) wallace_16_i (
    .i_a		    (wallace_i_a),          
    .i_b		    (wallace_i_b),

    .o_ab           (wallace_out));

// -------------------------------------------------------------------------
// Output sign logic & Output conversion
// -------------------------------------------------------------------------

generate
    // Deal with signs only if SIGNED operation
    if (SIGNED) begin

        // Output operand sign
        assign sign_out = sign_i_a ^ sign_i_b;

        // Sign of output => If negative, we invert
        assign wallace_out_signed = (sign_out)? (0 - wallace_out) : wallace_out;

        // MSB bit maintained for sign
        assign prod_out = {wallace_out_signed[31], wallace_out_signed[MUL_W-2:0]};

    // If unsigned operation, just short-circuit the signals
    end else begin
        assign sign_out = 0;
        assign wallace_out_signed = wallace_out;
        assign prod_out = wallace_out_signed[MUL_W-1:0];
    end
endgenerate

// ---------------------
// Outputs
// ---------------------

assign o_prod = prod_out;

endmodule
