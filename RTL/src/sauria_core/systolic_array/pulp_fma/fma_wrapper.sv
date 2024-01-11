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

module fma_wrapper #(
	parameter MUL_TYPE = 0,         
	parameter M_APPROX = 0,
	parameter MM_APPROX = 0,
	parameter ADD_TYPE = 0,         
	parameter A_APPROX = 0,       	
	parameter AA_APPROX = 0,  
	parameter STAGES = 0,
    parameter INTERMEDIATE_PIPELINE_STAGE = 1,
    parameter ZERO_GATING_MULT = 1,
	parameter FP_W = 16
)(
    // Clk, RST
	input logic 				i_clk,
	input logic					i_rstn,

	// Data Inputs
    input  logic [FP_W-1:0]   	i_a,	// Activation operand
	input  logic [FP_W-1:0]		i_b,	// Weight operand
	input  logic [FP_W-1:0] 	i_c,	// MAC input
	
	// Control Inputs
	input logic					i_msel,         // Adder Mux select signal (only if zero gating)
    input logic					i_pipeline_en,  // Global pipeline enable (for stalls)

	// Data Outputs
	output  logic [FP_W-1:0]  	o_c 	// MAC output
);

// ----------
// SIGNALS
// ----------

// Parameters
localparam fpnew_pkg::fp_format_e 	FpFormat = fpnew_pkg::fp_format_e'(2);
localparam int unsigned 			WIDTH = fpnew_pkg::fp_width(FpFormat); // do not change
localparam fpnew_pkg::pipe_config_t PipeConfig = fpnew_pkg::BEFORE;

// Input Operands
logic [2:0][WIDTH-1:0] 		operands;

// Output Value
logic [WIDTH-1:0]         	result;

// ---------------
// IO Adaptation
// ---------------

assign operands[0] = i_a;	// Adder Operand 1
assign operands[1] = i_b;	// Adder Operand 2
assign operands[2] = i_c;	// Adder Operand 3

assign o_c = result;

// ----------------------
// Module Instantiation
// ----------------------

fpnew_fma #(
	.FpFormat(FpFormat),
	.NumPipeRegs(STAGES),
	.PipeConfig(PipeConfig),
	.TagType(logic),
	.AuxType(logic),

  	// ++++++++++++++++++
	// Start New params
	// ++++++++++++++++++
	.MUL_TYPE(MUL_TYPE),
	.M_APPROX(M_APPROX),
	.MM_APPROX(MM_APPROX),
	.ADD_TYPE(ADD_TYPE),
	.A_APPROX(A_APPROX),
	.AA_APPROX(AA_APPROX),
	.ZERO_GATING_MULT(ZERO_GATING_MULT),
	.INTERMEDIATE_PIPELINE_STAGE(INTERMEDIATE_PIPELINE_STAGE)
	// +++++++++++++++++
	// End New params
	// +++++++++++++++++

) fma_i
	(.clk_i		        (i_clk),
	.rst_ni		        (i_rstn),
	.operands_i			(operands),
	.is_boxed_i 		(3'b111),				// 3'b111 => All inputs are boxed
	.rnd_mode_i			(fpnew_pkg::RNE),		// RTZ = Round to zero; RNE => Round to nearest
	.op_i				(fpnew_pkg::FMADD),		// FMADD always
	.op_mod_i			(1'b0),					// 0 => No sign inversion for operand C
	.tag_i				(1'b0),					// Tag = 0
	.aux_i				(1'b0),					// Aux = 0
	.in_valid_i			(1'b1),					// Always valid inputs
	.flush_i			(1'b0),					// We never flush
	.out_ready_i		(1'b1),					// Output always ready 

	// ++++++++++++++++++
	// Start New inputs
	// ++++++++++++++++++
	.msel_i 			(i_msel),			// Adder Mux Sel
	.pipeline_en_i		(i_pipeline_en),	// Pipeline Enable
	// +++++++++++++++++
	// End New inputs
	// +++++++++++++++++

	.result_o		    (result),		
	.in_ready_o		    (),				// We don't use any other outputs
	.status_o           (),
	.extension_bit_o    (),
	.tag_o      		(),
	.aux_o      		(),
	.out_valid_o      	(),
	.busy_o      		());

endmodule
