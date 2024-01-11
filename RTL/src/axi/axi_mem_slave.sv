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

module axi_mem_slave #(

    /// The minimum value of this parameter is `$clog2(RegNumBytes)`.
    parameter int unsigned AxiAddrWidth = 32'd0,
    /// Data width of the AXI4 port.
    parameter int unsigned AxiDataWidth = 32'd0,
    /// Width of the ID port
    parameter int unsigned AxiIdWidth = 32'd0,

    /// Request struct of the AXI4 port.
    parameter type req_t = logic,
    /// Response struct of the AXI4 port.
    parameter type resp_t = logic
) (

    input  logic                          clk_i,
    input  logic                          rst_ni,

    input  req_t                          axi_req_i,
    output resp_t                         axi_resp_o
);

// ----------------------
// SIGNALS
// ----------------------

typedef logic [AxiAddrWidth-1:0]     addr_t;

localparam BUS_BYTES = AxiDataWidth/8;
localparam IF_LSB_BITS = $clog2(AxiDataWidth/8);

logic  [AxiAddrWidth-1:0]     ram_addr;
logic  [AxiDataWidth-1:0]     ram_din;
logic  [AxiDataWidth-1:0]     ram_wmask;
logic                         ram_wren;
logic                         ram_rden;
logic  [AxiDataWidth-1:0]     ram_dout, ram_dout_q1;

logic [7:0] mem [addr_t];

// ----------------------
// MODULE INSTANTIATION
// ----------------------

axi_full_2ram #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .READ_LATENCY(1),
    .PrivProtOnly(0),
    .SecuProtOnly(0),
    .req_t(req_t),
    .resp_t(resp_t)
) axi_full_if (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .axi_req_i(axi_req_i),
    .axi_resp_o(axi_resp_o),
    .ram_addr_o(ram_addr),
    .ram_din_o(ram_din),
    .ram_wmask_o(ram_wmask),
    .ram_wren_o(ram_wren),
    .ram_rden_o(ram_rden),
    .ram_dout_i(ram_dout)
);

// ----------
// RAM
// ----------

logic cen, rdwen;

assign cen = !(ram_wren | ram_rden);
assign rdwen = (ram_rden | (!ram_wren));

always @(posedge clk_i) begin: ram
    
    // Active-low Chip Enable
    if (!cen) begin

        // Write (active low)
        if (!rdwen) begin
            
            // Update all affected bytes
            for (integer b=0; b < BUS_BYTES; b += 1) begin

                // Byte mask (converted from bitwise mask)
                if (ram_wmask[8*b]) begin
                    mem[ram_addr+b] = ram_din[8*b +: 8];
                end
            end

        // Read
        end else begin
            // Update all bytes
            for (integer t=0; t < BUS_BYTES; t += 1) begin
                ram_dout[8*t +: 8] <= mem[ram_addr+t];
            end
        end
    end
end

endmodule
