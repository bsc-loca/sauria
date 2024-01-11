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

// --------------------
//      INCLUDES
// --------------------

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "common_cells/registers.svh"

// ----------
// MACROS
// ----------

// --------------------
// MODULE DECLARATION
// --------------------

module axi_full_2ram #(

    /// The minimum value of this parameter is `$clog2(RegNumBytes)`.
    parameter int unsigned AxiAddrWidth = 32'd0,
    /// Data width of the AXI4 port.
    parameter int unsigned AxiDataWidth = 32'd0,
    /// Width of the ID port
    parameter int unsigned AxiIdWidth = 32'd0,

    // READ LATENCY CYCLES
    parameter int unsigned READ_LATENCY = 1,

    parameter bit PrivProtOnly = 1'b0,
    parameter bit SecuProtOnly = 1'b0,

    /// Constant (=**do not overwrite!**); type of a byte is 8 bit.
    parameter type byte_t = logic [7:0],

    /// Request struct of the AXI4 port.
    parameter type req_t = logic,
    /// Response struct of the AXI4 port.
    parameter type resp_t = logic
) (

    input  logic                          clk_i,
    input  logic                          rst_ni,

    input  req_t                          axi_req_i,
    output resp_t                         axi_resp_o,

    output  logic  [AxiAddrWidth-1:0]     ram_addr_o,
    output  logic  [AxiDataWidth-1:0]     ram_din_o,
    output  logic  [AxiDataWidth-1:0]     ram_wmask_o,
    output  logic                         ram_wren_o,
    output  logic                         ram_rden_o,
    input   logic  [AxiDataWidth-1:0]     ram_dout_i

);

// ----------
// SIGNALS
// ----------

