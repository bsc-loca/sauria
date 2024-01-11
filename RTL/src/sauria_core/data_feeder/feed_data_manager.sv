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

module feed_data_manager #(
    parameter I_W = 16,
    parameter WOFS_W = 3,
    parameter SRAM_W = 128,
    parameter DILP_W = 64,
    parameter PARAMS_W = 8,
    parameter M = 3,

    localparam FIFO_W = M*I_W
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [SRAM_W-1:0]       i_sram_data,        // Data bus from SRAM - Must have latency 2 wrto address
	
	// Control Inputs
    input  logic					i_feeder_en,        // Global pipeline enable (for stalls)
    input  logic					i_update,           // Address update flag
    input  logic                    i_clearbuff,        // High clears the buffer control signals
    input  logic                    i_valid_data,       // Valid data flag, propagates with pipeline
    input  logic					i_fifo_full,        // FIFO full flag
    input  logic                    i_x_ov_flag,        // X transition flag that marks a new glob_woffs
	input  logic [WOFS_W-1:0]	    i_glob_woffs,       // Word offset from Globlal counter
	input  logic [PARAMS_W-1:0]	    i_loc_woffs,        // Word offset from local position
    input  logic [0:DILP_W-1]	    i_Dil_pat,          // Config Parameter: Dilated pattern (incl Filter width)
    input  logic                    i_finalpush,        // Final push flag

	// Control Outputs
	output logic                    o_fifo_push, 	    // Push signal towards FIFO
    output logic                    o_stall,            // Stall flag to maintain the current data word

    // Data Outputs
	output logic [FIFO_W-1:0]       o_fifo_din          // Output data bus towards FIFO

);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam SRAM_N = SRAM_W/I_W;
localparam N_BUFS_TOTAL = M;
localparam N_CNT_BITS = $clog2(SRAM_N+1);
localparam M_CNT_BITS = $clog2(M+1);

// Registers enable
logic pipeline_regs_en;

// Input reshape
logic [0:SRAM_N-1][I_W-1:0] sram_elements;

// Valid data propagation (sync with pipeline stages)
logic valid_data_q1;

// Word Offset computation
logic [PARAMS_W-1:0]        woffs_init_d, woffs_init_q;

// Shift index counter
logic [PARAMS_W-1:0]        shift_idx_cnt_d, shift_idx_cnt_q;
logic [PARAMS_W-1:0]        last_rd;

// Dilation pattern shift
logic                       dil_shift_idx_sign;
logic [PARAMS_W:0]          dil_shift_idx, dil_shift_idx_inv;
logic [0:SRAM_N-1]          lshifted_dil_pat, rshifted_dil_pat, shifted_dil_pat_d, shifted_dil_pat_q, final_dil_pat;

// Read pointer
logic [PARAMS_W-1:0]        read_ptr_d, read_ptr_q;

// Interconnection control signals
logic [N_CNT_BITS-1:0]                      elm_number;
logic [M_CNT_BITS-1:0]                      elm_number_sat;
logic [0:SRAM_N-1][N_CNT_BITS-1:0]          par_sums;
logic [0:SRAM_N-1][N_CNT_BITS-1:0]          elm_idx_array;
logic [N_CNT_BITS-1:0]                      regs_used_idx;
logic [N_CNT_BITS:0]                        new_active_idx;
logic [0:N_BUFS_TOTAL-1]                    regs_active_new;

// Registers and maintenance
logic [0:N_BUFS_TOTAL-1]                    regs_active_d, regs_active_q;
logic [0:N_BUFS_TOTAL-1]                    regs_en_d;
logic [0:N_BUFS_TOTAL-1][I_W-1:0]           regs_d, regs_q;
logic [M_CNT_BITS-1:0]                      n_free_regs;

// Multiplexors control
logic [0:SRAM_N-1][N_CNT_BITS-1:0]          target_array;
logic [0:N_BUFS_TOTAL-1][N_CNT_BITS-1:0]    mux_control_array;

// Control signals
logic fifo_push;

// Output reshape and muxing
logic [FIFO_W-1:0] regs_obus;


// ------------------------------------------------------------
// General pipeline reg enable
// ------------------------------------------------------------

assign pipeline_regs_en = i_feeder_en & i_update & (!i_fifo_full);

// ------------------------------------------------------------
// IO Mapping - Wide SRAM bus to element array and vice versa
// ------------------------------------------------------------

genvar ii;
generate
    for (ii=0; ii < SRAM_N; ii++) begin
        // Input values
        assign sram_elements[ii] = i_sram_data[ii*I_W+:I_W];
    end
endgenerate

genvar k;
generate
    for (k=0; k < M; k++) begin
        // Output values
        assign regs_obus[k*I_W+:I_W] = regs_q[k];
    end
endgenerate

// ------------------------
// Valid Data Registers
// ------------------------

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : valid_data_reg
    if(~i_rstn) begin
        valid_data_q1 <= 0;
    end else begin

        if (i_clearbuff) begin
            valid_data_q1 <= 0;
        end else if (pipeline_regs_en) begin
            valid_data_q1 <= i_valid_data;
        end
    end
