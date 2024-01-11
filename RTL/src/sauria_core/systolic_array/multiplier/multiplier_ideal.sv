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

module multiplier_ideal #(
    parameter SIGNED = 0,
	parameter STAGES = 0,   // Internal pipeline stages
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

// Must typecast for int interpretation of the operands
logic signed [IA_W-1:0] a;
logic signed [IB_W-1:0] b;

logic signed [MUL_W-1:0] prod_d;
logic [0:STAGES][MUL_W-1:0] buff;        // Pipeline registers

// ---------------------
// Combinational part
// ---------------------

assign a = i_a;
assign b = i_b;

generate
    
    if (SIGNED==1) begin

        // EXACT SUM
        assign prod_d = a * b;

    // Leave as logic when not needed
    end else begin

        // EXACT SUM
        assign prod_d = i_a * i_b;

    end
    
endgenerate

// ---------------------------------------------------------------
// Pipeline registers (emulated as an output chain of registers)
// ---------------------------------------------------------------

assign buff[0] = prod_d;

genvar k;
generate
    // Generate one instance per position
    for (k=1; k < STAGES+1; k++) begin
        // Normal FF behavior
        always_ff @(posedge i_clk or negedge i_rstn) begin : a_b_reg
            if(~i_rstn) begin
                buff[k] <= 0;
            end else begin
                if (i_en_ff) begin
                    buff[k] <= buff[k-1];
                end
            end
        end
    end
endgenerate

// -------------------
// Outputs
// -------------------

generate
    // Assign output to the last pipeline stage
    if (STAGES>0) begin
        assign o_prod = buff[STAGES];
    end
    // Just shortcircuit the signal if K=0
    else begin
        assign o_prod = prod_d;
    end
endgenerate

endmodule
