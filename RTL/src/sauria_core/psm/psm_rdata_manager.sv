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

module psm_rdata_manager #(
    parameter Y = 3,
    parameter OC_W = 48,
    parameter SRAMC_N = 2,
    parameter SRAMC_W = 96,
    parameter BUFF_W = 144
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [SRAMC_W-1:0]      i_sramc_data,       // Data bus from SRAM - Must have latency 2 wrto address
	
	// Control Inputs
    input  logic [0:Y-1]            i_rows_active,      // Active rows
    input  logic					i_feeder_en,        // Global pipeline enable (for stalls)
    input  logic                    i_clearbuff,        // High clears the buffer control signals
    input  logic [0:SRAMC_N-1]      i_mask,             // Mask that indicates the location of active data elements in the bus

	// Control Outputs
	output logic                    o_fifo_push, 	    // Activity of ping registers

    // Data Outputs
	output logic [BUFF_W-1:0]       o_fifo_din          // Output data bus towards FIFO

);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam N_ELM_BITS = $clog2(SRAMC_N+1)+1;
localparam Y_CNT_BITS = $clog2(Y+1)+1;

// Input reshape
logic [0:SRAMC_N-1][OC_W-1:0] sram_elements;

// Mask propagation and muxing
logic [0:SRAMC_N-1] mask_q1, mask_q2;

// Element Index
logic [0:SRAMC_N-1][N_ELM_BITS-1:0]         par_sums;
logic [0:SRAMC_N-1][N_ELM_BITS-1:0]         elm_idx;

// Upload Index
logic                   [Y_CNT_BITS-1:0]    shift_idx;
logic [0:Y-1][Y_CNT_BITS-1:0]               order_pat, upload_idx;

// Ping-Pong registers
logic [0:Y-1]             buff_active_d, buff_active_q;
logic [0:Y-1]             buff_en;
logic [0:Y-1][OC_W-1:0]   buff_d, buff_q;

// Helper signals
logic [0:SRAMC_N-1]             map_flags;

// Control signals
logic fifo_push;

// Output reshape and muxing
logic [BUFF_W-1:0]      buff_obus;


// ------------------------------------------------------------
// IO Mapping - Wide SRAM bus to element array and vice versa
// ------------------------------------------------------------

// Input values
genvar ii;
generate
    for (ii=0; ii < SRAMC_N; ii++) begin
        assign sram_elements[ii] = i_sramc_data[ii*OC_W+:OC_W];
    end
endgenerate

// Output values
genvar jj;
generate
    for (jj=0; jj < Y; jj++) begin
        assign buff_obus[jj*OC_W+:OC_W] = buff_q[jj];
    end
endgenerate

// ------------------------
// Mask Shimming
// ------------------------

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : mask_reg
    if(~i_rstn) begin
        mask_q1 <= 0;
        mask_q2 <= 0;
    end else begin
        if (i_feeder_en) begin
            mask_q1 <= i_mask;
            mask_q2 <= mask_q1;
        end
    end
end

// ----------------------------------------------------------------
// Unified Data Interconnect
// ----------------------------------------------------------------

always_comb begin

    // Default states
    buff_d = buff_q;
    buff_active_d = buff_active_q;
    map_flags = 0;

    // Clear buffer signal => Immediately clears active flags
    if (i_clearbuff) begin
        buff_active_d = 0;

    // Normal operation => Enabled by feeder_en
    end else if (i_feeder_en) begin

        // Fifo push forces all positions to zero on (previous) selected buff
        if (fifo_push) begin
            buff_active_d = 0;
        end

        // Data interconnection
        for (integer i=0; i < SRAMC_N; i++) begin

            // If position is marked by mask_q2
            if (mask_q2[i]) begin
                
                // Check all register positions
                for (integer j=0; j < Y; j++) begin

                    // Only if row is active
                    if (i_rows_active[j]) begin

                        // If register is currently active and we have not already mapped, we map
                        if ((!buff_active_d[j]) && (!map_flags[i])) begin
                            buff_active_d[j] = 1'b1;
                            map_flags[i] = 1'b1;
                            buff_d[j] = sram_elements[i];
                        end
                    end
                end
            end
        end
    end

    // All unselected positions are always forced to 1
    buff_active_d = buff_active_d | (~i_rows_active);

end

// Ping and Pong Registers
genvar j;
generate
    // Generate one instance per position
    for (j=0; j < Y; j++) begin
        // Normal FF behavior
        always_ff @(posedge i_clk or negedge i_rstn) begin : pingpong_reg
            if(~i_rstn) begin
                buff_q[j] <= 0;
                buff_active_q[j] <= 0;
            end else begin
                buff_q[j] <= buff_d[j];
                buff_active_q[j] <= buff_active_d[j];
            end
        end
    end
endgenerate

// -----------------
// FIFO push logic
// -----------------

always_comb begin
    fifo_push = 0;

    if (i_feeder_en) begin
        // Ping selected & all ping positions full
        if (buff_active_q == '1) begin
            fifo_push = 1;
        end
    end
end

// ------------------------------
// Output Selection
// ------------------------------

assign o_fifo_din = (i_feeder_en)? buff_obus : 0;
assign o_fifo_push = fifo_push;

endmodule 