end

// ------------------------
// Word Offset computation
// ------------------------

assign woffs_init_d = i_glob_woffs + i_loc_woffs;

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : woffs_reg
    if(~i_rstn) begin
        woffs_init_q <= 0;
    end else begin

        if (i_clearbuff) begin
            woffs_init_q <= 0;
        end else if (pipeline_regs_en && (i_x_ov_flag)) begin
            woffs_init_q <= woffs_init_d;
        end
    end
end

// -------------------------------------
// Dilated pattern shift index Counter
// -------------------------------------

// Comb Logic
always_comb begin
    if (i_x_ov_flag) begin
        shift_idx_cnt_d = 0;
    end else begin
        shift_idx_cnt_d = shift_idx_cnt_q + SRAM_N;
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : shift_cnt_reg
    if(~i_rstn) begin
        shift_idx_cnt_q <= 0;
    end else begin

        if (i_clearbuff) begin
            shift_idx_cnt_q <= 0;
        end else if (pipeline_regs_en) begin
            shift_idx_cnt_q <= shift_idx_cnt_d;
        end
    end
end

// -------------------------------------
// Final shift index & sign flag
// -------------------------------------

always_comb begin

    dil_shift_idx = shift_idx_cnt_q - woffs_init_q;
    dil_shift_idx_inv = 0 - dil_shift_idx;              // Is the compiler smart enough to see this as a proper inversion?
    dil_shift_idx_sign = dil_shift_idx[PARAMS_W];

end

// -------------------------------------
// Dilation pattern shifts and muxing
// -------------------------------------

always_comb begin

    // Default to zero
    lshifted_dil_pat = 0;
    rshifted_dil_pat = 0;

    for (integer i=0; i < SRAM_N; i++) begin

        // Right Shift
        if (dil_shift_idx_inv>i) begin          // If the left boundary is exceeded, just put a zero 
            rshifted_dil_pat[i] = 0;
        end else begin
            rshifted_dil_pat[i] = i_Dil_pat[i - dil_shift_idx_inv];
        end
        
        // Left Shift
        if (dil_shift_idx>(DILP_W-1-i)) begin         // If the right boundary is exceeded, just put a zero
            lshifted_dil_pat[i] = 0;
        end else begin
            lshifted_dil_pat[i] = i_Dil_pat[i + dil_shift_idx];
        end
        
    end

    // Valid data gating and muxing
    if (valid_data_q1) begin
        // Choose according to sign
        if (dil_shift_idx_sign) begin
            shifted_dil_pat_d = rshifted_dil_pat;
        end else begin
            shifted_dil_pat_d = lshifted_dil_pat;
        end

    // If data is not yet valid, must force zero (otherwise we start saving garbage)
    end else begin
        shifted_dil_pat_d = 0;
    end

end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : dil_pat_reg
    if(~i_rstn) begin
        shifted_dil_pat_q <= 0;
    end else begin

        if (i_clearbuff) begin
            shifted_dil_pat_q <= 0;
        end else if (pipeline_regs_en) begin
            shifted_dil_pat_q <= shifted_dil_pat_d;
        end
    end
end

// -------------------------------------
// Read pointer counter
// -------------------------------------

