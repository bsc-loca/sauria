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

module feeders_fsm #(
    parameter X = 3,
    parameter Y = 3,
    parameter IDX_W = 8,
    parameter ACT_FIFO_POSITIONS = 8,
    parameter WEI_FIFO_POSITIONS = 8
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // FSM Control inputs
    input  logic                        i_pipeline_gate,    // Gate signal to force stalls
    input  logic                        i_feeders_start,    // Start flag for Feeders
    input  logic                        i_fsm_reset,        // Flag to reset FSM after completion
    input  logic                        i_pop_gate,        // Start flag for FIFO popping

    // Control Inputs
    input  logic [IDX_W-1:0]            i_act_reps,         // Number of activation tiling repetitions (for different weights)
    input  logic [IDX_W-1:0]            i_wei_reps,         // Number of weight tiling repetitions (for different activations)
    input  logic                        i_act_done,         // Done flag from Activations
    input  logic                        i_act_til_done,     // Tiling Done flag from Activations
    input  logic                        i_act_fifo_empty, 	// FIFO empty flag from Activations
    input  logic                        i_act_fifo_full,    // FIFO full flag from Activations
    input  logic                        i_act_stall,
    input  logic                        i_wei_done,	        // Done flag from Weights
    input  logic                        i_wei_til_done,	    // Tiling Done flag from Weights
    input  logic                        i_wei_fifo_empty, 	// FIFO empty flag from Weights
    input  logic                        i_wei_fifo_full,    // FIFO full flag from Weights
    input  logic                        i_wei_stall,        

	// Control Outputs (Activation Feeders)
    output  logic					    o_act_feeder_en,    // Enable for Row feeders
    output  logic                       o_act_feeder_clear, // Clear signal Row feeder buffers
    output  logic                       o_act_start,        // Flag: first inputs of current context
    output  logic                       o_act_valid,        // Flag: valid inputs at feeder
    output  logic                       o_act_finalpush,    // Flag: push of last buffer values
    output  logic                       o_act_cnt_en,       // Enable for counters
    output  logic                       o_act_cnt_clear,    // Clear signal for the counters
    output  logic                       o_act_clearfifo,    // Clear signal for FIFO
    output  logic                       o_act_pop_en,       // FIFO pop enable
    output  logic                       o_act_finalctx,     // Final context flag for activation counters

	// Control Outputs (Weight Feeders)
    output  logic					    o_wei_feeder_en,    // Enable for Row feeders
    output  logic                       o_wei_feeder_clear, // Clear signal Row feeder buffers
    output  logic                       o_wei_start,        // Flag: first inputs of current context
    output  logic                       o_wei_valid,        // Flag: valid inputs at feeder
    output  logic                       o_wei_finalpush,    // Flag: push of last buffer values
    output  logic                       o_wei_cnt_en,       // Enable for counters
    output  logic                       o_wei_cnt_clear,    // Clear signal for the counters
    output  logic                       o_wei_clearfifo,    // Clear signal for FIFO
    output  logic                       o_wei_pop_en,       // FIFO pop enable
    output  logic                       o_wei_cswitch,      // Context switch flag for weight counters

    // Control Outputs (Global)
    output  logic                       o_pipeline_en,      // Pipeline Enable signal for Array and Feeders

    // Status Outputs (External)
    output logic [4:0]                  o_feed_status,      // FSM status signal

    // Control Outputs (Internal to control)
    output  logic                       o_feeders_done      // Finish flag
);

// ----------
// SIGNALS
// ----------

// Main FSM
enum logic [4:0] {

    IDLE,
    CNT_START,
    DATA_START,
    FIFO_FILL_WAIT,
    FIFO_FILL,
    FINAL_PUSH_EARLY,
    FEEDING,
    ACT_FINISHED,
    WEI_FINISHED,
    FINAL_PUSH_BOTH,
    FINAL_PUSH_WAIT,
    EMPTY_WAIT,
    FIFO_EMPTYING,
    FINISH

} main_state_d, main_state_q;

