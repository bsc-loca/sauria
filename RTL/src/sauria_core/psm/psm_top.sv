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

module psm_top #(
    parameter X = 3,
    parameter Y = 3,
    parameter PARAMS_W = 8,
    parameter OC_W = 48,
    parameter SRAMC_W = 96,
    parameter IDX_W = 11,
    parameter ADRC_W = 8,

    localparam SRAMC_N = int'(SRAMC_W/OC_W)
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

	// Data Inputs from Array
	input  logic [0:Y-1][OC_W-1:0] 	    i_c_arr,	        // MAC outputs (scan chain)

    // Data Inputs from Memory
    input  logic [SRAMC_W-1:0]          i_sramc_rdata,      // Read data bus from SRAMC

	// Configuration Inputs
    input  logic [IDX_W-1:0]		    i_cxlim,            // Idx Counters : X counter limit
    input  logic [IDX_W-1:0]		    i_cxstep,           // Idx Counters : X counter step size
    input  logic [IDX_W-1:0]		    i_cklim,            // Idx Counters : Out-Channel counter limit
    input  logic [IDX_W-1:0]		    i_ckstep,           // Idx Counters : Out-Channel counter step size
    input  logic [IDX_W-1:0]		    i_til_cylim,        // Idx Counters : Tiling X-Y counter limit
    input  logic [IDX_W-1:0]		    i_til_cystep,       // Idx Counters : Tiling X-Y counter step size
    input  logic [IDX_W-1:0]		    i_til_cklim,        // Idx Counters : Tiling Out-Channel counter limit
    input  logic [IDX_W-1:0]		    i_til_ckstep,       // Idx Counters : Tiling Out-Channel counter step size
    input  logic [IDX_W-1:0]		    i_ncontexts,        // Total number of contexts to compute
    input  logic            		    i_preload_en,       // Output (psum) value preload enable
    input  logic [PARAMS_W-1:0]         i_inactive_cols,    // Number of inactive columns
    input  logic [0:Y-1]                i_rows_active,      // Active Rows configuration
    
    // FSM control inputs
    input  logic					    i_fsm_start,        // Start FSM
    input  logic                        i_fsm_reset,        // Reset FSM
    input  logic                        i_pipeline_en,      // Pipeline Enable, needed to stall the scanning

    // FSM control outputs
    output logic					    o_done,             // Finish flag
    output logic                        o_finalwrite,       // Flag signaling that all outputs EXCEPT LAST have been written successfully
    output logic					    o_shift_done,       // Flag signaling that computation can start

    // Status Outputs (External)
    output  logic [4:0]                 o_out_status,       // Output Scan FSM status

    // Control Outputs to Memory
    output logic [ADRC_W-1:0]           o_sramc_addr,       // Address towards SRAMC
    output logic                        o_sramc_wren,       // Write Enable for SRAMC
    output logic                        o_sramc_rden,       // Read Enable for SRAMC
    output logic [0:SRAMC_N-1]          o_sramc_wmask,      // Write Mask for SRAMC

    // Control Outputs to Array
    output logic                        o_cscan_en,         // Output Scan-Chain Enable

    // Data Outputs to Memory
    output logic [SRAMC_W-1:0]          o_sramc_wdata,      // Write data bus towards SRAMC

    // Data Outputs to Array
	output logic [0:Y-1][OC_W-1:0]  	o_c_arr             // MAC preload values (scan chain)
);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam BUFF_W = OC_W * Y;
localparam WOFS_W = $clog2(SRAMC_N);

// Input Data Bus Register
logic [SRAMC_W-1:0] sramc_rdata_q;

// Output Shift Buffer
logic [BUFF_W-1:0] buff_din, buff_sram_din, buff_arr_din, buff_dout;
logic buff_clear, buff_shift_en, fifo_push, fifo_pop, buff_shift_fsm;

// Scan FSM
logic rd_feed_en, rd_feed_clear;
logic wr_feed_en, wr_feed_clear;
logic cnt_en, cnt_clear, wr_flag, cnt_start;
logic sramc_wren_d, sramc_wren_q1, sramc_wren_q2, sramc_wren_q3;

// Index Counter
logic [ADRC_W-1:0]      sramc_addr_d, sramc_addr_q1, sramc_addr_q2, sramc_addr_q3;
logic [0:SRAMC_N-1]     mask;
logic                   cnt_done, cnt_til_done, fifo_data_flag;

// Output bus before muxing
logic [0:Y-1][OC_W-1:0]     buff_dout_arr;

// ------------------------------------------------------------
// IO Mapping - Wide bus to element array and vice versa
// ------------------------------------------------------------

genvar ii;
    generate
        for (ii=0; ii < Y; ii++) begin
            // Input values
            assign buff_arr_din[ii*OC_W+:OC_W] = i_c_arr[ii];
            
            // Output values
            assign buff_dout_arr[ii] = buff_dout[ii*OC_W+:OC_W];
        end
    endgenerate

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// Output Shift Register
psm_shift_register #(
        .X(X),
        .BUFF_W(BUFF_W)
    ) psm_shift_register_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_din	        (buff_din),
        .i_shift        (buff_shift_en),
        .i_clear        (buff_clear),

        .o_dout         (buff_dout));

// Read Data Manager
psm_rdata_manager #(
        .Y(Y),
        .OC_W(OC_W),
        .SRAMC_W(SRAMC_W),
        .SRAMC_N(SRAMC_N),
        .BUFF_W(BUFF_W)
    ) psm_rdata_manager_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_rows_active  (i_rows_active),
        .i_sramc_data   (sramc_rdata_q),
        .i_feeder_en    (rd_feed_en),
        .i_clearbuff	(rd_feed_clear),
        .i_mask         (mask),

        .o_fifo_push    (fifo_push),
        .o_fifo_din     (buff_sram_din));

