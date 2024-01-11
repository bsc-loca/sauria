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

module context_fsm (
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Soft reset signal
    input  logic                        i_soft_reset,

    // FSM Control inputs
    input  logic                        i_start,            // Start signal from interface
    input  logic                        i_outbuf_done,      // Done signal from output buffer
    input  logic                        i_cdone,            // Context done flag -> Signals last input shifted to array
    input  logic                        i_cswitch_done,     // Context Switch done flag
    input  logic                        i_shift_done,       // First ready flag from output buffer
    input  logic                        i_finalwrite,       // Flag from output buffer signaling that all outputs EXCEPT LAST have been written successfully
    input  logic                        i_feeders_done,     // Feeders done signal from Feeders FSM
    input  logic                        i_pipeline_en,      // Pipeline enable (for feedback)

	// Control Outputs (Feeders FSM)
    output  logic					    o_pipeline_gate,    // Master pipeline controll for stalls
    output  logic                       o_feeders_start,    // Start flag for Feeders
    output  logic                       o_feeders_reset,    // Feeders state Reset
    output  logic                       o_pop_gate,         // Pop start flag for Feeders + Array

	// Control Outputs (Output Buffer)
    output  logic					    o_outbuf_start,     // Start flag for output buffer
    output  logic                       o_outbuf_reset,     // Output buffer state Reset

    // Control Outputs (Context Switch Controller)
    output  logic                       o_cswitch_en,       // Context switch enable signal
    output  logic                       o_cswitch_force,    // Signal to force a context switch
    output  logic                       o_cswitch_cnt_clear, // Clear flag for cswitch counters and registers

    // Control Outputs (Systolic Array)
    output logic                        o_sa_clear,         // Clear signal for SA internal registers

    // Status Outputs (External)
    output logic [4:0]                  o_ctx_status,       // FSM status signal

    // Control Outputs (External)
    output  logic                       o_done              // Finish flag towards interface
);

// ----------
// SIGNALS
// ----------

// Main FSM
enum logic [4:0] {

    IDLE,
    START_FLAGS,
    ARRAY_PREP,
    FIRST_SHIFT,
    START_COMP,
    WAIT_CSWITCH,
    WAIT_CSWITCH_STALL,
    WAIT_OBUF,
    WAIT_OBUF_STALL,
    SCND_SHIFT,
    SCND_SHIFT_STALL,
    ALL_BUSY_SHIFT,
    ALL_BUSY,
    ARRAY_BUSY,
    ARRAY_CSWITCH,
    ARRAY_CSWITCH_STALL,
    OBUF_BUSY_SHIFT,
    FORCE_STALL,
    OBUF_BUSY,
    LAST_SHIFT,
    LAST_WAIT,
    DONE

} main_state_d, main_state_q;

// Helper FSM - For stall control
enum logic [1:0] {

    ARRAY_ACTIVE,
    ARRAY_STALL

} stall_state_d, stall_state_q;

// Flags that control helper FSM
logic computation_ready, force_stall, stall_state_reset;

// Output Buffer Done hold -> Hold up the signal until next start
logic outbuf_done_hold, outbuf_done_q;

// Output Buffer Enable -> Edge is Outbuf start signal
logic outbuf_enable_d, outbuf_enable_q;

// ---------------------------------
// Signal hold registers
// ---------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : hold_reg
    if(~i_rstn) begin
        outbuf_done_q <= 0;
    end else begin
        // Soft-reset
        if (i_soft_reset) begin
            outbuf_done_q <= 0;
        end else begin
            if (i_outbuf_done) begin
                outbuf_done_q <= 1;
            end else if (o_outbuf_start || o_outbuf_reset) begin
                outbuf_done_q <= 0;
            end
        end
    end
end

// Combinational part for direct switching
assign outbuf_done_hold = (i_outbuf_done || outbuf_done_q) && !(o_outbuf_start || o_outbuf_reset);

// ---------------------------------
// Edge outputs generation
// ---------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : edge_reg
    if(~i_rstn) begin
        outbuf_enable_q <= 0;
    end else begin
        outbuf_enable_q <= outbuf_enable_d;
    end
end

// Edge detection
assign o_outbuf_start = outbuf_enable_d & (!outbuf_enable_q);

// ---------------------------------
// FSM Registers
// ---------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : state_reg
    if(~i_rstn) begin
        main_state_q <= IDLE;
        stall_state_q <= ARRAY_STALL;
    end else begin
        main_state_q <= main_state_d;
        stall_state_q <= stall_state_d;
    end
end

// ----------------------------------------
// Stalls FSM - Transition Logic
// ----------------------------------------