// Parameter: cycles of advantage for initial fill of FIFO
localparam FIFO_FILL_CYCLES = 1;

// Parameter: cycles previous to FINAL_PUSH
localparam FINAL_PUSH_PRE_WEI = 3;
localparam FINAL_PUSH_PRE_ACT = 3;      // Should be >= FINAL_PUSH_PRE_WEI !!!

// Parameter: cycles previous to FINAL_PUSH latency
localparam FINAL_PUSH_LATENCY = 4;

// Parameter: size of largest FIFO
localparam FIFO_MAX_POS = `max2(`max2(`max2(ACT_FIFO_POSITIONS, WEI_FIFO_POSITIONS), `max2(FINAL_PUSH_PRE_ACT, FINAL_PUSH_LATENCY)), FIFO_FILL_CYCLES);
localparam PROP_MAX_POS = `max2(X,Y);
localparam FIFO_CNT_BITS = $clog2(FIFO_MAX_POS + PROP_MAX_POS);

// Counter
logic                       a_cnt_en, a_cnt_clear, b_cnt_en, b_cnt_clear;
logic [FIFO_CNT_BITS-1:0]   a_cnt, b_cnt;

// Repetition counters
logic                       act_done_q, wei_done_q, act_done_edge, wei_done_edge;
logic [IDX_W-1:0]           act_rep_cnt_d, act_rep_cnt_q, wei_rep_cnt_d, wei_rep_cnt_q;
logic                       act_ov_flag, wei_ov_flag;

// Tile Done Shimming
logic                       act_til_done_q, wei_til_done_q, act_til_done_shim, wei_til_done_shim, act_ov_flag_shim, wei_ov_flag_shim;

// Internal signals
logic                       pipeline_en;
logic                       act_pop_en, wei_pop_en;
logic                       act_cnt_en, wei_cnt_en;

// Flag indicating a state previous to FEEDING
logic                       pre_feeding_flag;

// Flag that stops a counter in case it finishes before FEEDING state
logic                       act_cnt_hold_d, act_cnt_hold_q, wei_cnt_hold_d, wei_cnt_hold_q;

// ------------------------------------
// Pipeline enable signal
// ------------------------------------

always_comb begin
    
    // During EMPTY_WAIT and FIFO_EMPTYING, do not stall
    if (main_state_q == EMPTY_WAIT || main_state_q == FIFO_EMPTYING || main_state_q == FINISH) begin

        o_pipeline_en = i_pipeline_gate && pipeline_en;

    // During EMPTY_WAIT and FIFO_EMPTYING, stall unconditionally when any FIFO is empty => To avoid corner cases here
    end else if (main_state_q == FINAL_PUSH_BOTH || main_state_q == FINAL_PUSH_WAIT) begin

        o_pipeline_en = i_pipeline_gate && pipeline_en && !(i_act_fifo_empty || i_wei_fifo_empty);

    // Otherwise stall if any FIFO is empty -> Except if we are done with that feeder (cnt_hold), then just let it roll
    end else begin

        o_pipeline_en = i_pipeline_gate && pipeline_en && !((i_act_fifo_empty && (!act_cnt_hold_q)) || (i_wei_fifo_empty && (!wei_cnt_hold_q)));

    end
end

// ------------------------------------
// Pop enable signals
// ------------------------------------
    
assign o_act_pop_en = act_pop_en & i_pop_gate;
assign o_wei_pop_en = wei_pop_en & i_pop_gate;

// ------------------------------------
// Counter enable signals
// ------------------------------------
    
assign o_act_cnt_en = act_cnt_en & (!act_cnt_hold_q);
assign o_wei_cnt_en = wei_cnt_en & (!wei_cnt_hold_q);

// ------------------------------------------------------
// Repetition counters => Simple counters of done edges
// ------------------------------------------------------

always_comb begin

    // Done edge flags
    act_done_edge = i_act_til_done;     //(!act_done_q) && i_act_til_done;
    wei_done_edge = i_wei_done;         //(!wei_done_q) && i_wei_done;

    // Register value maintaining
    act_rep_cnt_d = act_rep_cnt_q;
    wei_rep_cnt_d = wei_rep_cnt_q;

    // Overflow flags
    act_ov_flag = 0;
    wei_ov_flag = 0;

    // ACTIVATION REPETITIONS
    if (act_rep_cnt_q == (i_act_reps-1)) begin

        act_ov_flag = 1;

        // Reset only on pulse
        if (act_done_edge) begin
            act_rep_cnt_d = 0;
        end

    // Up count when done
    end else if (act_done_edge) begin
        act_rep_cnt_d = act_rep_cnt_q + 1;
    end

    // WEIGHT REPETITIONS
    if (wei_rep_cnt_q == (i_wei_reps-1)) begin

        wei_ov_flag = 1;

        // Reset only on pulse
        if (wei_done_edge) begin
            wei_rep_cnt_d = 0;
        end

    // Up count when done
    end else if (wei_done_edge) begin
        wei_rep_cnt_d = wei_rep_cnt_q + 1;
    end

end

always_ff @(posedge i_clk or negedge i_rstn) begin : simple_rep_cnt
    if(~i_rstn) begin
        act_done_q <= 0;
        wei_done_q <= 0;
        act_rep_cnt_q <= 0;
        wei_rep_cnt_q <= 0;
    end else begin

        // Synchronous reset
        if (i_fsm_reset) begin
            act_done_q <= 0;
            wei_done_q <= 0;
            act_rep_cnt_q <= 0;
            wei_rep_cnt_q <= 0;
        end else begin
            act_done_q <= i_act_til_done;
            wei_done_q <= i_wei_done;
            act_rep_cnt_q <= act_rep_cnt_d;
            wei_rep_cnt_q <= wei_rep_cnt_d;
        end
    end
end

assign o_wei_cswitch = wei_ov_flag;
assign o_act_finalctx = act_ov_flag;

// -----------------------------------------------------
// Tile Done Shimming - Latency equalization with SRAM
// -----------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : til_done_shim_reg
    if(~i_rstn) begin
        act_til_done_q <= 0;
        wei_til_done_q <= 0;
        act_ov_flag_shim <= 0;
        wei_ov_flag_shim <= 0;
    end else begin

        // Gated and reset like in the Feeders
        if (o_act_cnt_clear) begin
            act_til_done_q <= 0;
            act_ov_flag_shim <= 0;
        end else if (o_act_cnt_en && (!i_act_fifo_full) && (!i_act_stall)) begin
            act_til_done_q <= i_act_til_done;
            act_ov_flag_shim <= act_ov_flag;
        end

        // Gated and reset like in the Feeders
        if (o_wei_cnt_clear) begin
            wei_til_done_q <= 0;
            wei_ov_flag_shim <= 0;
        end else if (o_wei_cnt_en && (!i_wei_fifo_full) && (!i_wei_stall)) begin
            wei_til_done_q <= i_wei_til_done;
            wei_ov_flag_shim <= wei_ov_flag;
        end
    end
end

assign act_til_done_shim = act_til_done_q && o_act_cnt_en && (!i_act_fifo_full) && (!i_act_stall);
assign wei_til_done_shim = wei_til_done_q && o_wei_cnt_en && (!i_wei_fifo_full) && (!i_wei_stall);

// ------------------------------------
// Counter Hold Flag
// ------------------------------------

always_comb begin
    
    act_cnt_hold_d = act_cnt_hold_q;
    wei_cnt_hold_d = wei_cnt_hold_q;

    // Activation Counter Hold SETs when final flag arrives & we are not in FEEDING
    if(!act_cnt_hold_q) begin
        if ((pre_feeding_flag) && (act_til_done_shim && act_ov_flag_shim)) begin
            act_cnt_hold_d = 1;
        end

    // Activation Counter Hold RESETs when arriving to FINAL_PUSH_BOTH
    end else begin
        if (main_state_q == FINAL_PUSH_BOTH) begin
            act_cnt_hold_d = 0;
        end
    end

    // Weight Counter Hold SETs when final flag arrives & we are not in FEEDING
    if(!wei_cnt_hold_q) begin
        if ((pre_feeding_flag) && (wei_til_done_shim && wei_ov_flag_shim)) begin
            wei_cnt_hold_d = 1;
        end

    // Weight Counter Hold RESETs when arriving to FINAL_PUSH_BOTH
    end else begin
        if (main_state_q == FINAL_PUSH_BOTH) begin
            wei_cnt_hold_d = 0;
        end
    end

end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : hold_cnt
    if(~i_rstn) begin
        act_cnt_hold_q <= 0;
        wei_cnt_hold_q <= 0;
    end else begin

        // Synchronous reset
        if (i_fsm_reset) begin
            act_cnt_hold_q <= 0;
            wei_cnt_hold_q <= 0;
        end else begin
            act_cnt_hold_q <= act_cnt_hold_d;
            wei_cnt_hold_q <= wei_cnt_hold_d;
        end
    end
end

// ---------------------------------
// Counters (multipurpose)
// ---------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : counters_reg
    if(~i_rstn) begin
        a_cnt <= 0;
        b_cnt <= 0;
    end else begin
        // A counter -> Independent on pipeline and pop
        if (a_cnt_clear) begin
            a_cnt <= 0;
        end else if(a_cnt_en) begin
            a_cnt <= a_cnt + 1;
        end

        // B counter -> Synchronized with pipeline and pop
        if (b_cnt_clear) begin
            b_cnt <= 0;
        end else if(b_cnt_en && i_pipeline_gate && i_pop_gate) begin
            b_cnt <= b_cnt + 1;
        end
    end
end

// ---------------------------------
// Feeders Control FSM - Registers
// ---------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : state_reg
    if(~i_rstn) begin
        main_state_q <= IDLE;
    end else begin
        main_state_q <= main_state_d;
    end
end

// ----------------------------------------
// Feeders Control FSM - Transition Logic
// ----------------------------------------

always_comb begin: state_transitions

    // Maintain states by default
    main_state_d = main_state_q;

    // Reset always leaves it at IDLE
    if (i_fsm_reset) begin
        main_state_d = IDLE;
        
    end else begin

        case (main_state_q)

            // IDLE => Wait for start flag
            IDLE: begin
                if(i_feeders_start) begin
                    main_state_d = CNT_START;
                end
            end

            // CNT_START => 1 cycle to raise the counter enables
            CNT_START: begin
                main_state_d = DATA_START;
            end

            // DATA_START => 1 cycle to raise the start flag
            DATA_START: begin
                main_state_d = FIFO_FILL_WAIT;
            end

            // FIFO_FILL_WAIT => Wait until first data values are pushed
            FIFO_FILL_WAIT: begin
                if((!i_act_fifo_empty || act_cnt_hold_q) && (!i_wei_fifo_empty || wei_cnt_hold_q)) begin
                    main_state_d = FIFO_FILL;
                end
            end

            // FIFO_FILL => Wait for FIFO to fill up a little and for FIFO popping to be enabled
            FIFO_FILL: begin

                // If everything is finished, go directly to FINAL_PUSH and start emptying the FIFOs
                if (act_cnt_hold_q && wei_cnt_hold_q) begin
                    main_state_d = FINAL_PUSH_EARLY;

                // Otherwise proceed normally
                end else if (i_pop_gate && (a_cnt == (FIFO_FILL_CYCLES-1))) begin
                    main_state_d = FEEDING;
                end
            end

            // FINAL_PUSH_EARLY => Special Final Push for very short loads
            FINAL_PUSH_EARLY: begin
                if ((a_cnt == `max2(FINAL_PUSH_PRE_WEI, FINAL_PUSH_PRE_ACT))&&
                    (!i_act_fifo_full)&&(!i_wei_fifo_full)&&(!i_act_stall)&&(!i_wei_stall)) begin
                    main_state_d = FINAL_PUSH_WAIT;
                end
            end

            // FEEDING => Feeders actively fetching data until completion
            FEEDING: begin
                
                // If both finish simultaneously
                if (((act_til_done_shim && act_ov_flag_shim) || act_cnt_hold_q) && ((wei_til_done_shim && wei_ov_flag_shim) || wei_cnt_hold_q)) begin
                    main_state_d = FINAL_PUSH_BOTH;
                
                // If Activation finishes first
                end else if ((act_til_done_shim && act_ov_flag_shim) || act_cnt_hold_q) begin
                    main_state_d = ACT_FINISHED;

                // If Weight finishes first
                end else if ((wei_til_done_shim && wei_ov_flag_shim) || wei_cnt_hold_q) begin
                    main_state_d = WEI_FINISHED;
                end
            end

            // ACT_FINISHED => Activations done, wait for weights
            ACT_FINISHED: begin

                // When Weight finishes, go to FINAL_PUSH_BOTH
                if (wei_til_done_shim && wei_ov_flag_shim) begin
                    main_state_d = FINAL_PUSH_BOTH;
                end
            end

            // WEI_FINISHED => Weights done, wait for activations
            WEI_FINISHED: begin

                // When Activation finishes, go to FINAL_PUSH_BOTH
                if (act_til_done_shim && act_ov_flag_shim) begin
                    main_state_d = FINAL_PUSH_BOTH;
                end
            end

            // FINAL_PUSH_BOTH => Final push: both counters
            FINAL_PUSH_BOTH: begin
                if ((a_cnt == `max2(FINAL_PUSH_PRE_WEI, FINAL_PUSH_PRE_ACT))&&
                    (!i_act_fifo_full)&&(!i_wei_fifo_full)&&(!i_act_stall)&&(!i_wei_stall)) begin
                    main_state_d = FINAL_PUSH_WAIT;
                end
            end

            // FINAL_PUSH_WAIT => Wait until final push is effective, otherwise empty flag can be misleading
            FINAL_PUSH_WAIT: begin
                if(a_cnt==(FINAL_PUSH_LATENCY-1)) begin
                    main_state_d = EMPTY_WAIT;
                end
            end

            // EMPTY_WAIT => Wait for first FIFO on each feeder to become empty
            EMPTY_WAIT: begin
                if(i_act_fifo_empty && i_wei_fifo_empty && i_pop_gate && i_pipeline_gate) begin
                    main_state_d = FIFO_EMPTYING;
                end
            end

            // FIFO_EMPTYING => Wait during FIFO_POSITIONS until all FIFOs are empty of values AND all last values have propagated into the array
            FIFO_EMPTYING: begin
                if(b_cnt == (PROP_MAX_POS + FIFO_MAX_POS-1)) begin
                    main_state_d = FINISH;
                end
            end

            // FINISH => Signal completion until reset
            FINISH: begin
                if (i_fsm_reset) begin
                    main_state_d = IDLE;
                end
            end

            // Other => Should never reach => Go IDLE
            default: begin
                main_state_d = IDLE;
            end

        endcase
    end
end

// ----------------------------------------
// Feeders Control FSM - Output Logic
// ----------------------------------------

always_comb begin: output_logic

    // To avoid latches in case anything is forgotten
    o_act_feeder_en = 0;
    o_act_feeder_clear = 1;
    o_act_start = 0;
    o_act_finalpush = 0;
    act_cnt_en = 0;
    o_act_valid = 0;
    o_act_cnt_clear = 1;
    o_act_clearfifo = 1;
    act_pop_en = 0;
    o_wei_feeder_en = 0;
    o_wei_feeder_clear = 1;
    o_wei_start = 0;
    o_wei_finalpush = 0;
    wei_cnt_en = 0;
    o_wei_valid = 0;
    o_wei_cnt_clear = 1;
    o_wei_clearfifo = 1;
    wei_pop_en = 0;
    o_feeders_done = 0;
    a_cnt_en = 0;
    a_cnt_clear = 1;
    b_cnt_en = 0;
    b_cnt_clear = 1;
    pipeline_en = 0;
    pre_feeding_flag = 1;
    o_feed_status = 30;

    case (main_state_q)

        // IDLE => Wait for start flag
        IDLE: begin
            o_act_feeder_en = 0;
            o_act_feeder_clear = 1;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 0;
            o_act_cnt_clear = 1;
            o_act_clearfifo = 1;
            act_pop_en = 0;

            o_wei_feeder_en = 0;
            o_wei_feeder_clear = 1;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;
            o_wei_cnt_clear = 1;
            o_wei_clearfifo = 1;
            wei_pop_en = 0;

            pipeline_en = 0;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 1;

            o_feed_status = 0;
        end

        // CNT_START => 1 cycle to raise the counter enables
        CNT_START: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 1;
            o_act_valid = 0;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 0;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 1;
            o_wei_valid = 0;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 0;

            pipeline_en = 0;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 1;

            o_feed_status = 1;
        end

        // DATA_START => 1 cycle to raise the start flag
        DATA_START: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 1;
            o_act_finalpush = 0;
            act_cnt_en = 1;
            o_act_valid = 0;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 0;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 1;
            o_wei_finalpush = 0;
            wei_cnt_en = 1;
            o_wei_valid = 0;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 0;

            pipeline_en = 0;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 1;

            o_feed_status = 2;
        end

        // FIFO_FILL_WAIT => Wait until first data values are pushed
        FIFO_FILL_WAIT: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 1;
            o_act_valid = 1;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 0;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 1;
            o_wei_valid = 1;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 0;

            pipeline_en = 0;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 1;

            o_feed_status = 3;
        end

        // FIFO_FILL => Wait for FIFO to fill up a little and for FIFO popping to be enabled
        FIFO_FILL: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 1;
            o_act_valid = 1;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = i_pop_gate;        // Combinational transition

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 1;
            o_wei_valid = 1;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = i_pop_gate;        // Combinational transition

            pipeline_en = 1;
            o_feeders_done = 0;

            if (a_cnt == (FIFO_FILL_CYCLES-1)) begin
                // Only in the very last cycle
                if (i_pop_gate) begin
                    a_cnt_en = 0;
                    a_cnt_clear = 1;
                // If not we just wait
                end else begin
                    a_cnt_en = 0;
                    a_cnt_clear = 0;
                end
                
            end else begin
                a_cnt_en = 1;
                a_cnt_clear = 0;
            end

            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 1;

            o_feed_status = 4;
        end

       // FINAL_PUSH_EARLY => Special Final Push for very short loads
        FINAL_PUSH_EARLY: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            act_cnt_en = 0;
            o_act_valid = 0;

            a_cnt_en = 1;
            a_cnt_clear = 0;

            o_act_finalpush = 0;
            o_wei_finalpush = 0;

            if (a_cnt == `max2(FINAL_PUSH_PRE_WEI, FINAL_PUSH_PRE_ACT)) begin
                a_cnt_en = 0;

                if ((!i_act_fifo_full)&&(!i_wei_fifo_full)&&(!i_act_stall)&&(!i_wei_stall)) begin
                    a_cnt_clear = 1;
                end
            end

            if ((a_cnt == FINAL_PUSH_PRE_ACT) && (!i_act_fifo_full)&&(!i_act_stall)) begin
                o_act_finalpush = 1;
            end

            if ((a_cnt == FINAL_PUSH_PRE_WEI) && (!i_wei_fifo_full)&&(!i_wei_stall)) begin
                o_wei_finalpush = 1;
            end

            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;

            b_cnt_en = 0;
            b_cnt_clear = 1;

            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 1;

            pre_feeding_flag = 0;

            o_feed_status = 5;
        end

        // FEEDING => Feeders actively fetching data until completion
        FEEDING: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 1;
            o_act_valid = 1;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 1;
            o_wei_valid = 1;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 0;

            o_feed_status = 6;
        end

        // ACT_FINISHED => Activations done, wait for weights
        ACT_FINISHED: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 1;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 1;
            o_wei_valid = 1;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 0;

            o_feed_status = 7;
        end

        // WEI_FINISHED => Weights done, wait for activations
        WEI_FINISHED: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 1;
            o_act_valid = 1;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 1;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 0;

            o_feed_status = 8;
        end

        // FINAL_PUSH_BOTH => Final push: both counters
        FINAL_PUSH_BOTH: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            act_cnt_en = 0;
            o_act_valid = 1;

            a_cnt_en = 1;
            a_cnt_clear = 0;

            o_act_finalpush = 0;
            o_wei_finalpush = 0;

            if (a_cnt == `max2(FINAL_PUSH_PRE_WEI, FINAL_PUSH_PRE_ACT)) begin
                a_cnt_en = 0;

                if ((!i_act_fifo_full)&&(!i_wei_fifo_full)&&(!i_act_stall)&&(!i_wei_stall)) begin
                    a_cnt_clear = 1;
                end
            end

            if ((a_cnt == FINAL_PUSH_PRE_ACT) && (!i_act_fifo_full)&&(!i_act_stall)) begin
                o_act_finalpush = 1;
            end

            if ((a_cnt == FINAL_PUSH_PRE_WEI) && (!i_wei_fifo_full)&&(!i_wei_stall)) begin
                o_wei_finalpush = 1;
            end

            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            wei_cnt_en = 0;
            o_wei_valid = 1;

            b_cnt_en = 0;
            b_cnt_clear = 1;

            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 1;

            pre_feeding_flag = 0;

            o_feed_status = 9;
        end

        // FINAL_PUSH_WAIT => Wait until final push is effective, otherwise empty flag can be misleading
        FINAL_PUSH_WAIT: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 0;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 1;

            a_cnt_en = 1;
            a_cnt_clear = 0;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 0;

            o_feed_status = 10;
        end

        // EMPTY_WAIT => Wait for first FIFO on each feeder to become empty
        EMPTY_WAIT: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 0;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 1;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 1;

            pipeline_en = 1;
            o_feeders_done = 1;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 0;

            o_feed_status = 11;
        end

        // FIFO_EMPTYING => Wait during FIFO_POSITIONS until all FIFOs are empty of values
        FIFO_EMPTYING: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 0;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 0;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 0;

            pipeline_en = 1;
            o_feeders_done = 1;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 1;
            b_cnt_clear = 0;

            pre_feeding_flag = 0;

            o_feed_status = 12;
        end

        // FINISH => Signal completion until reset
        FINISH: begin
            o_act_feeder_en = 1;
            o_act_feeder_clear = 1;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 0;
            o_act_cnt_clear = 1;
            o_act_clearfifo = 1;
            act_pop_en = 0;

            o_wei_feeder_en = 1;
            o_wei_feeder_clear = 1;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;
            o_wei_cnt_clear = 1;
            o_wei_clearfifo = 1;
            wei_pop_en = 0;

            pipeline_en = 1;
            o_feeders_done = 1;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 0;

            o_feed_status = 13;
        end

        // Other => Should never reach => All zeroes
        default: begin
            o_act_feeder_en = 0;
            o_act_feeder_clear = 0;
            o_act_start = 0;
            o_act_finalpush = 0;
            act_cnt_en = 0;
            o_act_valid = 0;
            o_act_cnt_clear = 0;
            o_act_clearfifo = 0;
            act_pop_en = 0;

            o_wei_feeder_en = 0;
            o_wei_feeder_clear = 0;
            o_wei_start = 0;
            o_wei_finalpush = 0;
            wei_cnt_en = 0;
            o_wei_valid = 0;
            o_wei_cnt_clear = 0;
            o_wei_clearfifo = 0;
            wei_pop_en = 0;

            o_feeders_done = 0;

            a_cnt_en = 0;
            a_cnt_clear = 1;
            b_cnt_en = 0;
            b_cnt_clear = 1;

            pre_feeding_flag = 1;

            o_feed_status = 31;
        end

    endcase
end

endmodule 