// Comb Logic
always_comb begin
    if (i_update) begin
        read_ptr_d = 0;
    end else begin

        // If anything was read, point to last read + 1
        if (regs_en_d != '0) begin
            read_ptr_d = last_rd + 1;

        // If nothing was read, maintain pointer value
        end else begin
            read_ptr_d = read_ptr_q;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : ptr_cnt_reg
    if(~i_rstn) begin
        read_ptr_q <= 0;
    end else begin
        if (i_feeder_en && (!i_fifo_full)) begin
            read_ptr_q <= read_ptr_d;
        end
    end
end

// ------------------------------------------------------------------------------
// Final dilation pattern => Positions smaller than read_ptr_q are invalidated
// ------------------------------------------------------------------------------

always_comb begin

    final_dil_pat = '0;

    for (integer i=0; i < SRAM_N; i++) begin
        if (read_ptr_q <= i) begin
            final_dil_pat[i] = shifted_dil_pat_q[i];
        end else begin
            final_dil_pat[i] = 1'b0;
        end
    end
end

// -------------------------------------------------
// Element Index Array generation
// -------------------------------------------------

always_comb begin
    
    elm_idx_array = 0;
    par_sums = 0;

    // ELEMENT INDEX -> Number associated with each input element from SRAM input
    for (integer i=0; i < SRAM_N; i++) begin

        // Element 0 is a special case -> Will always be zero
        if (i==0) begin
            elm_idx_array[i] = 0;
            par_sums[i] = final_dil_pat[i];     // Read pointer >i invalidates the pattern

        end else begin

            // Only if position is active AND read pointer is smaller or equal allow the count outside
            if (final_dil_pat[i]) begin

                elm_idx_array[i] = par_sums[i-1];
                par_sums[i] = par_sums[i-1] + 1;

            // If inactive we leave at zero and propagate the value
            end else begin

                elm_idx_array[i] = 0;
                par_sums[i] = par_sums[i-1];
            end
        end
    end

    // Number of elements is just the last par_sums value
    elm_number = par_sums[SRAM_N-1];

end

// -------------------------------------------------
// Stall output generation
// -------------------------------------------------

assign o_stall = (elm_number > n_free_regs) && (!i_finalpush);

// ----------------------------------------------------------------
// Generation of Interconnect Control signals
// ----------------------------------------------------------------

always_comb begin
    
    // Registers Used Index -> Look for 1 crossing in regs_active_q
    regs_used_idx = 0;
    
    for (integer i=1; i<N_BUFS_TOTAL; i++) begin
        // When current location is 0 and previous location was 1, we take index   
        if ((!regs_active_q[i]) && regs_active_q[i-1]) begin
            regs_used_idx = i;
        end
    end

    // Saturation for element number => we can take maximum n_free_regs
    if (elm_number>n_free_regs) begin
        elm_number_sat = n_free_regs;
    end else begin
        elm_number_sat = elm_number;
    end

    // New Active Index -> Last index of values to be written
    new_active_idx = regs_used_idx + elm_number_sat;
    
    // Regs Active New -> Marks positions to be written to
    regs_active_new = 0;
    
    for (integer b=0; b<N_BUFS_TOTAL; b++) begin
        // Set bits to 1 between Registers Used Index and New Active Index
        if ((b>=regs_used_idx) && (b<new_active_idx)) begin
            regs_active_new[b] = 1'b1;
        end
    end
end

// ----------------------------------------------------------------
// Register and status maintainance
// ----------------------------------------------------------------

always_comb begin

    // Default states
    regs_active_d = regs_active_q;
    regs_en_d = 0;

    // Clear buffer signal => Immediately clears active flags
    if (i_clearbuff) begin
        regs_active_d = 0;

    // Normal operation => Enabled by feeder_en, disabled by fifo_full
    end else if (i_feeder_en && (!i_fifo_full)) begin

        // Fifo push forces all positions to zero on (previous) selected buff
        if (fifo_push) begin
            regs_active_d = 0;
        end

        // Registers Enable values have been computed already as regs_active_new
        regs_en_d = regs_active_new;

        // New Active Registers achieved by simpli ORing the old and the new
        regs_active_d = regs_active_d | regs_active_new;

    end
end

// ----------------------------------------------------------------
// Generation of multiplexor control signals
// ----------------------------------------------------------------

always_comb begin

    target_array = 0;
    mux_control_array = 0;
    last_rd = 0;

    // Target location is obtained by adding regs_used_idx to active positions of elm_idx_array
    for (integer i=0; i<SRAM_N; i++) begin

        // If position is active AND read pointer is smaller or equal, select target
        if (final_dil_pat[i]) begin
            target_array[i] = elm_idx_array[i] + regs_used_idx + 1;     // +1 to distinguish from zeros (unused)

            // Last read position is the last location (+1) with a value that fits in the registers
            if (target_array[i]<=M) begin
                last_rd = i;
            end

        end else begin
            target_array[i] = 0;
        end
    end

    // Target control is the index on which target == register index
    for (integer j=0; j<M; j++) begin
        for (integer ii=0; ii<SRAM_N; ii++) begin
            
            if (target_array[ii]==(j+1)) begin

                mux_control_array[j] = ii;
            
            end
        end
    end
end

// ----------------------------------------------------------------
// Registers and Muxes
// ----------------------------------------------------------------

genvar jj;
generate
    // Generate one instance per position
    for (jj=0; jj < M; jj++) begin

        // Input multiplexors
        always_comb begin

            regs_d[jj] = sram_elements[0];          // Default to first SRAM position

            // Check all other positions and select acc. to control
            for (integer i=1; i<SRAM_N; i++) begin
                if (mux_control_array[jj] == i) begin
                    regs_d[jj] = sram_elements[i];
                end
            end
        end

        // FFs
        always_ff @(posedge i_clk or negedge i_rstn) begin : main_regs
            if(~i_rstn) begin
                regs_q[jj] <= 0;
                regs_active_q[jj] <= 0;
            end else begin

                regs_active_q[jj] <= regs_active_d[jj];

                // Registers update
                if (regs_en_d[jj]) begin
                    regs_q[jj] <= regs_d[jj];
                end
            end
        end
    end
endgenerate

// ----------------------------------
// FIFO push logic & Free registers
// ----------------------------------

always_comb begin

    fifo_push = 0;
    n_free_regs = 0;

    // Count how many registers are free
    for (integer j=0; j<M; j++) begin
        if (!regs_active_q[j]) begin
            n_free_regs = n_free_regs + 1;
        end
    end

    // Only push values if FIFO is not full and feeder is active
    if ((!i_fifo_full) && i_feeder_en) begin

        // All reg positions full
        if (n_free_regs == 0) begin
            fifo_push = 1;
            n_free_regs = M;            // When we issue a push, registers become free for the next cycle
        end
    end
end

// ------------------------------
// Output management
// ------------------------------

assign o_fifo_din = regs_obus;
assign o_fifo_push = fifo_push;

endmodule 
