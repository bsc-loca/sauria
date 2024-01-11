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
// -------------------

module psm_shift_fsm #(
    parameter IDX_W = 8,
    parameter PARAMS_W = 2,
    parameter X = 3
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // FSM Control inputs
    input  logic                        i_fsm_start,        // Start flag for scan FSM
    input  logic                        i_fsm_reset,        // Flag to reset FSM after completion
    input  logic [IDX_W-1:0]            i_ncontexts,        // Total number of contexts (NOT counting +3 for Write)
    input  logic                        i_preload_en,       // Start flag for scan FSM
    input  logic [PARAMS_W-1:0]         i_inactive_cols,    // Number of inactive columns

    // Feedback Inputs
    input  logic                        i_pipeline_en,      // Pipeline Enable, needed to hold the scan enable upon stalls
    input  logic                        i_done,             // Done flag from Counters
    input  logic                        i_til_done,         // Done flag from Counters

	// Control Outputs (Counters)
    output  logic					    o_cnt_en,           // Enable for Counters
    output  logic                       o_cnt_clear,        // Clear signal for Counters
    output  logic                       o_wr_flag,          // Write/Read flag for Counters
    output  logic                       o_cnt_start,        // Flag: first inputs of current context

    // Control Outputs (Buffer)
    output  logic                       o_buff_clear,       // Output Buffer clear flag

	// Control Outputs (Read Data Manager)
    output  logic					    o_rd_feeder_en,     // Enable for Read manager
    output  logic                       o_rd_feeder_clear,  // Clear signal for Read manager

	// Control Outputs (Write Data Manager)
    output  logic					    o_wr_feeder_en,     // Enable for Write manager
    output  logic                       o_wr_feeder_clear,  // Clear signal for Write manager

    // Control Outputs (External)
    output  logic					    o_sramc_wren,       // Write enable signal for SRAM
    output  logic                       o_sramc_rden,       // Read enable signal for SRAM
    output  logic					    o_cscan_en,         // Output Scan-Chain Enable
    output  logic                       o_buff_shift,       // Buffer shift (scan) Enable

    // Status Outputs
    output  logic [4:0]                 o_out_status,       // Output Scan FSM status
    output  logic                       o_shift_done,       // Flag signaling that computation can start
    output  logic                       o_done,             // Finish flag
    output  logic                       o_finalwrite        // Flag signaling that all outputs EXCEPT LAST have been written successfully
);

// ----------
// SIGNALS
// ----------

// Main FSM
enum logic [3:0] {

    IDLE,
    PREREAD_SHIFT,
    RD_CNT_START,
    READING,
    READING_LAT_WAIT,
    POSTREAD_SHIFT,
    PREWRITE_SHIFT,
    WR_CNT_START,
    WRITING,
    WREN_HOLD_LAST,
    WRITING_LAT_WAIT,
    FINISH

} main_state_d, main_state_q;

localparam WR_LAT = 1;
localparam RD_LAT = 3;
localparam CYC_CNT_BITS = $clog2(`max2(`max2(WR_LAT, X), RD_LAT)+1);
localparam SCAN_CNT_BITS = $clog2(X+1);

// Cycle Counter
logic                       cyc_cnt_en, cyc_cnt_clear;
logic [CYC_CNT_BITS-1:0]    cyc_cnt;

// Scan Cycle Counter
logic                       scan_cnt_en, scan_cnt_clear;
logic [SCAN_CNT_BITS-1:0]   scan_cnt;

// Context counter
logic                       ctx_cnt_en, ctx_cnt_clear;
logic [IDX_W-1:0]           ctx_cnt;

// Inactive columns flag
logic                       inactive_cols_flag;

// Completion flag -> Blocks the FSM
logic                       completion_flag;

// -------------------------------------------------------------------------
// Inactive Columns Flag -> High to indicate that some columns are inactive
// -------------------------------------------------------------------------

assign inactive_cols_flag = (i_inactive_cols != 0);

// ------------------
// Simple Counters
// ------------------

assign ctx_cnt_clear = i_fsm_reset;
assign o_cnt_clear = i_fsm_reset;

always_ff @(posedge i_clk or negedge i_rstn) begin : counters_reg
    if(~i_rstn) begin
        cyc_cnt <= 0;
        scan_cnt <= 0;
        ctx_cnt <= 0;
    end else begin
        // Cycle counter
        if (cyc_cnt_clear) begin
            cyc_cnt <= 0;
        end else if(cyc_cnt_en) begin
            cyc_cnt <= cyc_cnt + 1;
        end

        // Scan cycle counter
        if (scan_cnt_clear) begin
            scan_cnt <= 0;
        end else if(scan_cnt_en && i_pipeline_en) begin
            scan_cnt <= scan_cnt + 1;
        end

        // Context counter
        if (ctx_cnt_clear) begin
            ctx_cnt <= 0;
        end else if(ctx_cnt_en) begin
            ctx_cnt <= ctx_cnt + 1;
        end
    end