always_comb begin: stalls_state_transitions

    // Maintain states by default
    stall_state_d = stall_state_q;

    // Reset signal brings it back to IDLE
    if (stall_state_reset || i_soft_reset) begin
        stall_state_d = ARRAY_STALL;

    end else begin

        case (stall_state_q)

            // ARRAY_ACTIVE => Array pipeline is enabled
            ARRAY_ACTIVE: begin
                if (force_stall || (i_cdone && (!computation_ready))) begin
                    stall_state_d = ARRAY_STALL;
                end
            end

            // ARRAY_STALL => Array pipeline is stalled
            ARRAY_STALL: begin
                if(computation_ready) begin
                    stall_state_d = ARRAY_ACTIVE;
                end
            end

            // Other => Should never reach => Go IDLE
            default: begin
                stall_state_d = ARRAY_STALL;
            end

        endcase
    end
end

// ----------------------------------------
// Stalls FSM - Output Logic
// ----------------------------------------

always_comb begin: stalls_output_logic

    // To avoid latches in case anything is forgotten
    o_pipeline_gate = 0;

    case (stall_state_q)

        // ARRAY_ACTIVE => Array pipeline is enabled
        ARRAY_ACTIVE: begin
            o_pipeline_gate = 1;
        end

        // ARRAY_STALL => Array pipeline is stalled
        ARRAY_STALL: begin
            o_pipeline_gate = 0;
        end

        // Other => Should never reach => Go IDLE
        default: begin
            o_pipeline_gate = 0;
        end

    endcase
end

// ----------------------------------------
// Context FSM - Transition Logic
// ----------------------------------------

