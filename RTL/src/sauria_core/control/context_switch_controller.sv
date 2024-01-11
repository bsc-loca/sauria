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

module context_switch_controller #(
    parameter X = 3,
    parameter Y = 3,
    parameter IDX_W = 11,
    parameter PE_LAT = 5,
    parameter EXTRA_CSREG = 0
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Control inputs
    input  logic [IDX_W-1:0]            i_incntlim,         // Input counter limit
    input  logic                        i_clear,            // Clear flag for counters and buffers
    input  logic                        i_pipeline_en,      // Pipeline enable
    input  logic                        i_wei_pop_en,       // Weight inputs pop enable
    input  logic                        i_act_pop_en,       // Activation inputs pop enable
    input  logic                        i_cswitch_en,       // Context switch enable
    input  logic                        i_cswitch_force,    // Force context switch flag

	// Control Outputs (Context FSM)
    output logic					    o_cdone,            // Context done flag
    output logic                        o_cswitch_done,     // Cswitch done flag

	// Control Outputs (Systolic Array)
    output logic [0:X-1]   		        o_cswitch_arr       // Accumulator context switches
);

// ----------
// SIGNALS
// ----------

// Context Switch signal propagation cycles (PE latency + total array propagation)
localparam CSWITCH_PROP_CYCLES = PE_LAT + X+Y-1;
localparam CSWITCH_CNT_BITS = $clog2(CSWITCH_PROP_CYCLES+1);

// Counter value that will trigger a cdone flag
logic [IDX_W-1:0]            cdone_val;

// Flags to force some special conditions to cdone at boundary cases (lim={0,1})
logic                        cdone_force_q1, cdone_force_q2;

// Pop signals shimming (to equalize latency with PEs)
logic pop_shim_init_q, pop_shim_init_d, pop_shim_q2;

// Input counter
logic [IDX_W-1:0]   incnt_d, incnt_q;

// Context Switch Signal and Hold
logic cdone, cdone_hold, cdone_hold_d;

// Cdone signal shimming
logic cdone_shim_q1, cdone_q;

// Cswitch counter signals
logic                           cscnt_trigger;
logic [CSWITCH_CNT_BITS-1:0]    cscnt_d, cscnt_q;
logic                           cscnt_flag;

// Intermediate CS signal
logic [0:X-1] cswitch_arr_d, cswitch_arr_q;

// -------------------------------------------------
// Pop signals => Shimming to equalize latency with PEs
// -------------------------------------------------

// pop_shim_init register is set to 1 with first poppings, and only cleared when i_clear => Represents 1st latency cycle only at the beginning, caused by FIFO ptrs
always_comb begin

    pop_shim_init_d = pop_shim_init_q;

    if (i_clear) begin
        pop_shim_init_d = 0;
    end else if (i_wei_pop_en && i_act_pop_en) begin
        pop_shim_init_d = 1;
    end
end

// Registers
always_ff @(posedge i_clk or negedge i_rstn) begin : popshim_reg
    if(~i_rstn) begin
        pop_shim_init_q <= 0;
        pop_shim_q2 <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            pop_shim_init_q <= 0;
            pop_shim_q2 <= 0;

        end else if (i_pipeline_en || i_cswitch_force) begin
            pop_shim_init_q <= pop_shim_init_d;
            pop_shim_q2 <= pop_shim_init_q && i_wei_pop_en && i_act_pop_en;
        end
    end
end

// -------------------------------------------------
// Simple input counter to track context execution
// -------------------------------------------------

// Cdone trigger value is max(i_incntlim-2, 0)
assign cdone_val = (i_incntlim>1)? (i_incntlim-2) : 0;

// In two special situations we raise these flags
assign cdone_force_q1 = (i_incntlim==1)? 1 : 0;
assign cdone_force_q2 = (i_incntlim==0)? 1 : 0;

