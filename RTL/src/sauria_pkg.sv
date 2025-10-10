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

package sauria_pkg;

    // Systolic Array Configuration
    parameter X = `X;                           // X-size of the systolic array
    parameter Y = `Y;                           // Y-size of the systolic array
    parameter IA_W = `IA_W;                     // Activation operand bit width
    parameter IB_W = `IB_W;                     // Weight operand bit width
    parameter OC_W = `OC_W;                     // Output (psum) operand bit width
    parameter TH_W = 2;                         // Negligence threshold bit width
    parameter PARAMS_W = 8;                     // Parametric bit width (controls width of different signals)

    parameter SRAMC_N = int'(SRAMC_W/OC_W);     // SRAM C - number of elements in the bus

    // Arithmetic & PE Configuration
    parameter STAGES_MUL = `STAGES_MUL;         // Multiplier : Internal pipeline stages (Unsupported for FP)
    parameter INTERMEDIATE_PIPELINE_STAGE = `INTERMEDIATE_PIPELINE_STAGE;  // Pipeline stage between multiplier and adder (1=True; 0=False)
    parameter ZERO_GATING_MULT = 1;             // Zero Gating @ Multiplier (optimal = 1)
    parameter ZERO_GATING_ADD = 0;              // Zero Gating @ Adder (optimal = 0)
    parameter ZD_LOOKAHEAD = 1;                 // Zero Detection Lookahead (leave at 1)
    parameter EXTRA_CSREG = 1;                  // Extra Pipeline register in cswitch signal
    
    parameter ARITHMETIC = `ARITHMETIC;     // Arithmetic representation (0=INT; 1=FP)
    parameter MUL_TYPE = `MUL_TYPE;         // Type of Multiplier
    parameter M_APPROX = `M_APPROX;         // Primary Mult. approximation parameter
    parameter MM_APPROX = `MM_APPROX;       // Secondary Mult. approximation parameter
    parameter ADD_TYPE = `ADD_TYPE;         // Type of Adder
    parameter A_APPROX = `A_APPROX;       	// Primary Adder approximation parameter
    parameter AA_APPROX = `AA_APPROX;       // Secondary Adder approximation parameter

    // FP16 Arithmetic definitions (LINKED TO FP_NEW PARAMS - DO NOT CHANGE)
    parameter FP_W = `FP_W;                 // Total number of bits
    parameter MANT_W = `MANT_W;             // Mantissa bits
    parameter EXP_W = FP_W-MANT_W-1;        // Exponent bits

    // Memory Configuration
    parameter SRAMA_W       = IA_W*Y;           // SRAM A data width
    parameter SRAMA_DEPTH   = `SRAMA_DEPTH;     // SRAM A depth
    parameter RF_A          = 0;                // Set to 1 to partition SRAMA into several small Register Files
    parameter ADRA_W = $clog2(SRAMA_DEPTH);     // SRAM A address width

    parameter SRAMB_W       = IB_W*X;           // SRAM B data width
    parameter SRAMB_DEPTH   = `SRAMB_DEPTH;     // SRAM B depth
    parameter RF_B          = 1;                // Set to 1 to partition SRAMB into several small Register Files
    parameter ADRB_W = $clog2(SRAMB_DEPTH);     // SRAM B address width

    parameter SRAMC_W       = OC_W*Y;           // SRAM C data width
    parameter SRAMC_DEPTH   = `SRAMC_DEPTH;     // SRAM C depth
    parameter RF_C          = 0;                // Set to 1 to partition SRAMC into several small Register Files
    parameter ADRC_W = $clog2(SRAMC_DEPTH);     // SRAM C address width

    // IFmap Feeders Configuration
    parameter M = `M;                           // Replication factor of IFmap Feeder
    parameter ACT_FIFO_POSITIONS = `ACT_FIFO_POSITIONS;// IFmap FIFO positions (total registers = Positions*M)
    parameter DILP_W = 64;                      // Dilation pattern width

    // Weight Fetcher Configuration
    parameter WEI_FIFO_POSITIONS = `WEI_FIFO_POSITIONS;// Weight FIFO positions (total registers = Positions)

    // AXI CDC Size
    parameter CFG_CDC_FIFO_BITS     = 2;        // CDC FIFO will contain 2**CDC_FIFO_BITS positions
    parameter DATA_CDC_FIFO_BITS    = 3;        // CDC FIFO will contain 2**CDC_FIFO_BITS positions

    // DMA Configuration
    parameter DMA_MAX_ARLEN                 = 255;
    parameter DMA_MAX_AWLEN                 = 255;
    parameter DMA_RFIFO_LEN                 = 2;
    parameter DMA_WFIFO_LEN                 = 2;
    parameter DMA_RADDR_OFFSET              = 0;        //offset of the DMA AXI master reader addresses; must be multiple of 4GB
    parameter DMA_WADDR_OFFSET              = 0;        //offset of the DNA AXI master writer addresses; must be multiple of 4GB
    parameter DATA_ELM_BITS                 = 8;        // Width of the axi data bus elements (integer multiple of 8)
    parameter DMA_SYNC_AW_W                 = 0;        // synchronize AW and W channels; adress is not valid until there is data availbale in the writer FIFO
    parameter DMA_MAX_OUTSTANDING_READS     = 8;        // Max concurrent reads
    parameter DMA_MAX_OUTSTANDING_WRITES    = 8;        // Max concurrent writes

endpackage