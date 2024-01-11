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

module sauria_dma_pointer_generator (
    input clk,
    input rst,
    input advance,
    input df_ctrl_pkg::TilePointers p,
    input [1:0] loop_order,
    output reg [23:0] ifmap_xcounter,
    output reg [23:0] ifmap_ycounter,
    output reg [23:0] ifmap_ccounter,
    output reg [23:0] psums_xcounter,
    output reg [23:0] psums_ycounter,
    output reg [23:0] psums_kcounter,
    output reg [23:0] weights_ccounter,
    output reg [23:0] weights_kcounter,
    output reg ifmaps_change,
    output reg psums_change,
    output reg weights_change,
    output last_iter
);

    reg [11:0] x;
    reg [11:0] y;
    reg [11:0] c;
    reg [11:0] k;

    wire [3:0] overflow;

    assign last_iter = &overflow;

    assign overflow[0] = x == p.x_lim;
    assign overflow[1] = y == p.y_lim;
    assign overflow[2] = c == p.c_lim;
    assign overflow[3] = k == p.k_lim;

    logic spatial_cond;
    logic c_cond;
    logic k_cond;

    always_comb begin
        if (loop_order == 2'd0) begin
            spatial_cond = 1'b1;
            c_cond = overflow[0] & overflow[1];
            k_cond = c_cond & overflow[2];
        end else if (loop_order == 2'd1) begin
            c_cond = 1'b1;
            k_cond = overflow[2];
            spatial_cond = k_cond & overflow[3];
        end else begin
            k_cond = 1'b1;
            c_cond = overflow[3];
            spatial_cond = c_cond & overflow[2];
        end
    end

    always_ff @(posedge clk) begin
        if (advance) begin
            ifmaps_change <= 1'b0;
            psums_change <= 1'b0;
            weights_change <= 1'b0;
            if (spatial_cond) begin
                if (p.x_lim != 12'd0 || p.y_lim != 12'd0) begin
                    ifmaps_change <= 1'b1;
                    psums_change <= 1'b1;
                end
                if (overflow[0]) begin
                    x <= 12'd0;
                    ifmap_xcounter <= 24'd0;
                    psums_xcounter <= 24'd0;
                end else begin
                    x <= x + 12'd1;
                    ifmap_xcounter <= ifmap_xcounter + p.ifmaps.x_step;
                    psums_xcounter <= psums_xcounter + p.psums.x_step;
                end
                if (overflow[0]) begin
                    if (overflow[1]) begin
                        y <= 12'd0;
                        ifmap_ycounter <= 24'd0;
                        psums_ycounter <= 24'd0;
                    end else begin
                        y <= y + 12'd1;
                        ifmap_ycounter <= ifmap_ycounter + p.ifmaps.y_step;
                        psums_ycounter <= psums_ycounter + p.psums.y_step;
                    end
                end
            end
            if (c_cond) begin
                if (p.c_lim != 12'd0) begin
                    ifmaps_change <= 1'b1;
                    weights_change <= 1'b1;
                end
                if (overflow[2]) begin
                    c <= 12'd0;
                    ifmap_ccounter <= 24'd0;
                    weights_ccounter <= 24'd0;
                end else begin
                    c <= c + 12'd1;
                    ifmap_ccounter <= ifmap_ccounter + p.ifmaps.c_step;
                    weights_ccounter <= weights_ccounter + p.weights.c_step;
                end
            end
            if (k_cond) begin
                if (p.k_lim) begin
                    psums_change <= 1'b1;
                    weights_change <= 1'b1;
                end
                if (overflow[3]) begin
                    k <= 12'd0;
                    psums_kcounter <= 24'd0;
                    weights_kcounter <= 24'd0;
                end else begin
                    k <= k + 12'd1;
                    psums_kcounter <= psums_kcounter + p.psums.k_step;
                    weights_kcounter <= weights_kcounter + p.weights.k_step;
                end
            end
        end

        if (rst) begin
            x <= 12'd0;
            y <= 12'd0;
            c <= 12'd0;
            k <= 12'd0;
            ifmap_xcounter <= 24'd0;
            ifmap_ycounter <= 24'd0;
            ifmap_ccounter <= 24'd0;
            psums_xcounter <= 24'd0;
            psums_ycounter <= 24'd0;
            psums_kcounter <= 24'd0;
            weights_ccounter <= 24'd0;
            weights_kcounter <= 24'd0;
            ifmaps_change <= 1'b1;
            psums_change <= 1'b1;
            weights_change <= 1'b1;
        end
    end

endmodule
