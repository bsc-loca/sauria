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

module main_controller #(
    parameter X = 3,
    parameter Y = 3,
    parameter ACT_IDX_W = 11,
    parameter OUT_IDX_W = 11,
    parameter ACT_FIFO_POSITIONS = 8,
    parameter WEI_FIFO_POSITIONS = 8,
    parameter PE_LAT = 5,
    parameter EXTRA_CSREG = 0
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Soft reset signal
    input  logic                        i_soft_reset,

    // Control Inputs (Context FSM & cswitch control)
    input  logic                        i_start,            // Main Controller start flag => Starts a convolution
    input  logic                        i_outbuf_done,      // Done signal from output buffer
    input  logic                        i_finalwrite,       // Signals that next write is the last
    input  logic                        i_shift_done,       // First ready flag from output buffer

    // Control Inputs (Feeders FSM)
    input  logic [ACT_IDX_W-1:0]        i_incntlim,         // Input counter limit
    input  logic [OUT_IDX_W-1:0]        i_act_reps,         // Total activation data repetitions
    input  logic [OUT_IDX_W-1:0]        i_wei_reps,         // Total weight data repetitions
    input  logic                        i_act_done,         // Done flag from Activations
    input  logic                        i_act_til_done,     // Tiling Done flag from Activations
    input  logic                        i_act_fifo_empty, 	// FIFO empty flag from Activations
    input  logic                        i_act_fifo_full,    // FIFO full flag from Activations
    input  logic                        i_act_stall,        // Stall flag from Activations
    input  logic                        i_wei_done,	        // Done flag from Weights
    input  logic                        i_wei_til_done,	    // Tiling Done flag from Weights
    input  logic                        i_wei_fifo_empty, 	// FIFO empty flag from Weights
    input  logic                        i_wei_fifo_full,    // FIFO full flag from Weights
    input  logic                        i_wei_stall,        // Stall flag from Weights

	// Control Outputs (to Feeders)
    output  logic					    o_act_feeder_en,    // Enable for Row feeders
    output  logic                       o_act_feeder_clear, // Clear signal Row feeder buffers
    output  logic                       o_act_valid,        // Flag: valid inputs at feeder
    output  logic                       o_act_start,        // Flag: first inputs of current context
    output  logic                       o_act_finalpush,    // Flag: push of last buffer values
    output  logic                       o_act_cnt_en,       // Enable for counters
    output  logic                       o_act_cnt_clear,    // Clear signal for counters
    output  logic                       o_act_clearfifo,    // Clear signal for FIFO
    output  logic                       o_act_pop_en,       // FIFO pop enable
    output  logic                       o_act_finalctx,     // Final context flag for activation counters
    output  logic					    o_wei_feeder_en,    // Enable for Column feeders
    output  logic                       o_wei_feeder_clear, // Clear signal Column feeder buffers
    output  logic                       o_wei_valid,        // Flag: valid inputs at feeder
    output  logic                       o_wei_start,        // Flag: first inputs of current context
    output  logic                       o_wei_finalpush,    // Flag: push of last buffer values
    output  logic                       o_wei_cnt_en,       // Enable for counters
    output  logic                       o_wei_cnt_clear,    // Clear signal for counters
    output  logic                       o_wei_clearfifo,    // Clear signal for FIFO
    output  logic                       o_wei_pop_en,       // FIFO pop enable
    output  logic                       o_wei_cswitch,      // Context switch flag for weight counters

	// Control Outputs (Output Buffer)
    output  logic					    o_outbuf_start,     // Start flag for output buffer
    output  logic                       o_outbuf_reset,     // Output buffer state Reset

    // Control Outputs (to Array)
    output  logic                       o_sa_clear,         // Clear signal for SA internal registers
    output  logic                       o_pipeline_en,      // Pipeline Enable signal for Array and Feeders
    output  logic [0:X-1]               o_cswitch_arr,      // Array Accumulator context switches

    // Control Outputs (to Interface)
    output  logic                       o_feed_deadlock,    // Deadlock flag between feeders
    output  logic [4:0]                 o_ctx_status,       // Context FSM status
    output  logic [4:0]                 o_feed_status,      // Feeders FSM status
    output  logic                       o_done              // Finish flag
);

// ----------
// SIGNALS
// ----------

// Context FSM <-> Feeders FSM
logic   feeders_done, pipeline_gate, feeders_start, feeders_reset, pop_gate;

