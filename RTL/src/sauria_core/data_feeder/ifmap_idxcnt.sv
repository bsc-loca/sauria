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

module ifmap_idxcnt #(
    parameter IDX_W = 11,
    parameter ADRA_W = 8,
    parameter WOFS_W = 3,
    parameter PARAMS_W = 8
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Control Inputs
    input  logic					i_cnt_en,           // Counters Enable
    input  logic                    i_cnt_clear,        // Counters Clear signal
    input  logic                    i_finalctx,         // Final context flag -> Current tile is last

    input  logic [IDX_W-1:0]		i_xlim,             // Idx Counters : X counter limit
    input  logic [IDX_W-1:0]		i_xstep,            // Idx Counters : X counter step size
    input  logic [IDX_W-1:0]		i_ylim,             // Idx Counters : Y counter limit
    input  logic [IDX_W-1:0]		i_ystep,            // Idx Counters : Y counter step size
    input  logic [IDX_W-1:0]		i_chlim,            // Idx Counters : In-Channel counter limit
    input  logic [IDX_W-1:0]		i_chstep,           // Idx Counters : In-Channel counter step size
    input  logic [IDX_W-1:0]		i_til_xlim,         // Idx Counters : Tiling x counter limit
    input  logic [IDX_W-1:0]		i_til_xstep,        // Idx Counters : Tiling x counter step size
    input  logic [IDX_W-1:0]		i_til_ylim,         // Idx Counters : Tiling y counter limit
    input  logic [IDX_W-1:0]		i_til_ystep,        // Idx Counters : Tiling y counter step size

	// Control Outputs
	output logic                    o_x_ov_flag, 	    // X index overflow flag
    output logic [ADRA_W-1:0]       o_sram_addr, 	    // SRAM address to read
    output logic [WOFS_W-1:0]       o_woffs, 	        // Word Offset to read
    output logic                    o_outbounds,        // Data out of bounds after Tiling Done
    output logic                    o_done, 	        // Done flag (all positions finished for current context)
    output logic                    o_til_done 	        // Tiling Done flag (all positions finished for all contexts)
);

// ----------
// SIGNALS
// ----------

// Counter signals
logic                   x_ov_flag, x_ov_flag_q, y_ov_flag, ch_ov_flag, til_x_ov_flag, til_y_ov_flag;
logic [IDX_W-1:0]       x_idx;
logic [IDX_W-1:0]       y_idx, ch_idx, til_x_idx, til_y_idx;

// Index sums
logic [IDX_W-1:0]       xy_idx, glob_idx, chg_idx, sram_idx_d, sram_idx_q;

// Intermediate flags
logic                   x_flag, xy_flag, xyc_flag, tilx_flag, tilxy_flag;
logic                   cnt_clear_q;

// Final shimming
logic [WOFS_W-1:0]      woffs_outshim;
logic                   x_ov_flag_outshim;
logic                   outbounds_outshim;

// Output registers
logic                   done_d, done_q, til_done_d, til_done_q, outbounds_q;

// ---------------------------------------
// Activation flags (EN of next counter)
// ---------------------------------------

assign x_flag = x_ov_flag;
assign xy_flag = x_ov_flag & y_ov_flag;
assign xyc_flag = x_ov_flag & y_ov_flag & ch_ov_flag;

assign tilx_flag = x_ov_flag & y_ov_flag & ch_ov_flag & til_x_ov_flag;
assign tilxy_flag = x_ov_flag & y_ov_flag & ch_ov_flag & til_x_ov_flag & til_y_ov_flag;

// --------------------------
// Counters instantiation
// --------------------------

// X counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) x_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_xlim),
        .i_step	(i_xstep),
        .i_en	(i_cnt_en),
        .i_clear(i_cnt_clear),

        .o_flag (x_ov_flag),
        .o_cnt  (x_idx));

// Y counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) y_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_ylim),
        .i_step	(i_ystep),
        .i_en	(i_cnt_en && x_flag),
        .i_clear(i_cnt_clear),

        .o_flag (y_ov_flag),
        .o_cnt  (y_idx));

