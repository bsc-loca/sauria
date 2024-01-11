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

module sa_processing_element #(
    parameter ARITHMETIC = 0,
	parameter MUL_TYPE = 0,         
	parameter M_APPROX = 0,
	parameter MM_APPROX = 0,
	parameter ADD_TYPE = 0,         
	parameter A_APPROX = 0,       	
	parameter AA_APPROX = 0,  
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
	input logic 				i_clk,
	input logic					i_rstn,

	// Data Inputs
    input  logic [IA_W-1:0]   	i_a,	// Activation operand
	input  logic [IB_W-1:0]		i_b,	// Weight operand
	input  logic [OC_W-1:0] 	i_c,	// MAC input (preload / out chain)
	
	// Control Inputs
    input logic                 i_reg_clear,    // Register clear
	input logic					i_cell_en,      // Cell enable (for PE deactivation)
	input logic					i_cell_sc_en,   // Cell enable scan-chain (to propagate i_cell_en)
    input logic					i_pipeline_en,  // Global pipeline enable (for stalls)
    input logic					i_cswitch,      // Accumulator context switch
    input logic					i_cscan_en,     // Output Scanchain Enable

    input logic [TH_W-1:0]      i_thres,        // Threshold for bit negligence in zero detection
	
	// Control Outputs
	output  logic               o_cswitch, 	// Activation output
    output  logic               o_cell_en, 	// Weight output

	// Data Outputs
	output  logic [IA_W-1:0]  	o_a, 	// Activation output
    output  logic [IB_W-1:0]  	o_b, 	// Weight output
	output  logic [OC_W-1:0]  	o_c 	// MAC output (preload / out chain)
);

// ----------
// SIGNALS
// ----------

localparam ZERO_DETECTOR = ZERO_GATING_MULT | ZERO_GATING_ADD;
localparam MUL_W = (ARITHMETIC == 0)? (IA_W + IB_W) : OC_W;

// Control
logic pipeline_ff_en;

// Propagation pipeline registers
logic [IA_W-1:0] a_q;
logic [IB_W-1:0] b_q;
logic            cswitch_q;
logic            cell_en_q;

// Extra cswitch register
logic            cswitch_q_ext;

// Computation and outputs
logic               mul_mux_sel;
logic [MUL_W-1:0]   mul_d, mul_q, mul_q_zd;
logic [OC_W-1:0]    mac_d, mac_q, mac_q_mux, mac_q_zd;

// Zero detection
logic                   zero_det_d, zero_det_q0, zero_det_q1;
logic                   zd_lookahead;
logic                   acc_read_en;
logic [STAGES_MUL:0]    zero_det_q_shim;    // Shimming registers parallel to multiplier pipeline
logic [IA_W-1:0]        a_zd_q;
logic [IB_W-1:0]        b_zd_q;
logic [OC_W-1:0]        mhold_q;

// Accumulator context switch and output chain
logic [OC_W-1:0]        mac_sc_d, mac_sc_q;
logic                   sc_reg_en;

// ----------
// Control
// ----------

assign pipeline_ff_en = i_cell_en & i_pipeline_en;

// -------------------
// Computation Units
// -------------------