// Context FSM <-> Context Switch Controller
logic   cdone, cswitch_en, cswitch_force, cswitch_done, cswitch_cnt_clear;

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// Context FSM
context_fsm #(
    ) context_fsm_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_soft_reset   (i_soft_reset),
        
        .i_start	        (i_start),
        .i_outbuf_done      (i_outbuf_done),
        .i_cdone	        (cdone),
        .i_cswitch_done     (cswitch_done),
        .i_shift_done       (i_shift_done),
        .i_finalwrite       (i_finalwrite),
        .i_feeders_done     (feeders_done),
        .i_pipeline_en      (o_pipeline_en),

        .o_pipeline_gate    (pipeline_gate),
        .o_feeders_start    (feeders_start),
        .o_feeders_reset	(feeders_reset),
        .o_pop_gate	        (pop_gate),
        .o_outbuf_start     (o_outbuf_start),
        .o_outbuf_reset	    (o_outbuf_reset),
        .o_cswitch_en       (cswitch_en),
        .o_cswitch_force    (cswitch_force),
        .o_cswitch_cnt_clear(cswitch_cnt_clear),
        .o_sa_clear         (o_sa_clear),
        .o_ctx_status       (o_ctx_status),
        .o_done	            (o_done));

// Context Switch Controller
context_switch_controller #(
        .X(X),
        .Y(Y),
        .IDX_W(ACT_IDX_W),
        .PE_LAT(PE_LAT),
        .EXTRA_CSREG(EXTRA_CSREG)
    ) context_switch_controller_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_incntlim	        (i_incntlim),
        .i_clear            (cswitch_cnt_clear | i_soft_reset),
        .i_pipeline_en      (o_pipeline_en),
        .i_wei_pop_en       (o_wei_pop_en),
        .i_act_pop_en       (o_act_pop_en),
        .i_cswitch_en	    (cswitch_en),
        .i_cswitch_force    (cswitch_force),

        .o_cdone            (cdone),
        .o_cswitch_done     (cswitch_done),
        .o_cswitch_arr	    (o_cswitch_arr));


// Feeders FSM
feeders_fsm #(
        .X(X),
        .Y(Y),
        .IDX_W(OUT_IDX_W),
        .ACT_FIFO_POSITIONS(ACT_FIFO_POSITIONS),
        .WEI_FIFO_POSITIONS(WEI_FIFO_POSITIONS)
    ) feeders_fsm_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_pipeline_gate	(pipeline_gate),
        .i_feeders_start    (feeders_start),
        .i_fsm_reset	    (feeders_reset | i_soft_reset),
        .i_pop_gate         (pop_gate),
        .i_act_reps         (i_act_reps),
        .i_wei_reps         (i_wei_reps),
        .i_act_done         (i_act_done),
        .i_act_til_done     (i_act_til_done),
        .i_act_fifo_empty   (i_act_fifo_empty),
        .i_act_fifo_full    (i_act_fifo_full),
        .i_act_stall        (i_act_stall),
        .i_wei_done         (i_wei_done),
        .i_wei_til_done     (i_wei_til_done),
        .i_wei_fifo_empty   (i_wei_fifo_empty),
        .i_wei_fifo_full    (i_wei_fifo_full),
        .i_wei_stall        (i_wei_stall),

        .o_act_feeder_en    (o_act_feeder_en),
        .o_act_feeder_clear (o_act_feeder_clear),
        .o_act_start	    (o_act_start),
        .o_act_valid        (o_act_valid),
        .o_act_finalpush	(o_act_finalpush),
        .o_act_cnt_en       (o_act_cnt_en),
        .o_act_cnt_clear    (o_act_cnt_clear),
        .o_act_clearfifo	(o_act_clearfifo),
        .o_act_pop_en	    (o_act_pop_en),
        .o_act_finalctx     (o_act_finalctx),
        .o_wei_feeder_en    (o_wei_feeder_en),
        .o_wei_feeder_clear (o_wei_feeder_clear),
        .o_wei_start	    (o_wei_start),
        .o_wei_valid        (o_wei_valid),
        .o_wei_finalpush	(o_wei_finalpush),
        .o_wei_cnt_en       (o_wei_cnt_en),
        .o_wei_cnt_clear    (o_wei_cnt_clear),
        .o_wei_clearfifo	(o_wei_clearfifo),
        .o_wei_pop_en	    (o_wei_pop_en),
        .o_wei_cswitch      (o_wei_cswitch),
        .o_pipeline_en      (o_pipeline_en),
        .o_feed_status      (o_feed_status),
        .o_feeders_done	    (feeders_done));

// ------------------------
// Feeders deadlock flag
// ------------------------

assign o_feed_deadlock = (i_act_fifo_empty && i_wei_fifo_full) || (i_act_fifo_full && i_wei_fifo_empty);

endmodule 
