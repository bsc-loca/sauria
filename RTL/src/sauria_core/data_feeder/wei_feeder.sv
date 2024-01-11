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

module wei_feeder #(
    parameter X = 3,
    parameter FIFO_POSITIONS = 8,
    parameter IB_W = 16,
    parameter SRAMB_W = 128,
    parameter IDX_W = 11,
    parameter ADRB_W = 8,
    parameter PARAMS_W = 8
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

	// Data Inputs
    input  logic [SRAMB_W-1:0]          i_sramb_data,       // Data bus from SRAMB

	// Index Counter Control Inputs
    input  logic                        i_cnt_en,           // Enable for counters
    input  logic                        i_cnt_clear,        // Clear signal for counters
    input  logic                        i_cswitch,          // Context switch enable -> Control of repetitions
    input  logic [0:X-1]		        i_cols_active,      // Active Columns configuration
    input  logic                        i_waligned,         // Bit that indicates if weight values are aligned in memory (better perf.)
    input  logic [IDX_W-1:0]		    i_auxlim,           // Idx Counters : Auxiliary counter limit
    input  logic [IDX_W-1:0]		    i_auxstep,          // Idx Counters : Auxiliary counter step size
    input  logic [IDX_W-1:0]		    i_wlim,             // Idx Counters : Weight counter limit
    input  logic [IDX_W-1:0]		    i_wstep,            // Idx Counters : Weight counter step size
    input  logic [IDX_W-1:0]		    i_til_klim,         // Idx Counters : Tiling Out-Channel counter limit
    input  logic [IDX_W-1:0]		    i_til_kstep,        // Idx Counters : Tiling Out-Channel counter step
    
    // Column Feeder control inputs
    input  logic					    i_feeder_en,        // Enable for counters and Column feeders
    input  logic                        i_feeder_clear,     // Clear signal for counters and Column feeder buffers
    input  logic                        i_wei_valid,        // Flag: valid inputs at feeder
    input  logic                        i_finalpush,        // Flag: push of last buffer values

    // FIFO control inputs
    input logic                         i_clearfifo,        // Clear signal for FIFO
    input logic                         i_pipeline_en,      // Systolic Array pipeline enable
    input logic                         i_pop_en,           // FIFO pop enable

	// Control Outputs
    output logic                        o_done, 	        // Current context counters done flag
    output logic                        o_til_done, 	    // Tiling counters done flag
    output logic [ADRB_W-1:0]           o_sramb_addr,       // Address towards SRAMB
    output logic                        o_sramb_rden,       // Read Enable for SRAMB
	output logic                        o_fifo_empty, 	    // FIFO empty flag (any)
    output logic                        o_fifo_full, 	    // FIFO full flag (any)
    output logic                        o_feeder_stall,     // Feeder stall flag (any)

    // Status Outputs
    output logic                        o_wei_deadlock,     // Deadlock flag

    // Data Outputs
	output logic [0:X-1][IB_W-1:0]      o_b_arr             // Weights feeding stream

);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam SRAMB_N = SRAMB_W/IB_W;
localparam WOFS_W = $clog2(SRAMB_N);

// Index counter -> Column feeders
logic [WOFS_W-1:0]  glob_woffs;

// Internal signals
logic [0:X-1]       fifo_empty, fifo_full, stall;
logic               fifo_empty_any, fifo_full_any, stall_any;
logic               feeders_update, feeders_update_q1;
logic               valid_q1, valid_q2, start_q, valid_data;      // Needs shimming
logic               pipeline_regs_en, cnt_en;
logic               finalpush_q1, finalpush_q2;                     // For shimming
logic               transn;
logic               outbounds, outbounds_q1, outbounds_q2, outbounds_q3;

logic [0:X-1][IB_W-1:0]         lane_dout;

// Data bus register
logic [SRAMB_W-1:0]             sram_data_q;

// Muxed signals
logic [SRAMB_W-1:0]             sramb_data_mux;
logic [WOFS_W-1:0]              glob_woffs_mux;
logic                           transn_mux;

// Local Word Offset (constants)
logic [0:X-1][PARAMS_W-1:0]     loc_woffs;

// FIFO full signal shimming => To equalize with SRAM rden latency
logic                           fifo_full_any_shim;

// ------------------------------------------------------------
// Local Word Offset is just the position of the feeder
// ------------------------------------------------------------

genvar x;
generate
    for (x=0; x < X; x++) begin
        assign loc_woffs[x] = x;
    end
endgenerate

// ------------------------------------------------------------
// Enable signals => Only advance if EN and NOT FULL
// ------------------------------------------------------------

assign pipeline_regs_en =   i_feeder_en & (!fifo_full_any) & (!stall_any);
assign cnt_en =             i_cnt_en & (!fifo_full_any) & (!stall_any);
assign feeders_update =     (!fifo_full_any) & (!stall_any);

// ------------------------------------------------------------
// Valid data signal & shimming registers
// ------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : valid_data_reg
    if(~i_rstn) begin
        finalpush_q1 <= 0;
        finalpush_q2 <= 0;
        valid_q1 <= 0;
        valid_q2 <= 0;
        outbounds_q1 <= 0;
        outbounds_q2 <= 0;
        outbounds_q3 <= 0;
    end else begin

        // Synchronous reset
        if (i_feeder_clear) begin
            finalpush_q1 <= 0;
            finalpush_q2 <= 0;
            valid_q1 <= 0;
            valid_q2 <= 0;
            outbounds_q1 <= 0;
            outbounds_q2 <= 0;
            outbounds_q3 <= 0;

        end else if (pipeline_regs_en) begin
            finalpush_q1 <= i_finalpush;
            finalpush_q2 <= finalpush_q1;
            valid_q1 <= i_wei_valid;
            valid_q2 <= valid_q1;
            outbounds_q1 <= outbounds;
            outbounds_q2 <= outbounds_q1;
            outbounds_q3 <= outbounds_q2;
        end
    end
