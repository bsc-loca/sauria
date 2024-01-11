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

module feed_xy_lane #(
    parameter FIFO_POSITIONS = 8,
    parameter I_W = 16,
    parameter WOFS_W = 3,
    parameter SRAM_W = 128,
    parameter DILP_W = 64,
    parameter PARAMS_W = 8,
    parameter M = 3
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [SRAM_W-1:0]      i_sram_data,       // Data bus from SRAM - Must have latency 2 wrto address
	
	// Control Inputs
    input  logic					i_feeder_en,        // Global pipeline enable (for stalls)
    input  logic					i_update,           // Address update flag
    input  logic                    i_clearbuff,        // High clears the buffer control signals
    input  logic                    i_valid_data,       // Valid data flag
    input  logic                    i_x_ov_flag,        // X transition flag that marks a new glob_woffs
	input  logic [WOFS_W-1:0]	    i_glob_woffs,       // Word offset from Globlal counter
	input  logic [PARAMS_W-1:0]	    i_loc_woffs,        // Word offset from local position
    input  logic [0:DILP_W-1]	    i_Dil_pat,          // Config Parameter: Dilated pattern (incl Filter width)
    input  logic                    i_finalpush,        // Final push flag

    input logic                     i_clearfifo,        // Clear signal for FIFO
    input logic                     i_pipeline_en,      // Systolic Array pipeline enable
    input logic                     i_pop_en,           // FIFO pop enable (in)

	// Control Outputs
    output logic                    o_stall,            // Stall flag to maintain the current data word
	output logic                    o_fifo_empty, 	    // FIFO empty flag
    output logic                    o_fifo_full, 	    // FIFO full flag

    // Data Outputs
	output logic [I_W-1:0]         o_data               // Activation feeding stream

);

// ----------
// SIGNALS
// ----------

localparam FIFO_W = M*I_W;

// Data manager -> FIFO signals
logic fifo_push;
logic [FIFO_W-1:0]  fifo_din;

// FIFO intermediate signals
logic [I_W-1:0]    fifo_dout;
logic               fifo_empty, fifo_full, fifo_pop;
logic               fifo_empty_q1, fifo_empty_q2;      // Empty signal with shimming

// Pop enable signal propagation
logic               pop_en_q;

// FIFO full signal shimming
logic               fifo_full_shim;

// ------------------------------------------------------------
// Submodule instantiation
// ------------------------------------------------------------

feed_data_manager #(
        .I_W(I_W),
        .WOFS_W(WOFS_W),
        .SRAM_W(SRAM_W),
        .DILP_W(DILP_W),
        .PARAMS_W(PARAMS_W),
        .M(M)
    ) feed_data_manager_i
       (.i_clk      (i_clk),
        .i_rstn     (i_rstn),
        
        .i_sram_data	(i_sram_data),
        .i_feeder_en	(i_feeder_en),
        .i_update	    (i_update),
        .i_clearbuff    (i_clearbuff),
        .i_valid_data	(i_valid_data),
        .i_fifo_full    (fifo_full),
        .i_x_ov_flag    (i_x_ov_flag),
        .i_glob_woffs   (i_glob_woffs),
        .i_loc_woffs    (i_loc_woffs),
        .i_Dil_pat      (i_Dil_pat),
        .i_finalpush    (i_finalpush),

        .o_stall	    (o_stall),
        .o_fifo_push	(fifo_push),
        .o_fifo_din		(fifo_din));

// FF-based FIFO
fifo_memory_ff #(
        .FIFO_POSITIONS(FIFO_POSITIONS),
        .IN_W(FIFO_W),
        .OUT_W(I_W)
    ) fifo_i
        (.i_clk         (i_clk),
        .i_rstn         (i_rstn),
    
        .i_din	        (fifo_din),
        .i_push	        (fifo_push),
        .i_pop          (fifo_pop),
        .i_clearfifo	(i_clearfifo),

        .o_full         (fifo_full),
        .o_empty        (fifo_empty),
        .o_dout         (fifo_dout));

// -----------------------------------
// Pop signal propagation register
// -----------------------------------

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : pop_reg
    if(~i_rstn) begin
        pop_en_q <= 0;
    end else begin
        // Synchronous reset
        if (i_clearfifo) begin
            pop_en_q <= 0;

        end else if (i_pipeline_en) begin
            pop_en_q <= i_pop_en;
        end
    end
end

assign fifo_pop = pop_en_q && i_pipeline_en;

// --------------------------------------------------------------------
// Shimming register for fifo empty - To equalize with data latency
// --------------------------------------------------------------------

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : fifo_empty_reg
    if(~i_rstn) begin
        fifo_empty_q1 <= 0;
        fifo_empty_q2 <= 0;
    end else begin
        // Synchronous reset
        if (i_clearfifo) begin
            fifo_empty_q1 <= 0;
            fifo_empty_q2 <= 0;

        end else if (fifo_pop) begin
            fifo_empty_q1 <= fifo_empty;
            fifo_empty_q2 <= fifo_empty_q1;
        end
    end
end

// -----------------------------------------------------------------
// FIFO full signal shimming => To equalize with SRAM rden latency
// -----------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : full_shim_reg
    if(~i_rstn) begin
        fifo_full_shim <= 0;
    end else begin
        fifo_full_shim <= fifo_full;
    end
end

// ------------------------
// Output management
// ------------------------

assign o_data = (fifo_pop && (!fifo_empty_q2)) ? fifo_dout : 0;
assign o_fifo_empty = fifo_empty;
assign o_fifo_full = fifo_full;

endmodule 
