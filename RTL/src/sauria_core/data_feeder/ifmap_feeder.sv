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

module ifmap_feeder #(
    parameter Y = 3,
    parameter FIFO_POSITIONS = 8,
    parameter IA_W = 16,
    parameter SRAMA_W = 128,
    parameter IDX_W = 11,
    parameter ADRA_W = 8,
    parameter DILP_W = 64,
    parameter PARAMS_W = 8,
    parameter M = 3
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

	// Data Inputs
    input  logic [SRAMA_W-1:0]          i_srama_data,       // Data bus from SRAMA

	// Index Counter Control Inputs
    input  logic                        i_cnt_en,           // Enable for counters
    input  logic                        i_cnt_clear,        // Clear signal for counters
    input  logic                        i_finalctx,         // Final context flag -> Current tile is last
    input  logic [0:Y-1]		        i_rows_active,      // Active Rows configuration
    input  logic [IDX_W-1:0]		    i_xlim,             // Idx Counters : X counter limit
    input  logic [IDX_W-1:0]		    i_xstep,            // Idx Counters : X counter step size
    input  logic [IDX_W-1:0]		    i_ylim,             // Idx Counters : Y counter limit
    input  logic [IDX_W-1:0]		    i_ystep,            // Idx Counters : Y counter step size
    input  logic [IDX_W-1:0]		    i_chlim,            // Idx Counters : In-Channel counter limit
    input  logic [IDX_W-1:0]		    i_chstep,           // Idx Counters : In-Channel counter step size
    input  logic [IDX_W-1:0]		    i_til_xlim,         // Idx Counters : Tiling x counter limit
    input  logic [IDX_W-1:0]		    i_til_xstep,        // Idx Counters : Tiling x counter step size
    input  logic [IDX_W-1:0]		    i_til_ylim,         // Idx Counters : Tiling y counter limit
    input  logic [IDX_W-1:0]		    i_til_ystep,        // Idx Counters : Tiling y counter step size
    
    // Row Feeder control inputs
    input  logic					    i_feeder_en,        // Enable for counters and Row feeders
    input  logic                        i_feeder_clear,     // Clear signal for counters and Row feeder buffers
    input  logic                        i_act_valid,        // Flag: valid inputs at feeder
    input  logic                        i_start,            // Flag: first inputs of current context
    input  logic                        i_finalpush,        // Flag: push of last buffer values
    input  logic [0:Y-1][PARAMS_W-1:0]  i_loc_woffs,        // Local word offset array (encodes strides)
    input  logic [0:DILP_W-1]	        i_Dil_pat,          // Dilation pattern (encodes dilation coeff.)

    // FIFO control inputs
    input logic                         i_clearfifo,        // Clear signal for FIFO
    input logic                         i_pipeline_en,      // Systolic Array pipeline enable
    input logic                         i_pop_en,           // FIFO pop enable

	// Control Outputs
    output logic                        o_done, 	        // Current context counters done flag
    output logic                        o_til_done, 	    // Tiling counters done flag
    output logic [ADRA_W-1:0]           o_srama_addr,       // Address towards SRAMA
    output logic                        o_srama_rden,       // Read Enable for SRAMA
	output logic                        o_fifo_empty, 	    // FIFO empty flag (any)
    output logic                        o_fifo_full, 	    // FIFO full flag (any)
    output logic                        o_feeder_stall,     // Feeder stall flag (any)

    // Status Outputs
    output logic                        o_act_deadlock,     // Deadlock flag

    // Data Outputs
	output logic [0:Y-1][IA_W-1:0]      o_a_arr             // Activation feeding stream

);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam SRAMA_N = SRAMA_W/IA_W;
localparam WOFS_W = $clog2(SRAMA_N);

// Index counter -> Row feeders
logic [WOFS_W-1:0]  glob_woffs;
logic               x_ov_flag_d, x_ov_flag_q;

// Internal signals
logic [0:Y-1]       fifo_empty, fifo_full, stall;
logic               fifo_empty_any, fifo_full_any, stall_any;
logic               feeders_update, feeders_update_q1;
logic               valid_q1, valid_q2, start_q, valid_data;      // Needs shimming
logic               pipeline_regs_en, cnt_en;
logic               finalpush_q1, finalpush_q2;                     // For shimming
logic               outbounds, outbounds_q1, outbounds_q2, outbounds_q3;

logic [0:Y-1][IA_W-1:0]         lane_dout;

// Data bus register
logic [SRAMA_W-1:0]             sram_data_q;

// Muxed signals
logic [SRAMA_W-1:0]             srama_data_mux;
logic [WOFS_W-1:0]              glob_woffs_mux;
logic [0:Y-1][PARAMS_W-1:0]     loc_woffs_mux;
logic [0:DILP_W-1]              Dil_pat_mux;

