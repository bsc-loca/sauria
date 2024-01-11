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

module sa_array #(
    parameter ARITHMETIC = 0,
	parameter MUL_TYPE = 0,         
	parameter M_APPROX = 0,
	parameter MM_APPROX = 0,
	parameter ADD_TYPE = 0,         
	parameter A_APPROX = 0,       	
	parameter AA_APPROX = 0,  
    parameter X = 3,
    parameter Y = 3,
    parameter IA_W = 16,
    parameter IB_W = 16,
    parameter OC_W = 48,
    parameter TH_W = 2,
	parameter STAGES_MUL = 2,
    parameter INTERMEDIATE_PIPELINE_STAGE = 1,
    parameter ZERO_GATING_MULT = 1,
    parameter ZERO_GATING_ADD = 1,
    parameter ZD_LOOKAHEAD = 1,
    parameter EXTRA_CSREG = 0
)(
    // Clk, RST
	input logic 				        i_clk,
	input logic					        i_rstn,

	// Data Inputs
    input  logic [0:Y-1][IA_W-1:0]      i_a_arr,	        // Activation operands
	input  logic [0:X-1][IB_W-1:0]	    i_b_arr,	        // Weight operands
	input  logic [0:Y-1][OC_W-1:0] 	    i_c_arr,	        // MAC inputs (preload / out chain)
	
	// Control Inputs
    input logic                         i_reg_clear,        // PE Register clear
	// input logic	[0:X-1]				i_cell_en_arr,      // [UNUSED] Cell enable scan-chains (for PE deactivation)
	// input logic					    i_cell_sc_en,       // [UNUSED] Scan enable (to propagate i_cell_en_arr)
    input logic					        i_pipeline_en,      // Global pipeline enable (for stalls)
    input logic	[0:X-1]				    i_cswitch_arr,      // Accumulator context switches
    input logic					        i_cscan_en,         // Output Scanchains Enable
    input logic [TH_W-1:0]              i_thres,            // Threshold for bit negligence in zero detection

	// Data Outputs
	output  logic [0:Y-1][OC_W-1:0]  	o_c_arr             // MAC outputs (preload / out chain)
);

// ----------
// SIGNALS
// ----------

logic [0:Y-1][0:X][IA_W-1:0]   	mat_A;
logic [0:Y][0:X-1][IB_W-1:0]	mat_B;
logic [0:Y-1][0:X][OC_W-1:0]	mat_C;

logic [0:Y][0:X-1]              mat_cswitch;
logic [0:Y][0:X-1]              mat_cell_en;

// ------------
// IO Mapping
// ------------

// Left mappings: along y dimension
genvar jj;
    generate
        for (jj=0; jj < Y; jj++) begin : y_ios

            assign mat_A[jj][0] = i_a_arr[jj];      // Activation inputs
            assign mat_C[jj][X] = i_c_arr[jj];      // Output Scan Chain inputs (preload)

            assign o_c_arr[jj] = mat_C[jj][0];      // Output Scan Chain outputs

        end
    endgenerate

// Top and bottom mappings: along x dimension
genvar ii;
    generate
        for (ii=0; ii < X; ii++) begin : x_ios

            assign mat_B[0][ii] = i_b_arr[ii];                  // Weight inputs
            assign mat_cswitch[0][ii] = i_cswitch_arr[ii];      // Context switch inputs
            //assign mat_cell_en[0][ii] = i_cell_en_arr[ii];    // [UNUSED] Cell Scan Chain inputs

        end
    endgenerate

// -------------------
// PE Instantiation
// -------------------

genvar i,j;
    generate
        for (j=0; j < Y; j++) begin : y_axis
			for (i=0; i < X; i++) begin : x_axis

                sa_processing_element #(
                    .ARITHMETIC(ARITHMETIC),
                    .MUL_TYPE(MUL_TYPE),
                    .M_APPROX(M_APPROX),
                    .MM_APPROX(MM_APPROX),
                    .ADD_TYPE(ADD_TYPE),
                    .A_APPROX(A_APPROX),
                    .AA_APPROX(AA_APPROX),
                    .IA_W(IA_W),
                    .IB_W(IB_W),
                    .OC_W(OC_W),
                    .TH_W(TH_W),
                    .STAGES_MUL(STAGES_MUL),
                    .INTERMEDIATE_PIPELINE_STAGE(INTERMEDIATE_PIPELINE_STAGE),
                    .ZERO_GATING_MULT(ZERO_GATING_MULT),
                    .ZERO_GATING_ADD(ZERO_GATING_ADD),
                    .ZD_LOOKAHEAD(ZD_LOOKAHEAD),
                    .EXTRA_CSREG(EXTRA_CSREG)
                ) sa_processing_element_i (
                    .i_clk		    (i_clk),
                    .i_rstn		    (i_rstn),

                    .i_a		    (mat_A[j][i]),          
                    .i_b		    (mat_B[j][i]),
                    .i_c		    (mat_C[j][i+1]),        // C input comes from the right

                    .i_thres        (i_thres),

                    .i_reg_clear    (i_reg_clear),
                    .i_cell_en		(1'b1),                 // [UNUSED]
                    .i_cell_sc_en   (1'b1),                 // [UNUSED]
                    .i_pipeline_en	(i_pipeline_en),
                    .i_cswitch		(mat_cswitch[j][i]),
                    .i_cscan_en		(i_cscan_en),

                    .o_cswitch		(mat_cswitch[j+1][i]),  // Propagates to the bottom
                    .o_cell_en		(),                     // [UNUSED] Propagates to the bottom

                    .o_a		    (mat_A[j][i+1]),        // Propagates to the right
                    .o_b		    (mat_B[j+1][i]),        // Propagates to the bottom
                    .o_c		    (mat_C[j][i]));         // Propagates from right to left (current idx)

            end
        end
    endgenerate

endmodule