end

// ---------------------------------
// Feeders Control FSM - Register
// ---------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : state_reg
    if(~i_rstn) begin
        main_state_q <= IDLE;
    end else begin
        main_state_q <= main_state_d;
    end
end

// ----------------------------------------
// Buffer Clear flag => Simple logic
// ----------------------------------------

assign o_buff_clear = (main_state_q==IDLE) && ((!i_preload_en)||(ctx_cnt>i_ncontexts));

// ------------------------------------------------------------
// Final write flag => When current context is last
// ------------------------------------------------------------

assign o_finalwrite = (ctx_cnt == (i_ncontexts+2));

// ------------------------------------------------------------
// Completion flag => Block FSM after last current is finished
// ------------------------------------------------------------

assign completion_flag = (ctx_cnt == (i_ncontexts+3));

// ----------------------------------------
// Feeders Control FSM - Transition Logic
// ----------------------------------------

always_comb begin: state_transitions

    // Maintain states by default
    main_state_d = main_state_q;

    case (main_state_q)

        // IDLE => Wait for start flag
        IDLE: begin
            if(i_fsm_start && !completion_flag) begin
                
                // If initial section
                if (ctx_cnt<3) begin
                    
                    // If preload is currently needed
                    if (i_preload_en && (i_ncontexts >= ctx_cnt)) begin
                        
                        // If we are on the very first context : No need for Shift
                        if (ctx_cnt == 0) begin
                            main_state_d = RD_CNT_START;

                        // Otherwise: Shift+Read procedure
                        end else begin
                            main_state_d = PREREAD_SHIFT;
                        end

                    // If preload is NOT currently needed
                    end else begin
                        main_state_d = FINISH;
                    end

                // If not initial section : Shift+Write procedure
                end else begin
                    main_state_d = PREWRITE_SHIFT;
                end
            end
        end

        // PREREAD_SHIFT => Shift array before reading (shift-in previous read)
        PREREAD_SHIFT: begin
            if ((i_pipeline_en)&&(scan_cnt == X-1)) begin

                // If current shift was the last, skip reading phase
                if (ctx_cnt == i_ncontexts) begin
                    main_state_d = FINISH;

                // Otherwise proceed with reading
                end else begin
                    main_state_d = RD_CNT_START;
                end
            end
        end

        // RD_CNT_START => 1 cycle for cnt start signal
        RD_CNT_START: begin
            main_state_d = READING;
        end

        // READING => Maintain state until i_done
        READING: begin
            if (i_done) begin
                main_state_d = READING_LAT_WAIT;
            end
        end

        // READING_LAT_WAIT => Wait to account for RD Data latency
        READING_LAT_WAIT: begin
            if (cyc_cnt==RD_LAT) begin
                // If some columns are inactive we must shift extra cycles
                if (inactive_cols_flag) begin
                    main_state_d = POSTREAD_SHIFT;

                // Otherwise we are done
                end else begin
                    main_state_d = FINISH;
                end
            end
        end

        // POSTREAD_SHIFT => Shift in extra cycles if the array is underutilized => Needed to reach proper array location
        POSTREAD_SHIFT: begin
            if (cyc_cnt == (i_inactive_cols-1)) begin
                main_state_d = FINISH;
            end
        end

        // PREWRITE_SHIFT => Shift array before writing (shift-in previous read + shift-out current write)
        PREWRITE_SHIFT: begin
            if ((i_pipeline_en)&&(scan_cnt == X-1)) begin
                main_state_d = WR_CNT_START;
            end
        end

        // WR_CNT_START => 1 cycle for cnt start signal
        WR_CNT_START: begin
            main_state_d = WRITING;
        end

        // WRITING => Maintain state until i_done
        WRITING : begin
            if (i_done) begin
                main_state_d = WREN_HOLD_LAST;
            end
        end

        // WREN_HOLD_LAST => Hold wren signal for an additional CLK (last address)
        WREN_HOLD_LAST : begin
            main_state_d = WRITING_LAT_WAIT;
        end

        // WRITING_LAT_WAIT => Wait for three cycles to account for WR Data latency, then decide if read or not
        WRITING_LAT_WAIT: begin
            if (cyc_cnt==WR_LAT) begin
                // Go to Read if preload is enabled and ctx_cnt has not reached the end (ie. there is sth to read)
                if (i_preload_en && (ctx_cnt < i_ncontexts)) begin
                    main_state_d = RD_CNT_START;
                end else begin
                    main_state_d = FINISH;
                end
            end
        end

        // FINISH => 1 cycle to signal completion
        FINISH: begin
            main_state_d = IDLE;
        end

        // Other => Should never reach => Go IDLE
        default: begin
            main_state_d = IDLE;
        end

    endcase