always_comb begin: state_transitions

    // Maintain states by default
    main_state_d = main_state_q;

    // Soft-reset
    if (i_soft_reset) begin
        main_state_d = IDLE;

    end else begin
            
        case (main_state_q)

            // IDLE => Wait for start flag
            IDLE: begin
                if(i_start) begin
                    main_state_d = START_FLAGS;
                end
            end

            // START_FLAGS => Output buffer start + Feeders start
            START_FLAGS: begin
                main_state_d = ARRAY_PREP;
            end

            // ARRAY_PREP => Output buffer reads 0th context preload
            ARRAY_PREP: begin
                if(outbuf_done_hold) begin
                    main_state_d = FIRST_SHIFT;
                end
            end

            // FIRST_SHIFT => Shift 0th context preload, wait until i_shift_done
            FIRST_SHIFT: begin
                if(i_shift_done) begin
                    main_state_d = START_COMP;
                end
            end

            // START_COMP => Pipeline can be enabled from this point, plus first context switch
            START_COMP: begin
                if(i_pipeline_en) begin
                    main_state_d = WAIT_CSWITCH;
                end
            end

            // WAIT_CSWITCH => Wait for cswitch sequence completion
            WAIT_CSWITCH: begin
                if(i_cdone && i_cswitch_done) begin
                    main_state_d = WAIT_OBUF_STALL;
                end else if(i_cdone) begin
                    main_state_d = WAIT_CSWITCH_STALL;
                end else if(i_cswitch_done) begin
                    main_state_d = WAIT_OBUF;
                end
            end

            // WAIT_CSWITCH_STALL => Wait for cswitch sequence completion + Disable FIFO pop (pseudo-stall)
            WAIT_CSWITCH_STALL: begin
                if(i_cswitch_done) begin
                    main_state_d = WAIT_OBUF_STALL;
                end
            end

            // WAIT_OBUF => Wait for Output Buffer completion
            WAIT_OBUF: begin
                if(i_cdone && outbuf_done_hold) begin
                    main_state_d = SCND_SHIFT_STALL;
                end else if(i_cdone) begin
                    main_state_d = WAIT_OBUF_STALL;
                end else if(outbuf_done_hold) begin
                    main_state_d = SCND_SHIFT;
                end
            end

            // WAIT_OBUF_STALL => Wait for Output Buffer completion + Disable FIFO pop (pseudo-stall)
            WAIT_OBUF_STALL: begin
                if(outbuf_done_hold) begin
                    main_state_d = SCND_SHIFT_STALL;
                end
            end

            // SCND_SHIFT => Give last start flag to Output Buffer before starting normal operation
            SCND_SHIFT: begin
                if (i_cdone) begin
                    main_state_d = OBUF_BUSY_SHIFT;
                end else begin
                    main_state_d = ALL_BUSY_SHIFT;
                end
            end

            // SCND_SHIFT_STALL => Give last start flag to Output Buffer before starting normal operation + Disable FIFO pop (pseudo-stall)
            SCND_SHIFT_STALL: begin
                if (outbuf_done_hold) begin
                    main_state_d = ARRAY_CSWITCH;
                end
            end

            // ALL_BUSY_SHIFT => Normal operation, all elements are working, Output Buffer is shifting
            ALL_BUSY_SHIFT: begin

                // If Shift Done and Context end at the same time (rare)
                if (i_shift_done && i_cdone) begin
                    main_state_d = FORCE_STALL;

                // If Context computation ends first (undesirable)
                end else if (i_cdone) begin
                    main_state_d = OBUF_BUSY_SHIFT;

                // If Shift Done ends first (desirable)
                end else if (i_shift_done) begin
                    main_state_d = ALL_BUSY;
                end
            end

            // ALL_BUSY => Normal operation, all elements are working
            ALL_BUSY: begin

                // If Output Buffer and Context end at the same time (rare)
                if (outbuf_done_hold && i_cdone) begin
                    main_state_d = ARRAY_CSWITCH;
                
                // If Output Buffer ends first (desirable)
                end else if (outbuf_done_hold) begin
                    main_state_d = ARRAY_BUSY;

                // If Context computation ends first (undesirable)
                end else if (i_cdone) begin
                    main_state_d = OBUF_BUSY;
                end
            end

            // ARRAY_BUSY => Array computing, Output Buffer waiting for array
            ARRAY_BUSY: begin
                if (i_cdone) begin
                    main_state_d = ARRAY_CSWITCH;
                end
            end

            // OBUF_BUSY_SHIFT => Output Buffer fetching data, Array shifting zeros (soft-stall)
            OBUF_BUSY_SHIFT: begin
                // If output buffer finishes completely, go to cswitch
                if (outbuf_done_hold) begin
                    main_state_d = ARRAY_CSWITCH;

                // If only shift part finishes, stall and wait
                end else if (i_shift_done) begin
                    main_state_d = FORCE_STALL;
                end
            end

            // FORCE_STALL => 1 cycle to force a stall in secondary FSM
            FORCE_STALL: begin
                // If output buffer finishes completely, go to cswitch
                if (outbuf_done_hold) begin
                    main_state_d = ARRAY_CSWITCH;

                // Otherwise wait for output buffer
                end else begin
                    main_state_d = OBUF_BUSY;
                end
            end

            // OBUF_BUSY => Output Buffer fetching data, Array waiting (stall)
            OBUF_BUSY: begin
                if (outbuf_done_hold) begin
                    main_state_d = ARRAY_CSWITCH;
                end
            end

            // ARRAY_CSWITCH => Array computing while context switch takes place
            ARRAY_CSWITCH: begin

                // If context switch and current context finish at the same time, jump directly to:
                if(i_cdone && i_cswitch_done) begin
                    // If Feeders & Output Buffer have finished, advance to last section
                    if (i_feeders_done && i_finalwrite) begin
                        main_state_d = LAST_SHIFT;
                    // Otherwise go to OBUF_BUSY_SHIFT
                    end else begin
                        main_state_d = OBUF_BUSY_SHIFT;
                    end

                // If context finished while cswitch, must change to soft-stall with pop enable
                end else if(i_cdone) begin
                    main_state_d = ARRAY_CSWITCH_STALL;

                // When Context Switch Done flag arrives, decide:
                end else if (i_cswitch_done) begin
                    // If Feeders & Output Buffer have finished, advance to last section
                    if (i_feeders_done && i_finalwrite) begin
                        main_state_d = LAST_SHIFT;

                    // Otherwise back to computing
                    end else begin
                        main_state_d = ALL_BUSY_SHIFT;
                    end
                end
            end

            // ARRAY_CSWITCH_STALL => Context switch takes place BUT array has finished (soft-stall)
            ARRAY_CSWITCH_STALL: begin

                // When Context Switch Done flag arrives, decide:
                if (i_cswitch_done) begin
                    // If Feeders & Output Buffer have finished, advance to last section
                    if (i_feeders_done && i_finalwrite) begin
                        main_state_d = LAST_SHIFT;

                    // Otherwise jump directly to OBUF_BUSY_SHIFT
                    end else begin
                        main_state_d = OBUF_BUSY_SHIFT;
                    end
                end
            end

            // LAST_SHIFT => Instruct Output Buffer to shift last output data
            LAST_SHIFT: begin
                main_state_d = LAST_WAIT;
            end

            // LAST_WAIT => Wait for completion of last write to output memory
            LAST_WAIT: begin
                if(outbuf_done_hold) begin
                    main_state_d = DONE;
                end
            end

            // DONE => 1 cycle to reset things before going idle
            DONE: begin
                main_state_d = IDLE;
            end

            // Other => Should never reach => Go IDLE
            default: begin
                main_state_d = IDLE;
            end

        endcase
    end
end

// ----------------------------------------
// Context FSM - Output Logic
// ----------------------------------------

