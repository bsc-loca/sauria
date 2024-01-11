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

module multiplier_log #(
    parameter APPROX_TYPE = 0,
    parameter M_APPROX = 3,
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

// Sign management (for sign operation only)
logic a_sign, b_sign, prod_sign;

// Multiplier inputs (unsigned)
logic [IA_W-1:0]    a, a_shifted;
logic [IB_W-1:0]    b, b_shifted;

// Characteristic parts of operands
localparam KA_W = $clog2(IA_W);
localparam KB_W = $clog2(IB_W);

logic [KA_W-1:0]    ka;
logic [KB_W-1:0]    kb;

// Mantissa parts of operands
logic [KA_W-1:0]    xa_shamt;
logic [KB_W-1:0]    xb_shamt;

logic [IA_W-2:0]    xa;
logic [IB_W-2:0]    xb;

// Log-space operands
localparam LOG_W = `max2(KA_W+IA_W-1, KB_W+IB_W-1);
logic [LOG_W-1:0]   log_a, log_b;

// Log-space product
logic [LOG_W:0]     log_prod;

// Characteristic and mantissa of product
localparam KP_W = `max2(KA_W, KB_W)+1;
localparam XP_W = `max2(IA_W, IB_W)-1;

logic [KP_W-1:0]    kprod;
logic [XP_W-1:0]    xprod;

// Shift amount for result
logic [KP_W-1:0]    prod_shamt;

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

// -----------------------
// LEADING-ONE DETECTORS
// -----------------------

// Characteristic part is directly the leading one position
lopd #(
    .I_W(IA_W)
) lopd_a (
    .i_d(a),
    .o_d(ka)
);

lopd #(
    .I_W(IB_W)
) lopd_b (
    .i_d(b),
    .o_d(kb)
);

// -----------------------
// MANTISSA SHIFTING
// -----------------------

// Shift amounts: first bit after the leading one must be MSB of mantissa
assign xa_shamt = IA_W - ka;
assign xb_shamt = IB_W - kb;

// Mantissa shifting
assign a_shifted = (a << xa_shamt);
assign b_shifted = (b << xb_shamt);

// Discard LSB (direct assignment discards MSB)
assign xa = a_shifted[IA_W-1:1];
assign xb = b_shifted[IB_W-1:1];

// -----------------------
// LOGARITHMIC OPERANDS
// -----------------------

assign log_a = {ka, xa};
assign log_b = {kb, xb};

// -----------------------
// PRODUCT (LOG ADDITION)
// -----------------------


generate
    
    // EXACT ADDER
    if (APPROX_TYPE==0) begin : exact_log_addition

        assign log_prod = log_a + log_b;

    // SOA
    end else if (APPROX_TYPE==1) begin : soa_log_addition

        logic soa_carry_in;

        // Lower bits fixed to 1
        assign log_prod[M_APPROX-1:0] = '1;

        // Carry in with last bit
        assign soa_carry_in = log_a[M_APPROX-1] & log_b[M_APPROX-1];

        // Upper bits computed with exact adder
        assign log_prod[LOG_W:M_APPROX] = log_a[LOG_W-1:M_APPROX] + log_b[LOG_W-1:M_APPROX] + soa_carry_in;
    
    end

endgenerate

// Characteristic part and mantissa decomposition
assign kprod = log_prod[LOG_W:XP_W];
assign xprod = log_prod[XP_W-1:0];

// -----------------------
// RESULT DECODING
// -----------------------

always_comb begin : decoding
    
    // When the exponent is large, we must left-shift
    if (kprod>XP_W) begin
        
        prod_shamt = kprod - XP_W;
        product = (xprod << prod_shamt);

    // Otherwise we will have to right-shift
    end else begin
        
        prod_shamt = XP_W - kprod;
        product = (xprod >> prod_shamt);

    end

    // Set leading one
    product[kprod] = 1'b1;

end

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
