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
// Juan Miguel de Haro <juan.deharoruiz@bsc.es>
//

module axi_util_fifo_fallthrough #(
    parameter LEN = 0,
    parameter WIDTH = 0
) (
    input clk,
    input arstn,
    output full,
    input write,
    input [WIDTH-1:0] din,
    output empty,
    input read,
    output reg [WIDTH-1:0] dout
);

    if (LEN == 1) begin
    
        reg full_reg;
        
        assign full = full_reg;
        assign empty = !full_reg;
        
        always_ff @(posedge clk, negedge arstn) begin
            if (!arstn) begin
                full_reg <= 1'b0;
            end else begin
                if (write) begin
                    dout <= din;
                    full_reg <= 1'b1;
                end else if (read) begin
                    full_reg <= 1'b0;
                end
            end
        end
        
    end else begin

    localparam CLOG2LEN = $clog2(LEN);
    localparam LAST_IDX = LEN-1;
    localparam CLOG2LEN_0 = {CLOG2LEN{1'b0}};
    localparam CLOG2LEN_1 = {{CLOG2LEN-1{1'b0}}, 1'b1};
    localparam IDX_0 = {CLOG2LEN+1{1'b0}};
    localparam IDX_1 = {{CLOG2LEN{1'b0}}, 1'b1};
    localparam POWER_2 = (LEN & (LEN-1)) == 0;

    reg [CLOG2LEN:0] read_idx;
    wire [CLOG2LEN:0] next_read_idx;
    reg [CLOG2LEN:0] write_idx;
    wire [CLOG2LEN:0] next_write_idx;

    assign empty = read_idx == write_idx;
    assign full = read_idx[CLOG2LEN-1:0] == write_idx[CLOG2LEN-1:0] && read_idx[CLOG2LEN] != write_idx[CLOG2LEN];

    if (POWER_2) begin
        assign next_read_idx = read_idx + IDX_1;
        assign next_write_idx = write_idx + IDX_1;
    end else begin
        assign next_read_idx[CLOG2LEN-1:0] = (read_idx[CLOG2LEN-1:0] == LAST_IDX[CLOG2LEN-1:0]) ? CLOG2LEN_0 : (read_idx[CLOG2LEN-1:0] + CLOG2LEN_1);
        assign next_read_idx[CLOG2LEN] = (read_idx[CLOG2LEN-1:0] == LAST_IDX[CLOG2LEN-1:0]) ? !read_idx[CLOG2LEN] : read_idx[CLOG2LEN];
        assign next_write_idx[CLOG2LEN-1:0] = (write_idx[CLOG2LEN-1:0] == LAST_IDX[CLOG2LEN-1:0]) ? CLOG2LEN_0 : (write_idx[CLOG2LEN-1:0] + CLOG2LEN_1);
        assign next_write_idx[CLOG2LEN] = (write_idx[CLOG2LEN-1:0] == LAST_IDX[CLOG2LEN-1:0]) ? !write_idx[CLOG2LEN] : write_idx[CLOG2LEN];
    end

    always_ff @(posedge clk, negedge arstn) begin
        if (!arstn) begin
            read_idx <= IDX_0;
            write_idx <= IDX_0;
        end else begin
            if (read) begin
                read_idx <= next_read_idx;
            end
            if (write) begin
                write_idx <= next_write_idx;
            end
        end
    end

    reg [WIDTH-1:0] mem[LEN];

    always_ff @(posedge clk) begin
        dout <= mem[read_idx[CLOG2LEN-1:0]];
        if (write && empty || (write && read && next_read_idx[CLOG2LEN-1:0] == write_idx[CLOG2LEN-1:0])) begin
            dout <= din;
        end else if (read) begin
            dout <= mem[next_read_idx[CLOG2LEN-1:0]];
        end
        if (write) begin
            mem[write_idx[CLOG2LEN-1:0]] <= din;
        end
    end
    
    end
endmodule
