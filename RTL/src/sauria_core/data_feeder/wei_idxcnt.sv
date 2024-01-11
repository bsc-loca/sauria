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

module wei_idxcnt #(
    parameter IDX_W = 11,
    parameter ADRB_W = 8,
    parameter WOFS_W = 3,
    parameter PARAMS_W = 8
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Control Inputs
    input  logic					i_cnt_en,           // Counters Enable
    input  logic                    i_cnt_clear,        // Counters Clear signal
    input  logic                    i_cswitch,          // Context switch enable -> Control of repetitions

    input  logic                    i_waligned,         // Bit that indicates if weight values are aligned in memory (better perf.)
    input  logic [IDX_W-1:0]		i_auxlim,           // Idx Counters : Auxiliary counter limit
    input  logic [IDX_W-1:0]		i_auxstep,          // Idx Counters : Auxiliary counter step        
    input  logic [IDX_W-1:0]		i_wlim,             // Idx Counters : Weight counter limit
    input  logic [IDX_W-1:0]		i_wstep,            // Idx Counters : Weight counter step size
    input  logic [IDX_W-1:0]		i_til_klim,         // Idx Counters : Tiling Out Channel counter limit
    input  logic [IDX_W-1:0]		i_til_kstep,        // Idx Counters : Tiling Out Channel counter step size

	// Control Outputs
    output logic                    o_transn,           // Inverted transition flag => for unaligned transitions
    output logic [ADRB_W-1:0]       o_sram_addr, 	    // SRAM address to read
    output logic [WOFS_W-1:0]       o_woffs, 	        // Word Offset to read
    output logic                    o_outbounds,        // Data out of bounds after Tiling Done
    output logic                    o_done, 	        // Done flag (all positions finished for current context)
    output logic                    o_til_done 	        // Tiling Done flag (all positions finished for all contexts)
);

// ----------
// SIGNALS
// ----------

// Counter signals
logic                   w_ov_flag, til_k_ov_flag, aux_ov_flag;
logic [IDX_W-1:0]       aux_idx, w_idx, til_k_idx;

// Intermediate flags
logic                   aux_flag, w_flag, tilk_flag;
logic                   cnt_clear_q;

// Addresses and Word Offsets
logic [IDX_W-1:0]       sram_idx_d, sram_idx_q;

// Address transition flag
logic                   transition_flag, transition_q1, transition_q2;

// Final shimming
logic [WOFS_W-1:0]      woffs_outshim;
logic                   outbounds_outshim;

// Output registers
logic                   done_d, done_q, til_done_d, til_done_q, outbounds_q;

// Auxiliary counter enable
logic   i_aux_cnt;
assign  i_aux_cnt = (i_auxlim > 1);

// ---------------------------------------
// Activation flags (EN of next counter)
// ---------------------------------------

assign aux_flag = aux_ov_flag;
assign w_flag = aux_ov_flag & w_ov_flag;
assign tilk_flag = aux_ov_flag & w_ov_flag & til_k_ov_flag;

// --------------------------
// Counters instantiation
// --------------------------

// Auxiliary counter - Used only when word repetition is needed
cnt_generic #(
        .CNT_W(IDX_W)
    ) aux_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_auxlim),
        .i_step	(i_auxstep),
        .i_en	(i_cnt_en),
        .i_clear(i_cnt_clear),

        .o_flag (aux_ov_flag),
        .o_cnt  (aux_idx));

// W counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) w_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_wlim),
        .i_step	(i_wstep),
        .i_en	(i_cnt_en && aux_flag && (!transition_flag || i_aux_cnt)),
        .i_clear(i_cnt_clear),

        .o_flag (w_ov_flag),
        .o_cnt  (w_idx));

// Tiling K counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) til_k_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_til_klim),
        .i_step	(i_til_kstep),
        .i_en	(i_cnt_en && w_flag && i_cswitch),
        .i_clear(i_cnt_clear),

        .o_flag (til_k_ov_flag),
        .o_cnt  (til_k_idx));

// ------------------------
// Partial Index Adder
// ------------------------

assign sram_idx_d = aux_idx + w_idx + til_k_idx;

// ------------------------
// Transition flag
// ------------------------

always_comb begin
    
    if (i_aux_cnt) begin
        transition_flag = aux_ov_flag;

    end else begin
        transition_flag = (sram_idx_q[IDX_W-1:WOFS_W] != sram_idx_d[IDX_W-1:WOFS_W]) && (!i_waligned);
    end
end

// ------------------------
// Registers
// ------------------------

assign done_d = w_flag          && (!transition_flag || i_aux_cnt);
assign til_done_d = tilk_flag   && (!transition_flag || i_aux_cnt);

always_ff @(posedge i_clk or negedge i_rstn) begin : gen_reg
    if(~i_rstn) begin
        sram_idx_q <= 0;
        done_q <= 0;
        til_done_q <= 0;
        transition_q1 <= 0;
    end else begin

        // Synchronous reset
        if (i_cnt_clear) begin
            sram_idx_q <= 0;
            done_q <= 0;
            til_done_q <= 0;
            transition_q1 <= 0;

        // SRAM index register & done flag are gated by counter enable (pipeline stall)
        end else if (i_cnt_en) begin
            sram_idx_q <= sram_idx_d;
            done_q <= done_d;
            til_done_q <= til_done_d;
            transition_q1 <= transition_flag;
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
        end else if (i_cnt_en && til_done_q && i_cswitch) begin
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
        transition_q2 <= 0;
        outbounds_outshim <= 0;
    end else begin

        // Synchronous reset signal
        if (i_cnt_clear) begin
            woffs_outshim <= 0;
            transition_q2 <= 0;
            outbounds_outshim <= 0;   // Should not be reset by cnt_clear

        // SRAM index register & done flag are gated by counter enable (pipeline stall)
        end else if (i_cnt_en) begin
            woffs_outshim <=        sram_idx_q[WOFS_W-1:0];
            transition_q2 <=        transition_q1;
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
assign o_transn =       !transition_q2;
assign o_done =         done_q              & i_cnt_en;
assign o_til_done =     til_done_q          & i_cnt_en;

endmodule 
