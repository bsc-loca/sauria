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

module multiplier_generic #(
    parameter MUL_TYPE = 0,
    parameter STAGES = 0,
    parameter SIGNED = 0,
    parameter M_APPROX = 0,
    parameter MM_APPROX = 0,
    parameter IA_W = 16,
    parameter IB_W = 16,
    localparam MUL_W = IA_W+IB_W
)(
    // Clk, RST
	input logic 				i_clk,
    input logic                 i_en_ff,
	input logic					i_rstn,

	// Data Inputs
    input  logic [IA_W-1:0]   	i_a,
	input  logic [IB_W-1:0]		i_b,
		
	// Data Outputs 
	output logic [MUL_W-1:0]  	o_prod
);

// ------------------------
// CONDITIONAL GENERATION
// ------------------------

generate

    // *********************************************************************
    // MULT TYPE 0 => Inferred Exact Multiplier
    // *********************************************************************

    if (MUL_TYPE == 0) begin

        // MULTIPLIER
        multiplier_ideal #(
                .SIGNED(SIGNED),
                .STAGES(STAGES),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 1 => Exact Wallace Multiplier
    // *************************************************************

    end else if (MUL_TYPE == 1) begin
        
        // MULTIPLIER
        multiplier_wallace #(
                .APPROX_TYPE(0),
                .SIGNED(SIGNED),
                .STAGES(STAGES),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 2 => Partial UDM Wallace Multiplier
    // *************************************************************

    end else if (MUL_TYPE == 2) begin
        
        // MULTIPLIER
        multiplier_wallace #(
                .APPROX_TYPE(1),
                .SIGNED(SIGNED),
                .STAGES(STAGES),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 3 => Full UDM Wallace Multiplier
    // *************************************************************

    end else if (MUL_TYPE == 3) begin
        
        // MULTIPLIER
        multiplier_wallace #(
                .APPROX_TYPE(2),
                .SIGNED(SIGNED),
                .STAGES(STAGES),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 4 => RADIX-4 EXACT BOOTH MULTIPLIER
    // *************************************************************

    end else if (MUL_TYPE == 4) begin

        // BOOTH MULTIPLIER INSTANTIATION
        multiplier_booth #(
                .APPROX_TYPE(0),
                .SIGNED(SIGNED),
                .M_APPROX(M_APPROX),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 5 => RADIX-4 APPROXIMATE BOOTH MULTIPLIER - M1
    // *************************************************************

    end else if (MUL_TYPE == 5) begin

        // BOOTH MULTIPLIER INSTANTIATION
        multiplier_booth #(
                .APPROX_TYPE(1),
                .SIGNED(SIGNED),
                .M_APPROX(M_APPROX),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 6 => RADIX-4 APPROXIMATE BOOTH MULTIPLIER - M3
    // *************************************************************

    end else if (MUL_TYPE == 6) begin

        // BOOTH MULTIPLIER INSTANTIATION
        multiplier_booth #(
                .APPROX_TYPE(2),
                .SIGNED(SIGNED),
                .M_APPROX(M_APPROX),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 7 => LOGARITHMIC MULTIPLIER
    // *************************************************************

    end else if (MUL_TYPE == 7) begin

        // LOG MULTIPLIER INSTANTIATION
        multiplier_log #(
                .APPROX_TYPE(0),
                .SIGNED(SIGNED),
                .M_APPROX(M_APPROX),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 8 => APPROX LOGARITHMIC MULTIPLIER - SOA
    // *************************************************************

    end else if (MUL_TYPE == 8) begin

        // LOG MULTIPLIER INSTANTIATION
        multiplier_log #(
                .APPROX_TYPE(1),
                .SIGNED(SIGNED),
                .M_APPROX(M_APPROX),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    // *************************************************************
    // MULT TYPE 9 => BROKEN ARRAY MULTIPLIER
    // *************************************************************

    end else if (MUL_TYPE == 9) begin

        // BAM MULTIPLIER INSTANTIATION
        multiplier_bam #(
                .SIGNED(SIGNED),
                .VBL(M_APPROX),
                .HBL(MM_APPROX),
                .IA_W(IA_W),
                .IB_W(IB_W),
                .MUL_W(MUL_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn),
                .i_en_ff    (i_en_ff),
                .i_a		(i_a),
                .i_b		(i_b),
                .o_prod		(o_prod));

    end

endgenerate

endmodule