// Channel counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) ch_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_chlim),
        .i_step	(i_chstep),
        .i_en	(i_cnt_en && xy_flag),
        .i_clear(i_cnt_clear),

        .o_flag (ch_ov_flag),
        .o_cnt  (ch_idx));

// Tiling X counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) til_x_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_til_xlim),
        .i_step	(i_til_xstep),
        .i_en	(i_cnt_en && xyc_flag),
        .i_clear(i_cnt_clear),

        .o_flag (til_x_ov_flag),
        .o_cnt  (til_x_idx));

// Tiling Y counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) til_y_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_til_ylim),
        .i_step	(i_til_ystep),
        .i_en	(i_cnt_en && tilx_flag),
        .i_clear(i_cnt_clear),

        .o_flag (til_y_ov_flag),
        .o_cnt  (til_y_idx));

// ------------------------
// Partial Index Adders
// ------------------------

assign xy_idx =     x_idx + y_idx;
assign glob_idx =   til_x_idx + til_y_idx;
assign chg_idx =    ch_idx + glob_idx;

assign sram_idx_d = xy_idx + chg_idx;

// ------------------------
// Registers
// ------------------------

assign done_d = xyc_flag;
assign til_done_d = tilxy_flag;

always_ff @(posedge i_clk or negedge i_rstn) begin : woffs_reg
    if(~i_rstn) begin
        sram_idx_q <= 0;
        x_ov_flag_q <= 0;
        done_q <= 0;
        til_done_q <= 0;
    end else begin

        // Synchronous reset signal
        if (i_cnt_clear) begin
            sram_idx_q <= 0;
            x_ov_flag_q <= 0;
            done_q <= 0;
            til_done_q <= 0;

        // SRAM index register & done flag are gated by counter enable (pipeline stall)
        end else if (i_cnt_en) begin
            sram_idx_q <= sram_idx_d;
            x_ov_flag_q <= x_ov_flag;
            done_q <= done_d;
            til_done_q <= til_done_d;
        end
    end
end

// ------------------------
// Out of bounds flag
// ------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : outbounds_reg
    if(~i_rstn) begin
        cnt_clear_q <= 0;
        outbounds_q <= 0;
    end else begin

        cnt_clear_q <= i_cnt_clear;

        // Synchronous reset with cnt_clear falling edge
        if (i_cnt_clear) begin
            outbounds_q <= 0;
        // Set 1 cycle after FINAL o_til_done, reset only when cnt_clear
        end else if (i_cnt_en && til_done_q && i_finalctx) begin
            outbounds_q <= 1;
        end
    end
end

// ---------------------------------------------------------
// Final shimming => Equalization with SRAM input pipeline
// ---------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : out_shimming_reg
    if(~i_rstn) begin
        woffs_outshim <= 0;
        x_ov_flag_outshim <= 0;
        outbounds_outshim <= 0;
    end else begin

        // Synchronous reset signal
        if (i_cnt_clear) begin
            woffs_outshim <= 0;
            x_ov_flag_outshim <= 0;
            outbounds_outshim <= 0;       // Should not be reset by cnt_clear

        // SRAM index register & done flag are gated by counter enable (pipeline stall)
        end else if (i_cnt_en) begin
            woffs_outshim <=        sram_idx_q[WOFS_W-1:0];
            x_ov_flag_outshim <=    x_ov_flag_q;
            outbounds_outshim <=    outbounds_q;
        end
    end
end

// ------------------------
// Output management
// ------------------------

// Addresses
assign o_sram_addr =    sram_idx_q[IDX_W-1:WOFS_W];
assign o_woffs =        woffs_outshim;

// Flags
assign o_outbounds =    outbounds_q;
assign o_x_ov_flag =    x_ov_flag_outshim   & i_cnt_en;
assign o_done =         done_q              & i_cnt_en;
assign o_til_done =     til_done_q          & i_cnt_en;

endmodule 