generate

    // ***********************
    //  INTEGER ARITHMETIC
    // ***********************
    if (ARITHMETIC == 0) begin

        // MULTIPLIER
        multiplier_generic #(
                .MUL_TYPE(MUL_TYPE),
                .M_APPROX(M_APPROX),
                .MM_APPROX(MM_APPROX),
                .SIGNED(1'b1),
                .STAGES(STAGES_MUL),
                .IA_W(IA_W),
                .IB_W(IB_W)
            ) multiplier_i
                (.i_clk		(i_clk),
                .i_rstn		(i_rstn && (!i_reg_clear)),
                .i_en_ff    (pipeline_ff_en),
                .i_a		(a_zd_q),
                .i_b		(b_zd_q),
                .o_prod		(mul_d));
            
        // ADDER
        adder_generic #(
                .ADD_TYPE(ADD_TYPE),
                .A_APPROX(A_APPROX),
                .AA_APPROX(AA_APPROX),
                .IP_W(MUL_W),
                .OC_W(OC_W)
            ) adder_i
                (.i_p		(mul_q_zd),
                .i_c		(mac_q_zd),
                .i_carry    (1'b0),
                .o_c		(mac_d));

    // ***********************
    //  FP ARITHMETIC
    // ***********************
    end else begin

        fma_wrapper #(
            .MUL_TYPE(MUL_TYPE),
            .M_APPROX(M_APPROX),
            .MM_APPROX(MM_APPROX),
            .ADD_TYPE(ADD_TYPE),
            .A_APPROX(A_APPROX),
            .AA_APPROX(AA_APPROX),
            .STAGES(STAGES_MUL),
            .INTERMEDIATE_PIPELINE_STAGE(INTERMEDIATE_PIPELINE_STAGE),
            .ZERO_GATING_MULT(ZERO_GATING_MULT),
            .FP_W(IA_W)
        ) fma_i
            (.i_clk		        (i_clk),
            .i_rstn		        (i_rstn && (!i_reg_clear)),
            .i_a		        (a_zd_q),
            .i_b		        (b_zd_q),
            .i_c                (mac_q_zd),
            .i_msel             (mul_mux_sel),
            .i_pipeline_en      (pipeline_ff_en),
            .o_c		        (mac_d));

    end

endgenerate

// ----------------------------------------------------------------
// Extra cswitch pipeline stage (PARAM-CONTROLLED)
// ----------------------------------------------------------------

generate
    // Generate extra register stage if requested
    if(EXTRA_CSREG == 1) begin

        always_ff @(posedge i_clk or negedge i_rstn) begin : prop_reg
            if(~i_rstn) begin
                cswitch_q_ext <= 0;
            end else begin

                // Synchronous reset
                if (i_reg_clear) begin
                    cswitch_q_ext <= 0;
                end else if(pipeline_ff_en) begin
                    cswitch_q_ext <= i_cswitch;
                end
            end
        end

    // Otherwise just shortcircuit the signal
    end else begin
        assign cswitch_q_ext = i_cswitch;
    end
endgenerate


// ----------------------------------------------------------------
// Zero detector (PARAM-CONTROLLED)
// ----------------------------------------------------------------

generate
    if(ZERO_DETECTOR == 1) begin

        // Zero detection & bit negligence block
        zero_det_neg #(
            .IA_W(IA_W),
            .IB_W(IB_W),
            .TH_W(TH_W)
        ) zero_det_neg_i
        (.i_a		    (i_a),
            .i_b		    (i_b),
            .i_thres	    (i_thres),
            .o_zero_det		(zero_det_d));

        // We also need one pipeline reg here for the zd signal
        always_ff @(posedge i_clk or negedge i_rstn) begin : zd_reg0
            if(~i_rstn) begin
                zero_det_q0 <= 0;
            end else begin

                // Synchronous reset
                if (i_reg_clear) begin
                    zero_det_q0 <= 0;
                end else if(pipeline_ff_en) begin
                    zero_det_q0 <= zero_det_d;
                end
            end
        end
    end
endgenerate

// ----------------------------------------------------------------
// Zero gating for multiplier (PARAM-CONTROLLED)
// ----------------------------------------------------------------

generate
    if(ZERO_GATING_MULT == 1) begin

        // Gated registers -> Ignore inputs if zero detection to avoid switching
        always_ff @(posedge i_clk or negedge i_rstn) begin : sil_reg
            if(~i_rstn) begin
                a_zd_q <= 0;
                b_zd_q <= 0;
            end else begin

                // Synchronous reset
                if (i_reg_clear) begin
                    a_zd_q <= 0;
                    b_zd_q <= 0;
                end else if ((pipeline_ff_en) && !(zero_det_d)) begin
                    a_zd_q <= i_a;
                    b_zd_q <= i_b;
                end
            end
        end

    end else begin
        // In case macro is deactivated, shortcircuit all external wires
        assign a_zd_q = i_a;
        assign b_zd_q = i_b;
    end