// Comb logic
always_comb begin

    cdone = 0;
    incnt_d = incnt_q;

    if (((incnt_q == cdone_val) && (pop_shim_q2 || cdone_force_q2))) begin
        cdone = 1;
    end

    if (incnt_q == i_incntlim) begin
        incnt_d = 0;
    end else begin
        incnt_d = incnt_q + 1;
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : incnt_reg
    if(~i_rstn) begin
        incnt_q <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            incnt_q <= 0;

        // Only count when pipeline is enable and inputs are popping
        end else if (i_pipeline_en && pop_shim_q2) begin
            incnt_q <= incnt_d;
        end
    end
end

// ---------------------------------
// Signal hold registers
// ---------------------------------

always_comb begin
    
    cdone_hold_d = cdone_hold;

    // Assert when cdone flag and imminent transition of incnt
    if(cdone && (i_pipeline_en || i_cswitch_force) && i_wei_pop_en && i_act_pop_en) begin
        cdone_hold_d = 1;

    // Deassert when cscnt is triggered
    end else if (cscnt_trigger && i_cswitch_en && (cscnt_q == 0) && (i_pipeline_en || i_cswitch_force)) begin
        cdone_hold_d = 0;
    end

end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : hold_reg
    if(~i_rstn) begin
        cdone_hold <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            cdone_hold <= 0;

        end else if (i_pipeline_en || i_cswitch_force) begin
            cdone_hold <= cdone_hold_d;
        end
    end
end

// -------------------------------------------------
// Shimming registers
// -------------------------------------------------

// GATED SHIMMING
always_ff @(posedge i_clk or negedge i_rstn) begin : gshim_reg
    if(~i_rstn) begin
        cdone_q <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            cdone_q <= 0;

        end else if (i_pipeline_en || i_cswitch_force) begin
            cdone_q <= cdone;
        end
    end
end

// UNGATED SHIMMING
always_ff @(posedge i_clk or negedge i_rstn) begin : ugshim_reg
    if(~i_rstn) begin
        cdone_shim_q1 <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            cdone_shim_q1 <= 0;

        end else if (i_pipeline_en || i_cswitch_force) begin
            cdone_shim_q1 <= cdone_hold;
        end
    end
end

// ------------------------------------
// Context Switch Counter
// ------------------------------------

assign cscnt_trigger = (i_cswitch_en && cdone_shim_q1) || i_cswitch_force;

// Comb logic
always_comb begin

    cscnt_flag = 0;
    cscnt_d = cscnt_q;

    // Reset & output flag
    if (cscnt_q == CSWITCH_PROP_CYCLES) begin
        cscnt_flag = 1;
        cscnt_d = 0;
    end else begin
        // Start counting only after trigger
        if (cscnt_trigger || (cscnt_q > 0)) begin
            cscnt_d = cscnt_q + 1;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : cscnt_reg
    if(~i_rstn) begin
        cscnt_q <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            cscnt_q <= 0;

        end else if (i_pipeline_en && i_cswitch_en) begin
            cscnt_q <= cscnt_d;
        end
    end
end

// ------------------------------------
// Context Switch Generation
// ------------------------------------

always_comb begin

    cswitch_arr_d = 0;

    // For each cswitch bit
    for (integer i=0; i<X; i++) begin
        // Set High depending on counter state
        if (cscnt_q == (PE_LAT - EXTRA_CSREG + i)) begin
            cswitch_arr_d[i] = 1;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : cswitch_reg
    if(~i_rstn) begin
        cswitch_arr_q <= 0;
    end else begin

        // Synchronous reset
        if (i_clear) begin
            cswitch_arr_q <= 0;

        end else if (i_pipeline_en) begin
            cswitch_arr_q <= cswitch_arr_d;
        end
    end
end

// ---------------------------------
// Output Management
// ---------------------------------

assign o_cswitch_arr = cswitch_arr_q;
assign o_cdone = (cdone_q || (cdone_force_q1 && cdone)) & i_pipeline_en & i_wei_pop_en & i_act_pop_en;
assign o_cswitch_done = cscnt_flag & i_pipeline_en & i_cswitch_en;

endmodule 