// Write Data Manager
psm_wdata_manager #(
        .Y(Y),
        .OC_W(OC_W),
        .WOFS_W(WOFS_W),
        .SRAMC_W(SRAMC_W),
        .SRAMC_N(SRAMC_N),
        .BUFF_W(BUFF_W)
    ) psm_wdata_manager_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_fifo_dout        (buff_dout),
        .i_feeder_en        (wr_feed_en),
        .i_clearbuff	    (wr_feed_clear),
        .i_mask             (mask),
        .i_fifo_pop         (fifo_data_flag),

        .o_sramc_wmask      (o_sramc_wmask),
        .o_fifo_pop         (fifo_pop),
        .o_sramc_wdata      (o_sramc_wdata));

// Scan FSM
psm_shift_fsm #(
        .X(X),
        .PARAMS_W(PARAMS_W),
        .IDX_W(IDX_W)
    ) psm_shift_fsm_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_fsm_start    (i_fsm_start),
        .i_fsm_reset    (i_fsm_reset),
        .i_ncontexts	(i_ncontexts),
        .i_preload_en   (i_preload_en),
        .i_inactive_cols(i_inactive_cols),
        .i_pipeline_en  (i_pipeline_en),
        .i_done         (cnt_done),
        .i_til_done     (cnt_til_done),

        .o_cnt_en	    (cnt_en),
        .o_cnt_clear    (cnt_clear),
        .o_wr_flag      (wr_flag),
        .o_cnt_start	(cnt_start),

        .o_buff_clear       (buff_clear),
        .o_rd_feeder_en     (rd_feed_en),
        .o_rd_feeder_clear  (rd_feed_clear),
        .o_wr_feeder_en     (wr_feed_en),
        .o_wr_feeder_clear  (wr_feed_clear),
        .o_sramc_wren       (sramc_wren_d),
        .o_sramc_rden       (o_sramc_rden),
        .o_buff_shift       (buff_shift_fsm),
        .o_cscan_en         (o_cscan_en),
        .o_out_status       (o_out_status),
        .o_shift_done       (o_shift_done),
        .o_done             (o_done),
        .o_finalwrite       (o_finalwrite));

// Index Counter
psm_idxcnt #(
        .IDX_W(IDX_W),
        .ADRC_W(ADRC_W),
        .WOFS_W(WOFS_W),
        .SRAMC_N(SRAMC_N)
    ) psm_idxcnt_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_cnt_en	    (cnt_en),
        .i_cnt_clear    (cnt_clear),
        .i_start	    (cnt_start),
        .i_wr_flag      (wr_flag),
        .i_cxlim	    (i_cxlim),
        .i_cxstep       (i_cxstep),
        .i_cklim        (i_cklim),
        .i_ckstep       (i_ckstep),
        .i_til_cylim	(i_til_cylim),
        .i_til_cystep   (i_til_cystep),
        .i_til_cklim	(i_til_cklim),
        .i_til_ckstep   (i_til_ckstep),

        .o_mask             (mask),
        .o_wr_fifo_pop      (fifo_data_flag),
        .o_sram_addr        (sramc_addr_d),
        .o_done	            (cnt_done),
        .o_til_done	        (cnt_til_done));

// --------------------------
// Shift signal generation
// ---------------------------

assign buff_shift_en = (o_cscan_en && i_pipeline_en) | buff_shift_fsm | fifo_push | fifo_pop;

// --------------------------
// Shift Buffer Input Muxing
// ---------------------------

assign buff_din = (buff_shift_fsm || o_cscan_en) ? buff_arr_din : buff_sram_din;

// ----------------------------------------------------------------------------
// SRAM Data Bus register (latency equalization of SRAM data with Data Manager)
// ----------------------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : data_reg
    if(~i_rstn) begin
        sramc_rdata_q <= 0;
    end else begin
        if (rd_feed_en) begin
            sramc_rdata_q <= i_sramc_rdata;
        end
    end
end

// ----------------------------------------------------------------------------
// Write address shimming & Address selection
// ----------------------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : addr_reg
    if(~i_rstn) begin
        sramc_addr_q1 <= 0;
        sramc_addr_q2 <= 0;
        sramc_addr_q3 <= 0;
        sramc_wren_q1 <= 0;
        sramc_wren_q2 <= 0;
        sramc_wren_q3 <= 0;
    end else begin

        if (wr_feed_clear) begin
            sramc_addr_q1 <= 0;
            sramc_addr_q2 <= 0;
            sramc_addr_q3 <= 0;
            sramc_wren_q1 <= 0;
            sramc_wren_q2 <= 0;
            sramc_wren_q3 <= 0;

        end else if (wr_feed_en) begin
            sramc_addr_q1 <= sramc_addr_d;
            sramc_addr_q2 <= sramc_addr_q1;
            sramc_addr_q3 <= sramc_addr_q2;
            sramc_wren_q1 <= sramc_wren_d;
            sramc_wren_q2 <= sramc_wren_q1;
            sramc_wren_q3 <= sramc_wren_q2;
        end
    end
end

assign o_sramc_addr = (wr_flag) ? sramc_addr_q3 : sramc_addr_d;
assign o_sramc_wren = (wr_flag) ? sramc_wren_q3 : 0;

assign o_c_arr = (o_cscan_en) ? buff_dout_arr : 0;

endmodule 