endgenerate

// -------------------------------------------------------------------------
// Zero gating signal propagation -> Shimming registers (PARAM-CONTROLLED)
// -------------------------------------------------------------------------

genvar k;
generate
    // Generate shimming registers
    if(ZERO_DETECTOR == 1) begin

        // If there is some pipelining in mult
        if (STAGES_MUL>0) begin
            // We define a loop to create many -> Index 0 is only used if STAGES_MUL=0, otherwise disconnected
            for (k=1; k<STAGES_MUL+1; k=k+1) begin
                // Each element is a simple FF
                always_ff @(posedge i_clk or negedge i_rstn) begin : buff_reg
                    if(~i_rstn) begin
                        zero_det_q_shim[k] <= 0;
                    end else begin

                        // Synchronous reset
                        if (i_reg_clear) begin
                            zero_det_q_shim[k] <= 0;
                        end else if(pipeline_ff_en) begin
                            // First FF is a little special
                            if (k==1) begin
                                zero_det_q_shim[1] <= zero_det_q0;
                            // The others just take the previous output
                            end else begin
                                zero_det_q_shim[k] <= zero_det_q_shim[k-1];
                            end
                        end
                    end
                end
            end

        // Otherwise just assign the 0th and only bit
        end else begin
            assign zero_det_q_shim[0] = zero_det_q0;
        end
    end
endgenerate

// ----------------------------------------------------------
// Pipeline stage between Mult and Add (PARAM-CONTROLLED)
// ----------------------------------------------------------

generate
    if(INTERMEDIATE_PIPELINE_STAGE == 1) begin

        // Instantiate Data Register only when Integer Type, otherwise it is internal
        if (ARITHMETIC == 0) begin
            always_ff @(posedge i_clk or negedge i_rstn) begin : mul_reg
                if(~i_rstn) begin
                    mul_q <= 0;
                end else begin

                    // Synchronous reset
                    if (i_reg_clear) begin
                        mul_q <= 0;
                    end else if(pipeline_ff_en) begin
                        mul_q <= mul_d;
                    end
                end
            end
        end

        // If zero gating is wanted, we also need a pipeline reg
        if(ZERO_DETECTOR == 1) begin
            always_ff @(posedge i_clk or negedge i_rstn) begin : zd_reg1
                if(~i_rstn) begin
                    zero_det_q1 <= 0;
                end else begin

                    // Synchronous reset
                    if (i_reg_clear) begin
                        zero_det_q1 <= 0;
                    end else if(pipeline_ff_en) begin
                        zero_det_q1 <= zero_det_q_shim[STAGES_MUL];
                    end
                end
            end
        end

    end else begin
    // In case macro is deactivated, shortcircuit all external wires
        assign mul_q = mul_d;
        assign zero_det_q1 = zero_det_q_shim[STAGES_MUL];
    end
endgenerate

// ----------------------------------------------------------------
// Zero gating in last pipeline stage (PARAM-CONTROLLED)
// ----------------------------------------------------------------

generate
    if(ZERO_DETECTOR == 1) begin

        // Bit indicating multiplier MUX selection
        assign mul_mux_sel = zero_det_q1 && cswitch_q_ext;

        // Instantiate Multiplication Mux only when Integer Type, otherwise it is internal
        if (ARITHMETIC == 0) begin
            // If ZD and context switch at the same time, we have no choice but to make it zero
            assign mul_q_zd = (mul_mux_sel) ? 0 : mul_q;
        end

        // Accumulator can ignore input (0) when zero_det_q1 is high, but only if i_cswitch is zero!
        assign acc_read_en = pipeline_ff_en & (cswitch_q_ext | (~zero_det_q1));

    end else begin
        // In case macro is deactivated, shortcircuit all external wires
        assign mul_q_zd = mul_q;
        assign acc_read_en = pipeline_ff_en;
    end
endgenerate

// ----------------------------------------------------------------
// Zero gating for adder (PARAM-CONTROLLED)
// ----------------------------------------------------------------