end

// ----------------------------------------
// Feeders Control FSM - Output Logic
// ----------------------------------------

always_comb begin: output_logic

    // To avoid latches in case anything is forgotten
    o_cnt_en = 0;
    o_wr_flag = 0;
    o_cnt_start = 0;
    o_rd_feeder_en = 0;
    o_rd_feeder_clear = 1;
    o_wr_feeder_en = 0;
    o_wr_feeder_clear = 1;
    o_done = 0;
    o_shift_done = 0;
    o_sramc_wren = 0;
    o_sramc_rden = 0;
    o_cscan_en = 0;
    o_buff_shift = 0;
    cyc_cnt_en = 0;
    cyc_cnt_clear = 1;
    scan_cnt_en = 0;
    scan_cnt_clear = 1;
    ctx_cnt_en = 0;
    o_out_status = 30;

    case (main_state_q)

        // IDLE => Wait for start flag
        IDLE: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 0;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 0;
        end

        // PREREAD_SHIFT => Shift array before reading (shift-in previous read)
        PREREAD_SHIFT: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 0;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 1;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 1;
            scan_cnt_clear = 0;
            ctx_cnt_en = 0;

            o_out_status = 1;
        end

        // RD_CNT_START => 1 cycle for cnt start signal
        RD_CNT_START: begin
            o_cnt_en = 1;
            o_wr_flag = 0;
            o_cnt_start = 1;
            o_rd_feeder_en = 1;
            o_rd_feeder_clear = 0;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 0;
            o_sramc_rden = 1;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 2;
        end

        // READING => Maintain state until i_done
        READING: begin
            o_cnt_en = 1;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 1;
            o_rd_feeder_clear = 0;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 0;
            o_sramc_rden = 1;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 3;
        end

        // READING_LAT_WAIT => Wait to account for RD Data latency
        READING_LAT_WAIT: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 1;
            o_rd_feeder_clear = 0;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 0;
            o_sramc_rden = 1;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 1;

            // Reset counter on last cycle
            if (cyc_cnt==RD_LAT) begin
                cyc_cnt_clear = 1;
            end else begin
                cyc_cnt_clear = 0;
            end        
            
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 4;
        end

        // POSTREAD_SHIFT => Shift in extra cycles if the array is underutilized => Needed to reach proper array location
        POSTREAD_SHIFT: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 0;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 1;

            cyc_cnt_en = 1;
            cyc_cnt_clear = 0;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 5;
        end

        // PREWRITE_SHIFT => Shift array before writing (shift-in previous read + shift-out current write)
        PREWRITE_SHIFT: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 0;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 1;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 1;
            scan_cnt_clear = 0;
            ctx_cnt_en = 0;

            o_out_status = 6;
        end

        // WR_CNT_START => 1 cycle for cnt start signal
        WR_CNT_START: begin
            o_cnt_en = 1;
            o_wr_flag = 1;
            o_cnt_start = 1;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 1;
            o_wr_feeder_clear = 0;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 7;
        end

        // WRITING => Maintain state until i_done, then decide if read or not
        WRITING: begin
            o_cnt_en = 1;
            o_wr_flag = 1;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 1;
            o_wr_feeder_clear = 0;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 1;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 8;
        end

        // WREN_HOLD_LAST => Hold wren signal for an additional CLK (last address)
        WREN_HOLD_LAST: begin
            o_cnt_en = 0;
            o_wr_flag = 1;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 1;
            o_wr_feeder_clear = 0;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 1;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 9;
        end

        // WRITING_LAT_WAIT => Wait for three cycles to account for WR Data latency, then decide if read or not
        WRITING_LAT_WAIT: begin
            o_cnt_en = 0;
            o_wr_flag = 1;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 1;
            o_wr_feeder_clear = 0;

            o_done = 0;
            o_shift_done = 1;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 1;
            cyc_cnt_clear = 0;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 10;
        end

        // FINISH => 1 cycle to signal completion
        FINISH: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 1;
            o_shift_done = 1;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 1;

            o_out_status = 11;
        end

        // Other => Should never reach => Go IDLE
        default: begin
            o_cnt_en = 0;
            o_wr_flag = 0;
            o_cnt_start = 0;
            o_rd_feeder_en = 0;
            o_rd_feeder_clear = 1;
            o_wr_feeder_en = 0;
            o_wr_feeder_clear = 1;

            o_done = 0;
            o_shift_done = 0;
            o_sramc_wren = 0;
            o_sramc_rden = 0;
            o_cscan_en = 0;
            o_buff_shift = 0;

            cyc_cnt_en = 0;
            cyc_cnt_clear = 1;
            scan_cnt_en = 0;
            scan_cnt_clear = 1;
            ctx_cnt_en = 0;

            o_out_status = 31;
        end

    endcase
end

endmodule 
