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
// MODULE DECLARATION
// --------------------

module cdc_sync_reg #(
    parameter STAGES = 2
)(
    input  logic        i_dst_clk,
    input  logic        i_dst_rstn,
    input  logic        i_signal,
    output logic        o_signal
);
// ------------------------------------------------------------
// Signals
// ------------------------------------------------------------

(* ASYNC_REG = "TRUE" *) logic [0:STAGES]	reg_q /*verilator split_var*/;

// ------------------------
// Registers instantiation
// ------------------------

genvar k;
generate
    // Generate one instance per position
    for (k=1; k<STAGES+1; k=k+1) begin
        // Normal FF behavior
		always_ff @(posedge i_dst_clk or negedge i_dst_rstn) begin : sync_regs
			if(~i_dst_rstn) begin
				reg_q[k] <= 0;
			end else begin
				reg_q[k] <= reg_q[k-1];
			end
		end
    end
endgenerate

// -------------------
// IO Mapping
// -------------------

assign reg_q[0] = i_signal;
assign o_signal = reg_q[STAGES];


endmodule