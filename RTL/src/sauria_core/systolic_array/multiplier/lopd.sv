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

module lopd #(
    parameter I_W = 16,
    localparam O_W = $clog2(I_W)
)(
	// Data Inputs
    input  logic [I_W-1:0]   	i_d,	    // Input data

	// Data Outputs 
	output logic [O_W-1:0]  	o_d 	    // Output Value
);

// -------------------------
// Behavioral description
// -------------------------

logic [O_W-1:0] one_location;

always_comb begin : leading_one_position_detector

    one_location = 0;

    // Start from LSB, get position of 1s, settle only if it's the last
    for (integer b=0; b<I_W; b++) begin
        if (i_d[b]) begin
            one_location = b;            
        end
    end
end

// Output management
assign o_d = one_location;

endmodule