generate
    if(ZERO_GATING_ADD == 1) begin

        // Lookahead is used to enable the mhold_q register only when the NEXT cycle will have a zero
        if(ZD_LOOKAHEAD == 1) begin

            // If we have a stage between mult and add, just take the point before that
            if(INTERMEDIATE_PIPELINE_STAGE == 1) begin
                assign zd_lookahead = zero_det_q_shim[STAGES_MUL];

            // If no intermediate stage, we need to go to previous stages
            end else begin
                
                // If the multiplier has some internal stages, just take the second-to-last shimming reg
                if (STAGES_MUL>0) begin
                    assign zd_lookahead = zero_det_q_shim[STAGES_MUL-1];

                // If the multiplier has no internal stages, we must take the first and only available, zero_det_d
                end else begin
                    assign zd_lookahead = zero_det_d;
                end
            end

        // If lookahead is not used, just enable the register always
        end else begin
            assign zd_lookahead = 1;
        end

        // To avoid switching when the value is zero, we save the last mac_q_zd in mhold_q
        always_ff @(posedge i_clk or negedge i_rstn) begin : mhold_reg
            if(~i_rstn) begin
                mhold_q <= 0;
            end else begin

                // Synchronous reset
                if (i_reg_clear) begin
                    mhold_q <= 0;
                end else if(zd_lookahead) begin
                    mhold_q <= mac_q_zd;
                end
            end
        end

        // If ZD and not i_cswitch, we take last value, otherwise we always take proper mac_q_mux.
        assign mac_q_zd = (zero_det_q1 && (!cswitch_q_ext)) ? mhold_q : mac_q_mux;

    end else begin
        // In case macro is deactivated, shortcircuit all external wires
        assign mac_q_zd = mac_q_mux;
    end
endgenerate

// --------------------------------------
// Local Accumulator + context switch
// --------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : acc_reg
	if(~i_rstn) begin
		mac_q <= 0;
	end else begin

        // Synchronous reset
        if (i_reg_clear) begin
            mac_q <= 0;
        end else if(acc_read_en) begin
		    mac_q <= mac_d;
        end
	end
end

assign mac_q_mux = (cswitch_q_ext) ? mac_sc_q : mac_q;

// --------------------------------------
// Output Scan Chain + context switch
// --------------------------------------

assign sc_reg_en = (i_cscan_en | cswitch_q_ext ) & i_pipeline_en;

assign mac_sc_d = (cswitch_q_ext) ? mac_q : i_c;

// Output SC register
always_ff @(posedge i_clk or negedge i_rstn) begin : sc_reg
	if(~i_rstn) begin
		mac_sc_q <= 0;
	end else begin

        // Synchronous reset
        if (i_reg_clear) begin
            mac_sc_q <= 0;
        end else if(sc_reg_en) begin
		    mac_sc_q <= mac_sc_d;
        end
	end
end

// -------------------------------
// Propagation Pipeline Registers
// -------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : prop_reg
	if(~i_rstn) begin
		a_q <= 0;
		b_q <= 0;
        cswitch_q <= 0;
	end else begin

        // Synchronous reset
        if (i_reg_clear) begin
            a_q <= 0;
            b_q <= 0;
            cswitch_q <= 0;
        end else if(pipeline_ff_en) begin
		    a_q <= i_a;
		    b_q <= i_b;
            cswitch_q <= i_cswitch;
        end
	end
end

// --------------------------------
// Cell Enable scan chain register
// --------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : cell_en_reg
	if(~i_rstn) begin
		cell_en_q <= 0;
	end else begin
        // Synchronous reset
        if (i_reg_clear) begin
            cell_en_q <= 0;
        end else if(i_cell_sc_en) begin
		    cell_en_q <= i_cell_en;
        end
	end
end

// -------------------
// Outputs
// -------------------

assign o_a = a_q;
assign o_b = b_q;
assign o_c = mac_sc_q;

assign o_cswitch = cswitch_q;
assign o_cell_en = cell_en_q;

endmodule
