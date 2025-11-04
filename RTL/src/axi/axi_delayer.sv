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
// Jordi Fornt <jfornt@bsc.es>
//

module axi_delayer #(
    parameter MAX_OUTSTANDING_AW = 0,
    parameter MAX_OUTSTANDING_W = 0,
    parameter MAX_OUTSTANDING_R = 0,
    parameter READ_LATENCY = 0,
    parameter READ_BANDWIDTH_UP = 1,
    parameter READ_BANDWIDTH_DOWN = 0,
    parameter READ_BANDWIDTH_RAND = 0,
    parameter READ_BANDWIDTH_UP_PROB = 0,
    parameter READ_BANDWIDTH_DOWN_PROB = 0,
    parameter WRITE_LATENCY = 0,
    parameter WRITE_BANDWIDTH_UP = 1,
    parameter WRITE_BANDWIDTH_DOWN = 0,
    parameter WRITE_BANDWIDTH_RAND = 0,
    parameter WRITE_BANDWIDTH_UP_PROB = 0,
    parameter WRITE_BANDWIDTH_DOWN_PROB = 0,
    parameter TIMER_WIDTH = 0,
    parameter AxiIdWidth = 0,
    parameter AxiDataWidth = 0,
    parameter AxiAddrWidth = 0,
    /// Request struct of the AXI4 port.
    parameter type req_t = logic,
    /// Response struct of the AXI4 port.
    parameter type resp_t = logic
) (
    input wire          clk,
    input wire          arstn,
    input  req_t        s_axi_req_i,
    output resp_t       s_axi_resp_o,
    output  req_t       m_axi_req_o,
    input resp_t        m_axi_resp_i
);

    // Channel contents are the same (we only play with valids and readys)
    assign m_axi_req_o.ar = s_axi_req_i.ar;
    assign m_axi_req_o.aw = s_axi_req_i.aw;
    assign m_axi_req_o.w = s_axi_req_i.w;
    assign s_axi_resp_o.b = m_axi_resp_i.b;
    assign s_axi_resp_o.r = m_axi_resp_i.r;

    localparam RU_BANDWIDTH_BITS = READ_BANDWIDTH_UP == 1 ? 1 : $clog2(READ_BANDWIDTH_UP);
    localparam RD_BANDWIDTH_BITS = (READ_BANDWIDTH_DOWN == 0 || READ_BANDWIDTH_DOWN == 1) ? 1 : $clog2(READ_BANDWIDTH_DOWN);
    localparam WU_BANDWIDTH_BITS = WRITE_BANDWIDTH_UP == 1 ? 1 : $clog2(WRITE_BANDWIDTH_UP);
    localparam WD_BANDWIDTH_BITS = (WRITE_BANDWIDTH_DOWN == 0 || WRITE_BANDWIDTH_DOWN == 1) ? 1 : $clog2(WRITE_BANDWIDTH_DOWN);

    wire read_fifo_full;
    wire [TIMER_WIDTH-1:0] read_fifo_din;
    wire read_fifo_wr_en;

    wire read_fifo_empty;
    wire [TIMER_WIDTH-1:0] read_fifo_dout;
    wire read_fifo_rd_en;

    wire aw_fifo_full;
    wire [TIMER_WIDTH-1:0] aw_fifo_din;
    wire aw_fifo_wr_en;

    wire aw_fifo_empty;
    wire [TIMER_WIDTH-1:0] aw_fifo_dout;
    wire aw_fifo_rd_en;

    wire w_fifo_full;
    wire [TIMER_WIDTH-1:0] w_fifo_din;
    wire w_fifo_wr_en;

    wire w_fifo_empty;
    wire [TIMER_WIDTH-1:0] w_fifo_dout;
    wire w_fifo_rd_en;

    reg [TIMER_WIDTH-1:0] timer;

    typedef enum bit [1:0] {
        READ_IDLE,
        READ_DATA,
        READ_DATA_WAIT
    } ReadState_t;

    localparam WRITE_DATA = 0;
    localparam WRITE_DATA_WAIT = 1;

    localparam WRITE_RESPONSE_IDLE = 0;
    localparam WRITE_RESPONSE_ISSUE = 1;

    ReadState_t read_state;
    reg [RU_BANDWIDTH_BITS-1:0] bandwidth_read_up_count;
    reg [RD_BANDWIDTH_BITS-1:0] bandwidth_read_down_count;
    reg [WU_BANDWIDTH_BITS-1:0] bandwidth_write_up_count;
    reg [WD_BANDWIDTH_BITS-1:0] bandwidth_write_down_count;
    reg [0:0] write_state;
    reg [0:0] write_response_state;

    wire aw_transfer;
    wire b_transfer;

    assign aw_transfer = s_axi_req_i.aw_valid && m_axi_resp_i.aw_ready;
    assign b_transfer = m_axi_resp_i.b_valid && s_axi_req_i.b_ready && write_response_state == WRITE_RESPONSE_ISSUE;

    assign m_axi_req_o.ar_valid = !read_fifo_full && s_axi_req_i.ar_valid;
    assign s_axi_resp_o.ar_ready = !read_fifo_full && m_axi_resp_i.ar_ready;
    assign read_fifo_wr_en = s_axi_req_i.ar_valid && !read_fifo_full && m_axi_resp_i.ar_ready;
    assign read_fifo_din = timer;

    assign m_axi_req_o.r_ready = read_state == READ_DATA && s_axi_req_i.r_ready;
    assign s_axi_resp_o.r_valid = read_state == READ_DATA && m_axi_resp_i.r_valid;
    assign read_fifo_rd_en = read_state == READ_DATA && m_axi_resp_i.r_valid && s_axi_req_i.r_ready && m_axi_resp_i.r.last;

    always_ff @(posedge clk, negedge arstn) begin
        if (!arstn) begin
            timer <= {TIMER_WIDTH{1'b0}};
        end else begin
            timer <= timer + {{TIMER_WIDTH-1{1'b0}}, 1'b1};
        end
    end

    always_ff @(posedge clk, negedge arstn) begin
        if (!arstn) begin
            read_state <= READ_IDLE;
        end else begin
        
        case (read_state)

            READ_IDLE: begin
                if (READ_BANDWIDTH_UP != 1) begin
                    bandwidth_read_up_count <= 0;
                end
                if (!read_fifo_empty && timer >= read_fifo_dout+READ_LATENCY) begin
                    read_state <= READ_DATA;
                end
            end

            READ_DATA: begin
                bandwidth_read_down_count <= 0;
                if (m_axi_resp_i.r_valid && s_axi_req_i.r_ready && m_axi_resp_i.r.last) begin
                    read_state <= READ_IDLE;
                end else if (m_axi_resp_i.r_valid && s_axi_req_i.r_ready) begin
                    if (READ_BANDWIDTH_RAND) begin
                        int r;
                        `ifdef RANDOM
                            r = $urandom_range(99);
                        `else
                            r = -1;
                        `endif
                        if (r < READ_BANDWIDTH_DOWN_PROB) begin
                            read_state <= READ_DATA_WAIT;
                        end
                    end else begin
                        if (READ_BANDWIDTH_UP != 1) begin
                            bandwidth_read_up_count <= bandwidth_read_up_count + 1;
                        end
                        if (READ_BANDWIDTH_DOWN != 0) begin
                            if (READ_BANDWIDTH_UP == 1 || bandwidth_read_up_count == READ_BANDWIDTH_UP-1) begin
                                read_state <= READ_DATA_WAIT;
                            end
                        end
                    end
                end
            end

            READ_DATA_WAIT: begin
                if (READ_BANDWIDTH_RAND) begin
                    int r;
                    `ifdef RANDOM
                        r = $urandom_range(99);
                    `else
                        r = -1;
                    `endif
                    if (r < READ_BANDWIDTH_UP_PROB) begin
                        read_state <= READ_DATA;
                    end
                end else begin
                    if (READ_BANDWIDTH_UP != 1) begin
                        bandwidth_read_up_count <= 0;
                    end
                    bandwidth_read_down_count <= bandwidth_read_down_count + 1;
                    if (bandwidth_read_down_count == READ_BANDWIDTH_DOWN-1) begin
                        read_state <= READ_DATA;
                    end
                end
            end

        endcase
        
        end
    end

    assign m_axi_req_o.aw_valid = !aw_fifo_full && s_axi_req_i.aw_valid;
    assign s_axi_resp_o.aw_ready = !aw_fifo_full && m_axi_resp_i.aw_ready;
    assign aw_fifo_din = timer;
    assign aw_fifo_wr_en = s_axi_req_i.aw_valid && m_axi_resp_i.aw_ready && !aw_fifo_full;
    assign m_axi_req_o.w_valid = s_axi_req_i.w_valid && !w_fifo_full && write_state == WRITE_DATA;
    assign s_axi_resp_o.w_ready = m_axi_resp_i.w_ready && !w_fifo_full && write_state == WRITE_DATA;
    assign w_fifo_wr_en = s_axi_req_i.w_valid && m_axi_resp_i.w_ready && s_axi_req_i.w.last && !w_fifo_full && write_state == WRITE_DATA;
    assign w_fifo_din = timer;

    always_ff @(posedge clk, negedge arstn) begin
        if (!arstn) begin
            bandwidth_write_up_count <= 0;
            write_state <= WRITE_DATA;
        end else begin
    
        case (write_state)

            WRITE_DATA: begin
                bandwidth_write_down_count <= 0;
                if (s_axi_req_i.w_valid && m_axi_resp_i.w_ready && !w_fifo_full) begin
                    if (WRITE_BANDWIDTH_RAND) begin
                        int r;
                        `ifdef RANDOM
                            r = $urandom_range(99);
                        `else
                            r = -1;
                        `endif
                        if (r < WRITE_BANDWIDTH_DOWN_PROB) begin
                            write_state <= WRITE_DATA_WAIT;
                        end
                    end else begin
                        if (WRITE_BANDWIDTH_UP != 1) begin
                            bandwidth_write_up_count <= bandwidth_write_up_count + 1;
                        end
                        if (WRITE_BANDWIDTH_DOWN != 0) begin
                            if (WRITE_BANDWIDTH_UP == 1 || bandwidth_write_up_count == WRITE_BANDWIDTH_UP-1) begin
                                write_state <= WRITE_DATA_WAIT;
                            end
                        end
                    end
                end
            end

            WRITE_DATA_WAIT: begin
                if (WRITE_BANDWIDTH_RAND) begin
                    int r;
                    `ifdef RANDOM
                        r = $urandom_range(99);
                    `else
                        r = -1;
                    `endif
                    if (r < WRITE_BANDWIDTH_UP_PROB) begin
                        write_state <= WRITE_DATA;
                    end
                end else begin
                    bandwidth_write_up_count <= 0;
                    bandwidth_write_down_count <= bandwidth_write_down_count + 1;
                    if (bandwidth_write_down_count == WRITE_BANDWIDTH_DOWN-1) begin
                        write_state <= WRITE_DATA;
                    end
                end
            end

        endcase

        end
    end

    assign aw_fifo_rd_en = write_response_state == WRITE_RESPONSE_IDLE && !w_fifo_empty && !aw_fifo_empty && timer >= w_fifo_dout+WRITE_LATENCY && timer >= aw_fifo_dout+WRITE_LATENCY;
    assign w_fifo_rd_en  = write_response_state == WRITE_RESPONSE_IDLE && !w_fifo_empty && !aw_fifo_empty && timer >= w_fifo_dout+WRITE_LATENCY && timer >= aw_fifo_dout+WRITE_LATENCY;
    assign m_axi_req_o.b_ready  = write_response_state == WRITE_RESPONSE_ISSUE && s_axi_req_i.b_ready;
    assign s_axi_resp_o.b_valid  = write_response_state == WRITE_RESPONSE_ISSUE && m_axi_resp_i.b_valid;

    always @(posedge clk, negedge arstn) begin
        if (!arstn) begin
            write_response_state <= WRITE_RESPONSE_IDLE;
        end else begin

        case(write_response_state)

            WRITE_RESPONSE_IDLE: begin
                if (!w_fifo_empty && timer >= w_fifo_dout+WRITE_LATENCY && !aw_fifo_empty && timer >= aw_fifo_dout+WRITE_LATENCY) begin
                    write_response_state <= WRITE_RESPONSE_ISSUE;
                end
            end

            WRITE_RESPONSE_ISSUE: begin
                if (m_axi_resp_i.b_valid && s_axi_req_i.b_ready) begin
                    write_response_state <= WRITE_RESPONSE_IDLE;
                end
            end

        endcase

        end
    end

    axi_util_fifo_fallthrough #(
        .LEN(MAX_OUTSTANDING_R),
        .WIDTH(TIMER_WIDTH)
    ) read_fifo (
        .clk(clk),
        .arstn(arstn),
        .full(read_fifo_full),
        .write(read_fifo_wr_en),
        .din(read_fifo_din),
        .empty(read_fifo_empty),
        .read(read_fifo_rd_en),
        .dout(read_fifo_dout)
    );

    axi_util_fifo_fallthrough #(
        .LEN(MAX_OUTSTANDING_AW),
        .WIDTH(TIMER_WIDTH)
    ) aw_fifo (
        .clk(clk),
        .arstn(arstn),
        .full(aw_fifo_full),
        .write(aw_fifo_wr_en),
        .din(aw_fifo_din),
        .empty(aw_fifo_empty),
        .read(aw_fifo_rd_en),
        .dout(aw_fifo_dout)
    );
    
    axi_util_fifo_fallthrough #(
        .LEN(MAX_OUTSTANDING_W),
        .WIDTH(TIMER_WIDTH)
    ) w_fifo (
        .clk(clk),
        .arstn(arstn),
        .full(w_fifo_full),
        .write(w_fifo_wr_en),
        .din(w_fifo_din),
        .empty(w_fifo_empty),
        .read(w_fifo_rd_en),
        .dout(w_fifo_dout)
    );

endmodule
