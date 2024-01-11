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

module fifo_memory_ff #(
    parameter FIFO_POSITIONS = 8,
    parameter IN_W = 128,
    parameter OUT_W = 16
)(
    // Clk, RST
	input  logic 				    i_clk,
	input  logic					i_rstn,

	// Data Inputs
    input  logic [IN_W-1:0]         i_din,          // Input Data Bus (Wider)
	
	// Control Inputs
    input  logic					i_push,         // Push new value into i_din
    input  logic                    i_pop,          // Pop value to dout
    input  logic                    i_clearfifo,    // Resets FIFO counters and makes it empty

	// Control Outputs
	output logic                    o_full,         // FIFO Full flag
    output logic                    o_empty,        // FIFO Empty flag

    // Data Outputs
	output logic [OUT_W-1:0]        o_dout          // Output Data Bus (Narrower)

);

// ----------
// SIGNALS
// ----------

// Local parameters
localparam N_ELEMENTS = IN_W/OUT_W;
localparam N_ELM_BITS = $clog2(N_ELEMENTS);

localparam MEM_ADDR_WIDTH = $clog2(FIFO_POSITIONS+1);

// Pointer
logic [MEM_ADDR_WIDTH-1:0]              ptr_d, ptr_q;
logic [N_ELM_BITS-1:0]                  out_woffs;
logic                                   down_flag;

// Flags
logic                                   empty, full;
logic                                   empty_public;

// Empty Start Flag
logic                                   empty_start_d, empty_start_q;

// Register Chain
logic [0:FIFO_POSITIONS-1][IN_W-1:0]    data_q, data_mux;
logic [0:FIFO_POSITIONS-1]              reg_en;
logic [0:FIFO_POSITIONS-1]              mux_sel;

// Final register arrangement & Muxing
logic [0:N_ELEMENTS-1][OUT_W-1:0]       data_pop_q;
logic [OUT_W-1:0]                       data_pop_mux;

// Output buffer
logic [OUT_W-1:0]                       outbuf_d, outbuf_q;

// ------------------------------------------------------------
// Register Chain instantiation
// ------------------------------------------------------------

// Combinational logic (muxes)
always_comb begin
    for (integer i=0; i < FIFO_POSITIONS; i++) begin
        // First register is a special case
        if (i==0) begin
            if (mux_sel[i]) begin
                data_mux[i] = i_din;
            end else begin
                data_mux[i] = 0;
            end
        end else begin
            // Take input if mux sel is High
            if (mux_sel[i]) begin
                data_mux[i] = i_din;
            // Otherwise take value from previous reg
            end else begin
                data_mux[i] = data_q[i-1];
            end
        end
    end
end

// Registers
genvar i;
generate
    // Generate one instance per position
    for (i=0; i < FIFO_POSITIONS; i++) begin
        // Normal FF behavior
        always_ff @(posedge i_clk or negedge i_rstn) begin : chain_reg
            if(~i_rstn) begin
                data_q[i] <= 0;
            end else begin

                // Synchronous reset
                if (i_clearfifo) begin
                    data_q[i] <= 0;
                end else if (reg_en[i]) begin
                    data_q[i] <= data_mux[i];
                end
            end
        end
    end
endgenerate

// -------------------------------------
// Output word offset - Simple counter
// -------------------------------------

// Register/counter
always_ff @(posedge i_clk or negedge i_rstn) begin : woffs_reg
    if(~i_rstn) begin
        out_woffs <= 0;
    end else begin

        // Synchronous reset
        if (i_clearfifo) begin
            out_woffs <= 0;
        //end else if (i_pop && (!(empty_public & empty))) begin
        end else if (i_pop && (!(empty))) begin

            // Reset when overflow, otherwise count up
            if (out_woffs == (N_ELEMENTS-1)) begin
                out_woffs <= 0;
            end else begin
                out_woffs <= out_woffs + 1;
            end
        end
    end
end

