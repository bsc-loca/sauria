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

module psm_idxcnt #(
    parameter IDX_W = 11,
    parameter WOFS_W = 3,
    parameter ADRC_W = 8,
    parameter SRAMC_N = 2
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Control Inputs
    input  logic					i_cnt_en,           // Counters Enable
    input  logic                    i_cnt_clear,        // Counters Clear signal
    input  logic					i_start,            // Start flag
    input  logic                    i_wr_flag,          // Write flag

    input  logic [IDX_W-1:0]		i_cxlim,            // Idx Counters : X counter limit
    input  logic [IDX_W-1:0]		i_cxstep,           // Idx Counters : X counter step size
    input  logic [IDX_W-1:0]		i_cklim,            // Idx Counters : Channel counter limit
    input  logic [IDX_W-1:0]		i_ckstep,           // Idx Counters : Channel counter step size
    input  logic [IDX_W-1:0]		i_til_cylim,        // Idx Counters : Tiling X-Y counter limit
    input  logic [IDX_W-1:0]		i_til_cystep,       // Idx Counters : Tiling X-Y counter step size
    input  logic [IDX_W-1:0]		i_til_cklim,        // Idx Counters : Tiling Out-Channel counter limit
    input  logic [IDX_W-1:0]		i_til_ckstep,       // Idx Counters : Tiling Out-Channel counter step size
    
	// Control Outputs
    output logic [0:SRAMC_N-1]      o_mask, 	        // Mask that indicates the location of active data elements in the bus
    output logic                    o_wr_fifo_pop,      // Pop (shift) flag towards buffer
    output logic [ADRC_W-1:0]       o_sram_addr, 	    // SRAM address
    output logic                    o_done, 	        // Done flag (all positions finished for current context)
    output logic                    o_til_done 	        // Tiling Done flag (all positions finished for all contexts)
);

// ----------
// SIGNALS
// ----------

// Counter signals
logic                   x_ov_flag, k_ov_flag, til_xy_ov_flag, til_k_ov_flag;
logic [IDX_W-1:0]       x_idx, k_idx, til_xy_idx, til_k_idx;

// Index sums -> Must be able to stand an overflow (+1 bit)
logic [IDX_W:0]         til_idx, kk_idx, sram_idx_d;
logic [IDX_W:0]         idx_end, idx_zero_current;
logic                   last_pos_flag;

// Intermediate flags
logic                   x_flag, xk_flag, til_xy_flag, til_xyk_flag;
logic                   transition_flag_d, transition_flag_q;

// Addresses and Word Offsets -> Addresses must be able to stand an overflow (+1 bit)
logic [ADRC_W:0]        sram_addr_d, sram_addr_q;
logic [WOFS_W-1:0]      woffs_d, woffs_end;

// Masks
logic [0:SRAMC_N-1]     mask_d, mask_d_mux, mask_q;

// Final shimming
logic [0:SRAMC_N-1]     mask_outshim;
logic                   done_outshim, til_done_outshim, wr_fifo_pop_outshim;

// Output registers
logic                   done_d, done_q, til_done_d, til_done_q, outbounds_q;

// ---------------------------------------
// Activation flags (EN of next counter)
// ---------------------------------------

assign x_flag = x_ov_flag;
assign xk_flag = x_ov_flag & k_ov_flag;
assign til_xy_flag = x_ov_flag & k_ov_flag & til_xy_ov_flag;
assign til_xyk_flag = x_ov_flag & k_ov_flag & til_xy_ov_flag & til_k_ov_flag;

// --------------------------
// Counters instantiation
// --------------------------

// X counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) x_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_cxlim),
        .i_step	(i_cxstep),
        .i_en	(i_cnt_en),
        .i_clear(i_cnt_clear || (!i_cnt_en)),   // Clear when disabled to clean the value between RD and WR

        .o_flag (x_ov_flag),
        .o_cnt  (x_idx));

// K counter
cnt_generic #(
        .CNT_W(IDX_W)
    ) k_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_cklim),
        .i_step	(i_ckstep),
        .i_en	(i_cnt_en && x_flag),
        .i_clear(i_cnt_clear || (!i_cnt_en)),   // Clear when disabled to clean the value between RD and WR

        .o_flag (k_ov_flag),
        .o_cnt  (k_idx));

// Tiling XY counter
cnt_dualctx #(
        .CNT_W(IDX_W)
    ) til_xy_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_til_cylim),
        .i_step	(i_til_cystep),
        .i_en	(i_cnt_en && xk_flag),
        .i_clear(i_cnt_clear),
        .i_sel(i_wr_flag),

        .o_flag (til_xy_ov_flag),
        .o_cnt  (til_xy_idx));

// Tiling K counter
cnt_dualctx #(
        .CNT_W(IDX_W)
    ) til_k_counter_i
       (.i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_lim	(i_til_cklim),
        .i_step	(i_til_ckstep),
        .i_en	(i_cnt_en && til_xy_flag),
        .i_clear(i_cnt_clear),
        .i_sel(i_wr_flag),

        .o_flag (til_k_ov_flag),
        .o_cnt  (til_k_idx));

// ------------------------
// Partial Index Adders
// ------------------------

