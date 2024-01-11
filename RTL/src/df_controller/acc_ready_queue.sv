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

module acc_ready_queue #(
    parameter NSLOTS = 1,
    parameter NARGS = 1
) (
    input clk,
    input rst,
    QueueRead.slave read_port,
    QueueWrite.slave write_port
);

    localparam SLOT_SIZE = NARGS+2; //tid and twid
    localparam LEN = NSLOTS*SLOT_SIZE;
    localparam CLOG2LEN = $clog2(LEN);
    localparam CLOG2LEN_0 = {CLOG2LEN{1'b0}};
    localparam CLOG2LEN_1 = {{CLOG2LEN-1{1'b0}}, 1'b1};
    localparam POWER_2 = (LEN & (LEN-1)) == 0;

    localparam [CLOG2LEN-1:0] LAST_IDX = LEN-1;
    localparam [CLOG2LEN:0] FULL_LIMIT_IDX = (NSLOTS-1)*SLOT_SIZE;

    reg overflow;
    reg [CLOG2LEN-1:0] read_idx;
    reg [CLOG2LEN-1:0] write_idx;
    wire [CLOG2LEN:0] size;
    wire empty;
    wire full;

    assign size = {overflow, write_idx} - {1'b0, read_idx};

    assign empty = size < SLOT_SIZE[CLOG2LEN:0];
    assign full = size > FULL_LIMIT_IDX;

    assign read_port.empty = empty;
    assign write_port.full = full;

    always_ff @(posedge clk) begin
        if (read_port.read) begin
            if (read_idx == LAST_IDX) begin
                overflow <= 1'b0;
            end
            if (POWER_2) begin
                read_idx <= read_idx + CLOG2LEN_1;
            end else begin
                if (read_idx == LAST_IDX) begin
                    read_idx <= CLOG2LEN_0;
                end else begin
                    read_idx <= read_idx + CLOG2LEN_1;
                end
            end
        end
        if (write_port.write) begin
            if (write_idx == LAST_IDX) begin
                overflow <= 1'b1;
            end
            if (POWER_2) begin
                write_idx <= write_idx + CLOG2LEN_1;
            end else begin
                if (write_idx == LAST_IDX) begin
                    write_idx <= CLOG2LEN_0;
                end else begin
                    write_idx <= write_idx + CLOG2LEN_1;
                end
            end
        end
        if (rst) begin
            overflow <= 1'b0;
            read_idx <= CLOG2LEN_0;
            write_idx <= CLOG2LEN_0;
        end
    end

    reg [63:0] mem[LEN];

    always_ff @(posedge clk) begin
        if (read_port.read) begin
            read_port.dout <= mem[read_idx];
        end
        if (write_port.write) begin
            mem[write_idx] <= write_port.din;
        end
    end
endmodule