//assign down_flag = (out_woffs==(N_ELEMENTS-1)) && i_pop && (!(empty_public & empty));
assign down_flag = (out_woffs==(N_ELEMENTS-1)) && i_pop && (!(empty));

// -------------------------------------
// Pointer counter - Up/Down Counter
// -------------------------------------

// Combinational logic
always_comb begin

    // Clear FIFO forces the pointer to zero (empty)
    if (i_clearfifo) begin
        ptr_d = 0;
        
    end else begin

        ptr_d = ptr_q;

        if (i_push && (!down_flag) && (!full)) begin
            ptr_d = ptr_q + 1;
        end

        if ((!i_push) && down_flag) begin
            ptr_d = ptr_q - 1;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : ptrs_reg
    if(~i_rstn) begin
        ptr_q <= 0;
    end else begin
        ptr_q <= ptr_d;
    end
end

// ------------------------------------------------------------
// Register Chain control
// ------------------------------------------------------------

always_comb begin

    mux_sel = 0;
    reg_en = 0;

    // For all registers
    for (integer i=0; i < FIFO_POSITIONS; i++) begin
        
        // Enable Mux Sel to the register we point to (ptr=0 means last reg)
        if (ptr_q == (FIFO_POSITIONS-1-i)) begin
            // Only enable at the moment of pushing, with 2 possibilities:
            if (i_push) begin
                // If down_flag is also active, set for the next register (special case)
                if (down_flag && (i<FIFO_POSITIONS-1)) begin
                    mux_sel[i+1] = 1;
                // Otherwise set for current register
                end else begin
                    mux_sel[i] = 1;
                end
            end
        end
        
        // When pushing new values, enable the register pointed to
        if (mux_sel[i] && (!full)) begin
            reg_en[i] = 1;
        end
    end

    // When pulling from a new register, enable all registers for a shift
    if (down_flag) begin
        reg_en = '1;
    end
end

// ------------------------
// Empty start flag => After clearing the FIFO we must reset all pointers, but in this case this means Empty
// ------------------------

// Combinational logic
always_comb begin
    
    // Set to 1 with clear fifo signal or RST
    if (i_clearfifo) begin
        empty_start_d = 1;
    end else begin

        // Maintained until first push
        empty_start_d = empty_start_q;

        // Upon first push it is cleared
        if (i_push) begin
            empty_start_d = 0;
        end
    end
end

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : empty_start_reg
    if(~i_rstn) begin
        empty_start_q <= 1;         // RST also empties the FIFO
    end else begin
        empty_start_q <= empty_start_d;
    end
end

// ------------------------
// Full & Empty flags
// ------------------------

always_comb begin
    full = (ptr_q == FIFO_POSITIONS);
    //empty = ((ptr_q <= 1) && (out_woffs==(N_ELEMENTS-1))) || empty_start_q;
    empty = (ptr_q == 0) || empty_start_q;
end

// ------------------------
// Output Data management
// ------------------------

// Output selection
always_comb begin

    // Wide bus to array mapping
    for (integer i=0; i < N_ELEMENTS; i++) begin        
        data_pop_q[i] = data_q[FIFO_POSITIONS-1][i*OUT_W+:OUT_W];
    end

    // Output Mux
    outbuf_d = 0;
    for (integer i=0; i < N_ELEMENTS; i++) begin
        
        if (out_woffs==i) begin
            outbuf_d = data_pop_q[i];
        end
    end
end

// Output buffer
always_ff @(posedge i_clk or negedge i_rstn) begin : outbuff_reg
    if(~i_rstn) begin
        outbuf_q <= 0;
        empty_public <= 0;
    end else begin

        // Synchronous reset
        if (i_clearfifo) begin
            outbuf_q <= 0;
            empty_public <= 1;

        end else if (i_pop) begin        // i_pop acts as read enable
            outbuf_q <= outbuf_d;
            empty_public <= empty;
        end
    end
end

assign o_dout = outbuf_q;
assign o_full = full;
//assign o_empty = empty_public & empty;
assign o_empty = empty;

endmodule 
