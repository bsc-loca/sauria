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

module axi_lite_err_slv_intf #(
    parameter AxiDataWidth = 0,
    parameter [AxiDataWidth-1:0] ReadDataWord = 0
) (
    input clk,
    input rstn,
    AXI_LITE.Slave slv
);

    typedef enum bit [0:0] {
        AR,
        R
    } ReadState_t;

    typedef enum bit [1:0] {
        AW,
        W,
        B
    } WriteState_t;

    ReadState_t read_state;
    WriteState_t write_state;

    assign slv.ar_ready = read_state == AR;
    assign slv.r_valid = read_state == R;
    assign slv.aw_ready = write_state == AW;
    assign slv.w_ready = write_state == W;
    assign slv.b_valid = write_state == B;
    assign slv.r_data = ReadDataWord;
    assign slv.r_resp = 2'b11; //DECERR
    assign slv.b_resp = 2'b11;

    always_ff @(posedge clk) begin

        case (read_state)

            AR: begin
                if (slv.ar_valid) begin
                    read_state <= R;
                end
            end

            R: begin
                if (slv.r_ready) begin
                    read_state <= AR;
                end
            end

        endcase

        case (write_state)

            AW: begin
                if (slv.aw_valid) begin
                    write_state <= W;
                end
            end

            W: begin
                if (slv.w_valid) begin
                    write_state <= B;
                end
            end

            B: begin
                if (slv.b_ready) begin
                    write_state <= AW;
                end
            end

        endcase

        if (!rstn) begin
            read_state <= AR;
            write_state <= AW;
        end
    end

endmodule