always_comb begin: output_logic

    // To avoid latches in case anything is forgotten
    computation_ready = 0;
    o_feeders_start = 0;
    o_feeders_reset = 1;
    o_pop_gate = 0;

    outbuf_enable_d = 0;
    o_outbuf_reset = 1;

    o_cswitch_en = 0;
    o_cswitch_force = 0;
    o_cswitch_cnt_clear = 1;
    o_sa_clear = 1;

    o_done = 0;
    stall_state_reset = 0;
    force_stall = 0;

    o_ctx_status = 30;

    case (main_state_q)

        // IDLE => Wait for start flag
        IDLE: begin
            computation_ready = 0;
            o_feeders_start = 0;
            o_feeders_reset = 1;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 1;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 1;
            o_sa_clear = 1;

            o_done = 1;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 0;
        end

        // START_FLAGS => Output buffer start + Feeders start
        START_FLAGS: begin
            computation_ready = 0;
            o_feeders_start = 1;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 1;
        end

        // ARRAY_PREP => Output buffer reads 0th context
        ARRAY_PREP: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 2;
        end

        // FIRST_SHIFT => Shift 0th context preload, wait until i_shift_done
        FIRST_SHIFT: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 3;
        end

        // START_COMP => Pipeline can be enabled from this point, plus first context switch
        START_COMP: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 1;
            o_cswitch_force = 1;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 4;
        end

        // WAIT_CSWITCH => Wait for cswitch sequence completion
        WAIT_CSWITCH: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 1;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 5;
        end

        // WAIT_CSWITCH => Wait for cswitch sequence completion + Disable FIFO pop (pseudo-stall)
        WAIT_CSWITCH_STALL: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 1;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 6;
        end

        // WAIT_OBUF => Wait for Output Buffer completion
        WAIT_OBUF: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 7;
        end

        // WAIT_OBUF => Wait for Output Buffer completion + Disable FIFO pop (pseudo-stall)
        WAIT_OBUF_STALL: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 8;
        end

        // SCND_SHIFT => Give last start flag to Output Buffer before starting normal operation
        SCND_SHIFT: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 9;
        end

        // SCND_SHIFT_STALL => Give last start flag to Output Buffer before starting normal operation + Disable FIFO pop (pseudo-stall)
        SCND_SHIFT_STALL: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 10;
        end

        // ALL_BUSY_SHIFT => Normal operation, all elements are working, Output Buffer is shifting
        ALL_BUSY_SHIFT: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 11;
        end

        // ALL_BUSY => Normal operation, all elements are working
        ALL_BUSY: begin
            computation_ready = 0;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 12;
        end

        // ARRAY_BUSY => Array computing, Output Buffer waiting for array
        ARRAY_BUSY: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 1;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 13;
        end

        // OBUF_BUSY_SHIFT => Output Buffer fetching data, Array shifting zeros (soft-stall)
        OBUF_BUSY_SHIFT: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 14;
        end

        // FORCE_STALL => 1 cycle to force a stall in secondary FSM
        FORCE_STALL: begin
            computation_ready = 0;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 1;

            o_ctx_status = 15;
        end

        // OBUF_BUSY => Output Buffer fetching data, Array waiting (stall)
        OBUF_BUSY: begin
            computation_ready = 0;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 16;
        end

        // ARRAY_CSWITCH => Array computing while context switch takes place
        ARRAY_CSWITCH: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 1;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 1;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 17;
        end

        // ARRAY_CSWITCH_STALL => Context switch takes place BUT array has finished (soft-stall)
        ARRAY_CSWITCH_STALL: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 1;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 18;
        end

        // LAST_SHIFT => Instruct Output Buffer to shift last output data + Context Switch
        LAST_SHIFT: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 1;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 19;
        end

        // LAST_WAIT => Wait for completion of last write to output memory
        LAST_WAIT: begin
            computation_ready = 1;
            o_feeders_start = 0;
            o_feeders_reset = 0;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 0;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 20;
        end

        // DONE => 1 cycle to reset things before going idle
        DONE: begin
            computation_ready = 0;
            o_feeders_start = 0;
            o_feeders_reset = 1;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 1;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 1;
            stall_state_reset = 1;
            force_stall = 0;

            o_ctx_status = 21;
        end

        // Other => Should never reach => Go IDLE
        default: begin
            computation_ready = 0;
            o_feeders_start = 0;
            o_feeders_reset = 1;
            o_pop_gate = 0;

            outbuf_enable_d = 0;
            o_outbuf_reset = 1;

            o_cswitch_en = 0;
            o_cswitch_force = 0;
            o_cswitch_cnt_clear = 0;
            o_sa_clear = 0;

            o_done = 0;
            stall_state_reset = 0;
            force_stall = 0;

            o_ctx_status = 31;
        end

    endcase
end

endmodule 