// FIFO full signal shimming => To equalize with SRAM rden latency
logic                           fifo_full_any_shim;

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
        start_q <= 0;
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
            start_q <= 0;
            valid_q1 <= 0;
            valid_q2 <= 0;
            outbounds_q1 <= 0;
            outbounds_q2 <= 0;
            outbounds_q3 <= 0;

        end else if (pipeline_regs_en) begin
            finalpush_q1 <= i_finalpush;
            finalpush_q2 <= finalpush_q1;
            start_q <= i_start;
            valid_q1 <= i_act_valid;
            valid_q2 <= valid_q1;
            outbounds_q1 <= outbounds;
            outbounds_q2 <= outbounds_q1;
            outbounds_q3 <= outbounds_q2;
        end
    end
end

assign valid_data = (i_act_valid && !(outbounds_q1)) || i_finalpush || stall_any;

// ---------------------------------------------------------------------------------
// X overflow flag shimming register => Flag must be aligned with first new woffs
// ---------------------------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : x_ov_flag_reg
    if(~i_rstn) begin
        x_ov_flag_q <= 0;
    end else begin

        // Synchronous reset
        if (i_feeder_clear) begin
            x_ov_flag_q <= 0;

        end else if (pipeline_regs_en) begin
            x_ov_flag_q <= x_ov_flag_d;
        end
    end
end

// Force flag when start and finish periods
assign x_transition_flag = x_ov_flag_q | start_q | i_finalpush;

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
            sram_data_q <= i_srama_data;
        end
    end
end

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// Global Index Counters
ifmap_idxcnt #(
        .IDX_W(IDX_W),
        .ADRA_W(ADRA_W),
        .WOFS_W(WOFS_W),
        .PARAMS_W(PARAMS_W)
    ) ifmap_idxcnt_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_cnt_en	    (cnt_en),
        .i_cnt_clear    (i_cnt_clear),
        .i_finalctx     (i_finalctx),
        .i_xlim	        (i_xlim),
        .i_xstep        (i_xstep),
        .i_ylim         (i_ylim),
        .i_ystep        (i_ystep),
        .i_chlim        (i_chlim),
        .i_chstep       (i_chstep),
        .i_til_xlim	    (i_til_xlim),
        .i_til_xstep    (i_til_xstep),
        .i_til_ylim     (i_til_ylim),
        .i_til_ystep    (i_til_ystep),

        .o_x_ov_flag    (x_ov_flag_d),
        .o_sram_addr    (o_srama_addr),
        .o_woffs	    (glob_woffs),
        .o_outbounds    (outbounds),
        .o_done	        (o_done),
        .o_til_done	    (o_til_done));

// Row Feeders (along Y dimension)
genvar jj;
    generate
        for (jj=0; jj < Y; jj++) begin : y_axis

            feed_xy_lane #(
                    .FIFO_POSITIONS(FIFO_POSITIONS),
                    .I_W(IA_W),
                    .WOFS_W(WOFS_W),
                    .SRAM_W(SRAMA_W),
                    .DILP_W(DILP_W),
                    .PARAMS_W(PARAMS_W),
                    .M(M)
            ) ifmap_feeder_i
                   (.i_clk          (i_clk),
                    .i_rstn         (i_rstn),
                    
                    .i_sram_data   (srama_data_mux),
                    .i_feeder_en    (i_feeder_en && i_rows_active[jj]),    // Row Active to zero overrides feeder enable
                    .i_update       (feeders_update),
                    .i_clearbuff    (i_feeder_clear),
                    .i_valid_data	(valid_data),
                    .i_x_ov_flag    (x_transition_flag),
                    .i_glob_woffs   (glob_woffs_mux),
                    .i_loc_woffs    (loc_woffs_mux[jj]),
                    .i_Dil_pat      (Dil_pat_mux),
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
                .I_W(IA_W)
            ) feed_registers_i
                   (.i_clk          (i_clk),
                    .i_rstn         (i_rstn),
                    
                    .i_clear        (i_clearfifo),
                    .i_pipeline_en  (i_pipeline_en),

                    .i_din          (lane_dout[jj]),
                    .o_dout	        (o_a_arr[jj]));

        end
    endgenerate

// -----------------------------------------------------------------
// Signal muxing => During final push some have special fix values
// -----------------------------------------------------------------

assign srama_data_mux = (finalpush_q2)      ? '{default: 0} : sram_data_q;
assign glob_woffs_mux = (i_finalpush)       ? '{default: 0} : glob_woffs;
assign loc_woffs_mux =  (i_finalpush)       ? '{default: 0} : i_loc_woffs;
assign Dil_pat_mux =    (finalpush_q1)      ? '{default: 1} : i_Dil_pat;

// -----------------------------------
// Reduction of flag signals
// -----------------------------------

always_comb begin

    fifo_empty_any = 0;
    fifo_full_any = 0;
    stall_any = 0;

    for (integer j=0; j < Y; j++) begin
        fifo_empty_any = fifo_empty_any | (fifo_empty[j] && i_rows_active[j]);     // Row Active to zero overrides fifo empty
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
assign o_srama_rden = feeders_update;
assign o_fifo_full = fifo_full_any;
assign o_feeder_stall = stall_any;

assign o_act_deadlock = fifo_empty_any & fifo_full_any;

endmodule 