localparam IF_LSB_BITS = $clog2(AxiDataWidth / 32'd8);
localparam int unsigned AxiStrbWidth  = AxiDataWidth / 32'd8;
localparam L_CNT_BITS = $clog2(READ_LATENCY+2);

// Channel definitions for spill register
typedef logic [AxiDataWidth-1:0]    axi_data_t;
typedef logic [AxiIdWidth-1:0]      axi_id_t;
`AXI_TYPEDEF_B_CHAN_T(b_chan_t, axi_id_t, logic)
`AXI_TYPEDEF_R_CHAN_T(r_chan_t, axi_data_t, axi_id_t, logic)

// Response: combinational and sequential signals
resp_t  axi_resp_d, axi_resp_q /*verilator split_var*/;

// Status signals for writing and reading
logic   rd_flag_d, rd_flag_q;
logic   wr_flag_d, wr_flag_q;

// Address registers
logic   [AxiAddrWidth-1:0]  awaddr_d, awaddr_q;
logic   [AxiAddrWidth-1:0]  araddr_d, araddr_q;

// ID registers
logic   [AxiIdWidth-1:0]    awid_d, awid_q;
logic   [AxiIdWidth-1:0]    arid_d, arid_q;

// Burst & BurstLen registers
logic   [1:0]   awburst_d, awburst_q;
logic   [8:0]   awlen_d, awlen_q;
logic   [1:0]   arburst_d, arburst_q;
logic   [8:0]   arlen_d, arlen_q;

// Burst wrap sizes
logic   [AxiAddrWidth-1:0]  aw_wrap_size;
logic   [AxiAddrWidth-1:0]  ar_wrap_size;

// Burst counters
logic   [8:0]   wburst_cnt_d, wburst_cnt_q;
logic   [8:0]   rburst_cnt_d, rburst_cnt_q;

// Latency counters
logic [L_CNT_BITS-1:0]  latency_cnt_d, latency_cnt_q;
logic                   latency_cnt_flag;

logic [L_CNT_BITS-1:0]  rlast_cnt_d, rlast_cnt_q;

// Spill registers ready
logic reg_b_ready, reg_r_ready;

// --------------------------------
// Write Address Ready (AWREADY)
// --------------------------------

always_comb begin
    
    wr_flag_d = wr_flag_q;

    // AWREADY defaults to zero
    axi_resp_d.aw_ready = 1'b0;

    // If writing not in progress, we can start it when AWVALID
    if (!wr_flag_q) begin
        if (axi_req_i.aw_valid) begin
            wr_flag_d = 1'b1;                   // Signal that we start writing
            axi_resp_d.aw_ready = 1'b1;         // Ready to take AW
        end

    // If writing is in progress, can't take a new address
    end else begin
        // When WLAST arrives and we accept it, we can deassert wr_flag
        if (axi_req_i.w.last && axi_req_i.w_valid && axi_resp_q.w_ready) begin
            wr_flag_d = 1'b0;
        end
    end
end

// --------------------------------
// Write Ready (WREADY)
// --------------------------------

always_comb begin
    
    // WREADY defaults to zero
    axi_resp_d.w_ready = 1'b0;

    // If we are in the writing process and WVALID
    if (wr_flag_q) begin
        
        // When WLAST arrives, deassert WREADY (would go down next cycle)
        if (axi_req_i.w.last && axi_req_i.w_valid && axi_resp_q.w_ready) begin
            axi_resp_d.w_ready = 1'b0;
        
        // Otherwise assert WREADY
        end else begin
            axi_resp_d.w_ready = 1'b1;     
        end
    end
end

// -------------------------------------
// Write Response (BVALID, BID, BRESP)
// -------------------------------------

always_comb begin
    
    // Write Response ID is AWID
    axi_resp_d.b.id = awid_q;

    // Write response is maintained
    axi_resp_d.b.resp = axi_resp_q.b.resp;

    // BVALID is maintained
    axi_resp_d.b_valid = axi_resp_q.b_valid;

    // If BVALID and BREADY are high, we can deassert BVALID
    if (axi_resp_q.b_valid) begin
        if (reg_b_ready) begin
            axi_resp_d.b_valid = 1'b0;
        end

    // We assert BVALID and set BREST when WLAST arrives and we are writing (and reg_b is ready)
    end else if (wr_flag_q && axi_req_i.w.last && axi_req_i.w_valid && reg_b_ready) begin
        axi_resp_d.b_valid = 1'b1;
        axi_resp_d.b.resp = '0;         // OKAY response
    end
end

// -------------------------------------------------
// Write Address Latching (AWADDR, AWLEN, AWBURST)
// -------------------------------------------------

always_comb begin

    // Wrap boundary is fix
    aw_wrap_size = awlen_q;

    // Other signals are maintained    
    awaddr_d = awaddr_q;
    awid_d = awid_q;
    awburst_d = awburst_q;
    awlen_d = awlen_q;
    wburst_cnt_d = wburst_cnt_q;

    // Initial AWADDR latching => On the same cycle as AWREADY
    if (!wr_flag_q) begin
        if (axi_req_i.aw_valid) begin
            awaddr_d =      axi_req_i.aw.addr;
            awid_d =        axi_req_i.aw.id;
            awburst_d =     axi_req_i.aw.burst;
            awlen_d =       axi_req_i.aw.len + 1;   // aw_len = a => burst_length = a+1

            // Reset burst counter
            wburst_cnt_d = '0;
        end

    // During writing, manage awaddr
    end else begin

        // Only act when WREADY and WVALID
        if (axi_req_i.w_valid && axi_resp_q.w_ready) begin
            
            // Accept it only if we have not reached the end of the burst
            if (wburst_cnt_q < awlen_q) begin

                wburst_cnt_d = wburst_cnt_q + 1;

                // Different logic circuits depending on Burst Type
                case (awburst_q)

                    // FIXED BURST -> Address always the same
                    2'd0: begin
                        awaddr_d = awaddr_q;
                    end

                    // INCREMENTAL BURST -> Increment address on each beat
                    2'd1: begin
                        // Increment happens in real LSB
                        awaddr_d[AxiAddrWidth-1:IF_LSB_BITS] = awaddr_q[AxiAddrWidth-1:IF_LSB_BITS] + 1;
                    end

                    // WRAPPING BURST -> Increment address and wrap when necessary
                    2'd2: begin
                        
                        // WRAP => when address lower bits (that's why we AND) equal wrap size
                        if ((awaddr_q & aw_wrap_size) == aw_wrap_size) begin
                            awaddr_d = awaddr_q - aw_wrap_size;
                        
                        // NORMAL INCREMENT
                        end else begin
                            awaddr_d[AxiAddrWidth-1:IF_LSB_BITS] = awaddr_q[AxiAddrWidth-1:IF_LSB_BITS] + 1;
                        end
                    end

                    // OTHERS -> FIXED
                    default: begin
                        awaddr_d = awaddr_q;
                    end
                endcase
            end
        end
    end
end

// -------------------------------
// Read Address Ready (ARREADY)
// -------------------------------

always_comb begin
    
    // I DON'T KNOW WHY BUT VERILATOR DOES STRANGE THINGS IF I DON'T "READ" THESE SIGNALS HERE :(
    logic [2:0] dummy_thing;
    dummy_thing = {axi_resp_d.r.last, rd_flag_q, axi_resp_d.r_valid};

    // ARREADY defaults to zero
    axi_resp_d.ar_ready = 1'b0;

    rd_flag_d = rd_flag_q;

    // If reading not in progress, we can start it when ARVALID
    if (!rd_flag_q) begin
        if (axi_req_i.ar_valid) begin
            rd_flag_d = 1'b1;                   // Signal that we start reading
            axi_resp_d.ar_ready = 1'b1;         // Ready to take AR
        end

    // If reading is in progress, can't take a new address
    end else begin
        // When RLAST is sent, we can deassert rd_flag
        //if (axi_resp_d.r.last && axi_resp_d.r_valid) begin
        if (axi_resp_d.r.last && axi_resp_d.r_valid && reg_r_ready) begin
            rd_flag_d = 1'b0;
        end
    end
end

// ---------------------------------------------
// Read Valid and Response (RVALID, RID, RRESP)
// ---------------------------------------------

always_comb begin
    
    // Read Response ID is AWID
    axi_resp_d.r.id = arid_q;

    // Read response is always OK
    axi_resp_d.r.resp = 2'b0;         // OKAY (read response is asserted individually on each transfer inside a burst)

    // Latency counter defaults at zero, and is only active when reading is in progress
    latency_cnt_d = '0;
    latency_cnt_flag = 0;

    // Latency counter management
    if (rd_flag_q) begin

        // Stop when we reach READ_LATENCY+1 (acc. for out register) and raise a flag
        if (latency_cnt_q>=(READ_LATENCY+1)) begin
            latency_cnt_d = latency_cnt_q;
            latency_cnt_flag = 1;
        
        // Otherwise count normally
        end else begin
            latency_cnt_d = latency_cnt_q + 1;

            // Raise flag_prev when we reach READ_LATENCY, without stopping the count
            if (latency_cnt_q>=(READ_LATENCY)) begin
                latency_cnt_flag = 1;
            end
        end     
    end
end

// SPILL REGISTER valid (*not* AXI RVALID) - Controls if we let data in to the spill register
always_comb begin
    
    axi_resp_d.r_valid = 0;

    if (reg_r_ready | (!axi_resp_q.r_valid)) begin

        // Set to 1 only if reg_r_ready is high and initial latency is over
        axi_resp_d.r_valid = reg_r_ready & latency_cnt_flag;
    end
end

// -------------------------------------------------
// Read Address Latching (ARADDR, ARLEN, ARBURST)
// -------------------------------------------------

always_comb begin

    // Wrap boundary is fix
    ar_wrap_size = arlen_q;

    // RLAST defaults at zero
    rlast_cnt_d = '0;
    axi_resp_d.r.last = 0;

    // Other signals are maintained    
    araddr_d = araddr_q;
    arid_d = arid_q;
    arburst_d = arburst_q;
    arlen_d = arlen_q;
    rburst_cnt_d = rburst_cnt_q;

    // Initial ARADDR latching => On the same cycle as ARREADY
    if (!rd_flag_q) begin
        if (axi_req_i.ar_valid) begin
            araddr_d =      axi_req_i.ar.addr;
            arid_d =        axi_req_i.ar.id;
            arburst_d =     axi_req_i.ar.burst;
            arlen_d =       axi_req_i.ar.len + 1;   // ar_len = a => burst_length = a+1

            // Reset burst counter
            rburst_cnt_d = '0;
        end

    // During reading, manage araddr
    end else begin
        
        // On last address, start RLAST counter to align pulse with the actual data
        if (rburst_cnt_q == arlen_q) begin

            // If burst length is 1, assert LAST after initial latency count
            if (arlen_q == 1) begin
                axi_resp_d.r.last = latency_cnt_flag;
            end

            // RLAST counter: Stop when we reach READ_LATENCY-1 and raise flag
            else if (rlast_cnt_q==(READ_LATENCY-1)) begin
                rlast_cnt_d = rlast_cnt_q;
                axi_resp_d.r.last = 1;

            // RLAST counter: Otherwise count normally, gated by r_ready
            end else begin
                if (reg_r_ready) begin
                    rlast_cnt_d = rlast_cnt_q + 1;
                end else begin
                    rlast_cnt_d = rlast_cnt_q;
                end
            end

        // Increase address only if we have not reached the end of the burst
        end else begin

            // Stall readout if READY goes down, but only if pipeline is full
            if (reg_r_ready | (!latency_cnt_flag)) begin
            
                rburst_cnt_d = rburst_cnt_q + 1;

                // Different logic circuits depending on Burst Type
                case (arburst_q)

                    // FIXED BURST -> Address always the same
                    2'd0: begin
                        araddr_d = araddr_q;
                    end

                    // INCREMENTAL BURST -> Increment address on each beat
                    2'd1: begin
                        // Increment happens in real LSB
                        araddr_d[AxiAddrWidth-1:IF_LSB_BITS] = araddr_q[AxiAddrWidth-1:IF_LSB_BITS] + 1;
                    end

                    // WRAPPING BURST -> Increment address and wrap when necessary
                    2'd2: begin
                        
                        // WRAP => when address lower bits (that's why we AND) equal wrap size
                        if ((araddr_q & ar_wrap_size) == ar_wrap_size) begin
                            araddr_d = araddr_q - ar_wrap_size;
                        
                        // NORMAL INCREMENT
                        end else begin
                            araddr_d[AxiAddrWidth-1:IF_LSB_BITS] = araddr_q[AxiAddrWidth-1:IF_LSB_BITS] + 1;
                        end
                    end

                    // OTHERS -> FIXED
                    default: begin
                        araddr_d = araddr_q;
                    end
                endcase
            end
        end
    end
end

// -------------------------------------------------
// Registers
// -------------------------------------------------

// General registers & FFs
always_ff @(posedge clk_i or negedge rst_ni) begin : reg_general
    if(~rst_ni) begin
        wr_flag_q <= 0;
        rd_flag_q <= 0;
        awaddr_q <= '0;
        awid_q <= '0;
        araddr_q <= '0;
        arid_q <= '0;
        awburst_q <= '0;
        arburst_q <= '0;
        awlen_q <= '0;
        arlen_q <= '0;
        wburst_cnt_q <= '0;
        rburst_cnt_q <= '0;
        latency_cnt_q <= '0;
        rlast_cnt_q <= '0;
    end else begin
        wr_flag_q <= wr_flag_d;
        rd_flag_q <= rd_flag_d;
        awaddr_q <= awaddr_d;
        awid_q <= awid_d;
        araddr_q <= araddr_d;
        arid_q <= arid_d;
        awburst_q <= awburst_d;
        arburst_q <= arburst_d;
        awlen_q <= awlen_d;
        arlen_q <= arlen_d;
        wburst_cnt_q <= wburst_cnt_d;
        rburst_cnt_q <= rburst_cnt_d;
        latency_cnt_q <= latency_cnt_d;
        rlast_cnt_q <= rlast_cnt_d;
    end
end

// Read data is always taken directly from the registers module output
assign axi_resp_d.r.data = ram_dout_i;

// B channel output register
spill_register #(
    .T      ( b_chan_t ),
    .Bypass ( 1'b0          )
) i_b_spill_register (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .valid_i ( axi_resp_d.b_valid ),
    .ready_o ( reg_b_ready ),       
    .data_i  ( axi_resp_d.b       ),
    .valid_o ( axi_resp_q.b_valid ),
    .ready_i ( axi_req_i.b_ready  ),
    .data_o  ( axi_resp_q.b       )
);

// R channel output register
spill_register #(
    .T      ( r_chan_t ),
    .Bypass ( 1'b0          )
) i_r_spill_register (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .valid_i ( axi_resp_d.r_valid ),
    .ready_o ( reg_r_ready ),          
    .data_i  ( axi_resp_d.r       ),
    .valid_o ( axi_resp_q.r_valid ),
    .ready_i ( axi_req_i.r_ready  ),
    .data_o  ( axi_resp_q.r       )
);

// AW_ready, W_ready and AR_ready should also have a register to cut comb. paths
always_ff @(posedge clk_i or negedge rst_ni) begin : reg_ready
    if(~rst_ni) begin
        axi_resp_q.aw_ready <= 0;
        axi_resp_q.ar_ready <= 0;
        axi_resp_q.w_ready <= 0;
    end else begin
        axi_resp_q.aw_ready <= axi_resp_d.aw_ready;
        axi_resp_q.ar_ready <= axi_resp_d.ar_ready;
        axi_resp_q.w_ready <= axi_resp_d.w_ready;
    end
end

// Output response is the register output
assign axi_resp_o = axi_resp_q;

// -------------------------------------------------
// RAM signals management
// -------------------------------------------------

// Write enable: if writing on progress and w_valid
assign ram_wren_o = wr_flag_q && axi_req_i.w_valid;

// Read enable: if reading on progress and read pipeline enable = r_ready and not filling the pipeline
assign ram_rden_o = rd_flag_q && (reg_r_ready | (!latency_cnt_flag));

// Address multiplexing
assign ram_addr_o = (ram_wren_o)? awaddr_q : 
                    (ram_rden_o)? araddr_q : 
                    '0;

// Data values are mapped directly
assign ram_din_o      = axi_req_i.w.data;

// Mask => Conversion to all-bits format
genvar I;
generate
for(I=0; I<AxiStrbWidth; I=I+1) begin:  write_data_byte_en
    assign ram_wmask_o[(I*8)+:8]  = {{8'd8}{axi_req_i.w.strb[I]}};       // Replicate byte mask on all individual mask bits
end
endgenerate


endmodule
