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

module psm_wdata_manager #(
    parameter Y = 3,
    parameter OC_W = 48,
    parameter WOFS_W = 3,
    parameter SRAMC_N = 2,
    parameter SRAMC_W = 96,
    parameter BUFF_W = 144
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [BUFF_W-1:0]       i_fifo_dout,        // Data bus from SRAM - Must have latency 2 wrto address
	
	// Control Inputs
    input  logic					i_feeder_en,        // Global pipeline enable (for stalls)
    input  logic                    i_clearbuff,        // High clears the buffer control signals
    input  logic [0:SRAMC_N-1]      i_mask,             // Word offset for writing
    input  logic                    i_fifo_pop,         // Signal marking a data transition

    // Control Outputs
    output logic [0:SRAMC_N-1]      o_sramc_wmask,      // Output data bus towards FIFO
    output logic                    o_fifo_pop,         // Actual pop signal towards FIFO
	
    // Data Outputs
    output logic [SRAMC_W-1:0]      o_sramc_wdata       // Output data bus towards FIFO

);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam N_ELM_BITS = $clog2(Y+1)+1;

// Input reshape
logic [0:Y-1][OC_W-1:0]     buff_elements;

// Woffs propagation
logic [WOFS_W-1:0]  wofs;

// Write Elements counter
logic [N_ELM_BITS-1:0]          elm_cnt_step;
logic [N_ELM_BITS-1:0]          elm_cnt_d, elm_cnt_q;

// Write mask shimming
logic [0:SRAMC_N-1]             mask_q1, mask_q2;

// FIFO pop shimming
logic fifo_pop_q;

// Output registers
logic [0:Y-1]                   outbuf_en;
logic [0:SRAMC_N-1][OC_W-1:0]   outbuf_d, outbuf_q;

// ------------------------------------------------------------
// IO Mapping - Wide SRAM bus to element array and vice versa
// ------------------------------------------------------------

// Input values
genvar ii;
generate
    for (ii=0; ii < Y; ii++) begin
        assign buff_elements[ii] = i_fifo_dout[ii*OC_W+:OC_W];
    end
endgenerate

// Output values
genvar jj;
generate
    for (jj=0; jj < SRAMC_N; jj++) begin
        assign o_sramc_wdata[jj*OC_W+:OC_W] = outbuf_q[jj];
    end
endgenerate

// ------------------------------
// Write Mask & FIFO pop shimming
// ------------------------------

// Registers
always_ff @(posedge i_clk or negedge i_rstn) begin : wmask_reg
    if(~i_rstn) begin
        mask_q1 <= 0;
        mask_q2 <= 0;
        fifo_pop_q <= 0;
    end else begin
        if(i_feeder_en) begin
            mask_q1 <= i_mask;
            mask_q2 <= mask_q1;
            fifo_pop_q <= i_fifo_pop;
        end
    end
end

// ----------------------------------------------------------------
// Input Data Interconnect Logic
// ----------------------------------------------------------------

always_comb begin

    // Default state
    outbuf_en = 0;
    outbuf_d = 0;

    // Word Offset => Location of 1st one
    wofs = 0;
    for (integer j=1; j < SRAMC_N; j++) begin
        if (mask_q1[j] && (!mask_q1[j-1])) begin
            wofs = j;
        end
    end

    // ASSIGNTMENT TO BUFFERS: Based on Element Index Counter & Mask
    for (integer j=0; j < SRAMC_N; j++) begin
        if (mask_q1[j]) begin
            outbuf_en[j] = 1;
            outbuf_d[j] = buff_elements[elm_cnt_q+(j-wofs)];
        end
    end
end

// ------------------------------
// Output Buffers
// ------------------------------

// Ping and Pong Registers
genvar j;
generate
    // Generate one instance per position
    for (j=0; j < SRAMC_N; j++) begin
        // Normal FF behavior
        always_ff @(posedge i_clk or negedge i_rstn) begin : outbuf_reg
            if(~i_rstn) begin
                outbuf_q[j] <= 0;
            end else begin
                if(i_feeder_en && outbuf_en[j]) begin
                    outbuf_q[j] <= outbuf_d[j];
                end
            end
        end
    end
endgenerate

// -------------------------------------
// Element Index Counter
// -------------------------------------

// Comb Logic
always_comb begin

    elm_cnt_d = elm_cnt_q;

    // Current count step = Number of 1s in mask_q1
    elm_cnt_step = 0;
    for (integer b=0; b < SRAMC_N; b++) begin
        elm_cnt_step = elm_cnt_step + mask_q1[b];
    end

    // Up counter behavior
    if (fifo_pop_q || i_clearbuff) begin
        elm_cnt_d = 0;
    end else begin
        elm_cnt_d = elm_cnt_q + elm_cnt_step;
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : el_cnt_reg
    if(~i_rstn) begin
        elm_cnt_q <= 0;
    end else begin
        if (i_feeder_en || i_clearbuff) begin
            elm_cnt_q <= elm_cnt_d;
        end
    end
end

// ------------------------------
// Output Management
// ------------------------------

assign o_sramc_wmask = mask_q2;
assign o_fifo_pop = fifo_pop_q;

endmodule 