end

assign valid_data = (i_wei_valid && !(outbounds_q1)) || i_finalpush || stall_any;

// ----------------------------------------------------------------------------
// Data Bus register (latency equalization of SRAM data with Data Manager)
// ----------------------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : data_reg
    if(~i_rstn) begin
        sram_data_q <= 0;
    end else begin

        // Synchronous reset
        if (i_feeder_clear) begin
            sram_data_q <= 0;

        end else if (pipeline_regs_en) begin
            sram_data_q <= i_sramb_data;
        end
    end
end

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// Global Index Counters
wei_idxcnt #(
        .IDX_W(IDX_W),
        .ADRB_W(ADRB_W),
        .WOFS_W(WOFS_W),
        .PARAMS_W(PARAMS_W)
    ) wei_idxcnt_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_cnt_en	    (cnt_en),
        .i_cnt_clear    (i_cnt_clear),
        .i_cswitch      (i_cswitch),
        .i_waligned     (i_waligned),
        .i_auxlim       (i_auxlim),
        .i_auxstep      (i_auxstep),
        .i_wlim         (i_wlim),
        .i_wstep        (i_wstep),
        .i_til_klim	    (i_til_klim),
        .i_til_kstep    (i_til_kstep),

        .o_transn       (transn),
        .o_sram_addr    (o_sramb_addr),
        .o_woffs	    (glob_woffs),
        .o_outbounds    (outbounds),
        .o_done	        (o_done),
        .o_til_done	    (o_til_done));

// Column Feeders (along X dimension)
genvar jj;
    generate
        for (jj=0; jj < X; jj++) begin : x_axis

            feed_xy_lane #(
                    .FIFO_POSITIONS(FIFO_POSITIONS),
                    .I_W(IB_W),
                    .WOFS_W(WOFS_W),
                    .SRAM_W(SRAMB_W),
                    .DILP_W(SRAMB_N),
                    .PARAMS_W(PARAMS_W),
                    .M(1)                                                   // M fix to 1
                ) act_row_feeder_i
                   (.i_clk          (i_clk),
                    .i_rstn         (i_rstn),
                    
                    .i_sram_data    (sramb_data_mux),
                    .i_feeder_en    (i_feeder_en && i_cols_active[jj]),     // Column Active to zero overrides feeder enable
                    .i_update       (feeders_update),
                    .i_clearbuff    (i_feeder_clear),
                    .i_valid_data	(valid_data),
                    .i_x_ov_flag    (transn_mux),                           
                    .i_glob_woffs   (glob_woffs_mux),
                    .i_loc_woffs    (loc_woffs[jj]),
                    .i_Dil_pat      ( {1'b1, {(SRAMB_N-1){1'b0}}} ),        // Fix to 1 the first position, 0 otherwise (no pattern)
                    .i_finalpush    (finalpush_q2),                                 
                    .i_clearfifo    (i_clearfifo),
                    .i_pipeline_en  (i_pipeline_en),
                    .i_pop_en       (i_pop_en),

                    .o_stall        (stall[jj]),
                    .o_fifo_empty   (fifo_empty[jj]),
                    .o_fifo_full    (fifo_full[jj]),
                    .o_data	        (lane_dout[jj]));

            feed_registers #(
                .N_REGS(jj),
                .I_W(IB_W)
            ) feed_registers_i
                   (.i_clk          (i_clk),
                    .i_rstn         (i_rstn),
                    
                    .i_clear        (i_clearfifo),
                    .i_pipeline_en  (i_pipeline_en),

                    .i_din          (lane_dout[jj]),
                    .o_dout	        (o_b_arr[jj]));

        end
    endgenerate

// -----------------------------------------------------------------
// Signal muxing => During final push some have special fix values
// -----------------------------------------------------------------

assign sramb_data_mux = (finalpush_q2)      ? '{default: 0} : sram_data_q;
assign glob_woffs_mux = (i_finalpush)       ? '{default: 0} : glob_woffs;
assign transn_mux = (i_finalpush)           ?   1'b0        : transn;

// -----------------------------------
// Reduction of flag signals
// -----------------------------------

always_comb begin

    fifo_empty_any = 0;
    fifo_full_any = 0;
    stall_any = 0;

    for (integer j=0; j < X; j++) begin
        fifo_empty_any = fifo_empty_any | (fifo_empty[j] && i_cols_active[j]);     // Column Active to zero overrides fifo empty
        fifo_full_any = fifo_full_any | fifo_full[j];
        stall_any = stall_any | stall[j];
    end
end

// -----------------------------------------------------------------
// FIFO full signal shimming => To equalize with SRAM rden latency
// -----------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : full_shim_reg
    if(~i_rstn) begin
        fifo_full_any_shim <= 0;
    end else begin
        fifo_full_any_shim <= fifo_full_any;
    end
end

// ------------------------
// Output management
// ------------------------

assign o_fifo_empty = fifo_empty_any;
assign o_sramb_rden = feeders_update;
assign o_fifo_full = fifo_full_any;
assign o_feeder_stall = stall_any;

assign o_wei_deadlock = fifo_empty_any & fifo_full_any;

endmodule 
