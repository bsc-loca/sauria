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

`define NEGLIGENCE          // Leave uncommented to use negligence logic

`define SIGNED_INT          // Leave uncommented to interpret inputs as signed fix-point integers
//`define FLOAT             // Leave uncommented to interpret inputs as floating point numbers

// --------------------
// MODULE DECLARATION
// --------------------

module zero_det_neg #(
    parameter IA_W = 16,
    parameter IB_W = 16,
    parameter TH_W = 2
)(
	// Data Inputs
    input  logic [IA_W-1:0]   	i_a,	// Activation operand
	input  logic [IB_W-1:0]		i_b,	// Weight operand
	
	// Control Inputs
	input  logic [TH_W-1:0]		i_thres,        // Negligence threshold
	
	// Control Outputs
	output  logic               o_zero_det 	    // Zero detection / negligence output
);

// ----------
// SIGNALS
// ----------

// Control
logic exact_zero_det, neg_det_a, neg_det_b, neg_det;

localparam dec_bits = 2**TH_W -1;
logic [dec_bits-1:0] thres_dec;

// Data (SIGNED INT)
logic [IA_W-1:1] a_neg_inputs_p, a_neg_inputs_n;    // 0th not included -> If we do negligence, we neglect at least 1 bit
logic [IB_W-1:1] b_neg_inputs_p, b_neg_inputs_n;

// Data (FLOAT)
localparam a_exp_bit_max = 14;
localparam a_exp_bit_min = 10;
localparam b_exp_bit_max = 14;
localparam b_exp_bit_min = 10;

logic [a_exp_bit_max:a_exp_bit_min+1] a_exp_inputs;     // 0th not included -> If we do negligence, we neglect at least 1 bit
logic [b_exp_bit_max:b_exp_bit_min+1] b_exp_inputs;

// -----------------------
// Exact Zero Detection
// -----------------------

always_comb begin
    if ((i_a == 0) || (i_b == 0)) begin
        exact_zero_det = 1;
    end else begin
        exact_zero_det = 0;
    end
end

// ----------------------------------------------------------------
// Negligence logic
// ----------------------------------------------------------------

`ifdef NEGLIGENCE

    // +++++++++++++++++++
    // Threshold Decoder
    // +++++++++++++++++++

    always_comb begin
        for (integer b=0; b<dec_bits; b=b+1) begin

            //thres_dec[b] = (b<i_thres);

            if (b<i_thres) begin
                thres_dec[b] = 1;
            end else begin
                thres_dec[b] = 0;
            end
        end
    end

    // +++++++++++++++++++++++
    // Signed Int Negligence
    // +++++++++++++++++++++++

    `ifdef SIGNED_INT

        always_comb begin

            // If threshold value is zero, silence comparison inputs (don't do negligence) => To avoid switching
            if (i_thres==0) begin
            
                a_neg_inputs_p = '1;
                a_neg_inputs_n = '0;
                b_neg_inputs_p = '1;
                b_neg_inputs_n = '0;

            // If threshold value is nonzero, assign comparison inputs
            end else begin

                // Select comparison inputs depending on threshold (i_a) => 0th element not included
                for (integer ba=1; ba<IA_W; ba=ba+1) begin
                    
                    if(ba<dec_bits) begin

                        if (thres_dec[ba]) begin
                            a_neg_inputs_p[ba] = 0;           // For positive values, trigger is all zeros
                            a_neg_inputs_n[ba] = 1;           // For negative values, trigger is all ones
                        end else begin
                            a_neg_inputs_p[ba] = i_a[ba];
                            a_neg_inputs_n[ba] = i_a[ba];
                        end
                        
                    end else begin
                        a_neg_inputs_p[ba] = i_a[ba];
                        a_neg_inputs_n[ba] = i_a[ba];
                    end

                end
            
                // Select comparison inputs depending on threshold (i_b) => 0th element not included [Same as above]
                for (integer bb=1; bb<IB_W; bb=bb+1) begin
                    
                    if(bb<dec_bits) begin

                        if (thres_dec[bb]) begin
                            b_neg_inputs_p[bb] = 0;           // For positive values, trigger is all zeros
                            b_neg_inputs_n[bb] = 1;           // For negative values, trigger is all ones
                        end else begin
                            b_neg_inputs_p[bb] = i_b[bb];
                            b_neg_inputs_n[bb] = i_b[bb];
                        end
                        
                    end else begin
                        b_neg_inputs_p[bb] = i_b[bb];
                        b_neg_inputs_n[bb] = i_b[bb];
                    end

                end

            end
            
            // Perform negligence comparison
            neg_det_a = (a_neg_inputs_p=='0) || (a_neg_inputs_n=='1);
            neg_det_b = (b_neg_inputs_p=='0) || (b_neg_inputs_n=='1);

            // Output high iff both are small enough
            neg_det = neg_det_a & neg_det_b;
        
        end

    `endif

    // +++++++++++++++++++++++++++
    // Floating point Negligence
    // +++++++++++++++++++++++++++

    `ifdef FLOAT

            // If threshold value is zero, silence comparison inputs (don't do negligence) => To avoid switching
            if (i_thres==0) begin
            
                a_exp_inputs = '1;
                b_exp_inputs = '1;

            // If threshold value is nonzero, assign comparison inputs
            end else begin

                // Select comparison inputs depending on threshold (i_a) => 0th element not included
                for (integer ba=a_exp_bit_min; ba<=a_exp_bit_max; ba=ba+1) begin
                    
                    if(ba<(dec_bits+a_exp_bit_min)) begin

                        if (thres_dec[ba]) begin
                            a_exp_inputs[ba] = 0;
                        end else begin
                            a_exp_inputs[ba] = i_a[ba];
                        end
                        
                    end else begin
                        a_exp_inputs[ba] = i_a[ba];
                    end

                end
            
                // Select comparison inputs depending on threshold (i_b) => 0th element not included [Same as above]
                for (integer bb=b_exp_bit_min; bb<=b_exp_bit_max; bb=bb+1) begin
                    
                    if(bb<(dec_bits+b_exp_bit_min)) begin

                        if (thres_dec[bb]) begin
                            b_exp_inputs[bb] = 0;
                        end else begin
                            b_exp_inputs[bb] = i_b[bb];
                        end
                        
                    end else begin
                        b_exp_inputs[bb] = i_b[bb];
                    end

                end
            
            // Perform negligence comparison
            neg_det_a = (a_exp_inputs=='0);
            neg_det_b = (b_exp_inputs=='0);

            // Output high iff both are small enough
            neg_det = neg_det_a & neg_det_b;

    `endif

    // ++++++++++++++++++++++++++++++++++++++
    // Output: zero detection or negligence
    // ++++++++++++++++++++++++++++++++++++++

    assign o_zero_det = exact_zero_det | neg_det;

// +++++++++++++++++++++++++++++++++
// If not defined, just take exact
// +++++++++++++++++++++++++++++++++

`else
    assign o_zero_det = exact_zero_det;
`endif

endmodule