assign til_idx =    til_xy_idx + til_k_idx;
assign kk_idx =     til_idx + k_idx;
assign sram_idx_d = x_idx + kk_idx;

// Address & Word Offset
assign sram_addr_d =        sram_idx_d[IDX_W:WOFS_W];
assign woffs_d =            sram_idx_d[WOFS_W-1:0];

// ----------------------------------
// Transition flag logic & register
// ----------------------------------

assign transition_flag_d = (x_flag && i_cnt_en);

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : transition_reg
    if(~i_rstn) begin
        transition_flag_q <= 0;
    end else begin

        if (i_cnt_en && (!i_cnt_clear)) begin
            transition_flag_q <= transition_flag_d;
        end else begin
            transition_flag_q <= 0;
        end
    end
end

// ------------------------
// Mask generation logic
// ------------------------

always_comb begin

    // Current Index Zero: first index of current address
    idx_zero_current = sram_addr_d << WOFS_W;

    // Index End: points to the very last element needed    
    idx_end = kk_idx + i_cxlim - (SRAMC_N + 1);

    // Woffs End: word offset of above
    woffs_end = idx_end[WOFS_W-1:0];

    // Last position flag: indicates when are we reading the last SRAM word
    last_pos_flag = (idx_zero_current + (SRAMC_N-1)) >= idx_end;

    // Mask defaults to zero (should be overwritten)
    mask_d = 0;

    // If the index itself is already larger than idx_end, read nothing
    if (idx_zero_current > idx_end) begin
        mask_d = 0;
    
    // Otherwise, there is something to be read
    end else begin

        // Normally accept all input elements
        mask_d = '{default: 1};

        // If Weight Transition AND Last postion flag
        if ((transition_flag_q || i_start) && last_pos_flag) begin
            mask_d = 0;
            // Set all bits to 1 after rd_woffs_d
            for (integer i=0; i<SRAMC_N; i++) begin
                // Set the bit if the counter points to that bit
                if ((i>=woffs_d) && (i<=woffs_end)) begin
                    mask_d[i] = 1;
                end
            end

        // Weight Transition flag indicates the first weight position
        end else if (transition_flag_q || i_start) begin
            mask_d = 0;
            // Set all bits to 1 after rd_woffs_d
            for (integer i=0; i<SRAMC_N; i++) begin
                // Set the bit if the counter points to that bit
                if (i>=woffs_d) begin
                    mask_d[i] = 1;
                end
            end
        
        // Last position flag indicates the last (but not mutually exclusive!)
        end else if(last_pos_flag) begin
            mask_d = 0;
            // Set all bits to 1 up to rd_woffs_end
            for (integer i=0; i<SRAMC_N; i++) begin
                // Set the bit if the counter points to that bit
                if (i<=woffs_end) begin
                    mask_d[i] = 1;
                end
            end
        end
    end
end

// ------------------------
// Registers
// ------------------------

assign done_d = xk_flag;
assign til_done_d = til_xyk_flag;

always_ff @(posedge i_clk or negedge i_rstn) begin : gen_reg
    if(~i_rstn) begin
        sram_addr_q <= 0;
        mask_q <= 0;
        done_q <= 0;
        til_done_q <= 0;
    end else begin

        // Synchronous reset
        if (i_cnt_clear || (!i_cnt_en)) begin
            sram_addr_q <= 0;
            mask_q <= 0;
            done_q <= 0;
            til_done_q <= 0;

        // SRAM index register & done flag are gated by counter enable (pipeline stall)
        end else if (i_cnt_en) begin
            sram_addr_q <= sram_addr_d;
            mask_q <= mask_d;
            done_q <= done_d;
            til_done_q <= til_done_d;
        end
    end
end

// ---------------------------------------------------------
// Final shimming => Equalization with SRAM input pipeline
// ---------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : out_shimming_reg
    if(~i_rstn) begin
        mask_outshim <= 0;
        done_outshim <= 0;
        til_done_outshim <= 0;
        wr_fifo_pop_outshim <= 0;
    end else begin

        // Synchronous reset signal
        if (i_cnt_clear || (!i_cnt_en)) begin
            mask_outshim <= 0;
            done_outshim <= 0;
            til_done_outshim <= 0;
            wr_fifo_pop_outshim <= 0;

        // SRAM index register & done flag are gated by counter enable (pipeline stall)
        end else if (i_cnt_en) begin
            mask_outshim <=         mask_q;
            done_outshim <=         done_q;
            til_done_outshim <=     til_done_q;
            wr_fifo_pop_outshim <=  transition_flag_q & i_wr_flag;
        end
    end
end

// ------------------------
// Output management
// ------------------------

assign o_sram_addr =        sram_addr_q[ADRC_W-1:0];
assign o_wr_fifo_pop =      wr_fifo_pop_outshim;

// Silence when disabled or when start and wr_flag => Otherwise it might wrongly enable some residual values from last
assign o_mask =             (((!i_cnt_en) && !(done_outshim))||(i_start && i_wr_flag))? 0 : mask_outshim;     

// Flags
assign o_done =         done_q & i_cnt_en;
assign o_til_done =     til_done_q & i_cnt_en;

endmodule 
