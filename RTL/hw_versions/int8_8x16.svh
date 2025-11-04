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

// Systolic Array Configuration
`define X   16                      // X-size of the systolic array
`define Y   8                       // Y-size of the systolic array

// Precision Configuration
`define ARITHMETIC   0              // Arithmetic representation (0=INT    1=FP)
`define IA_W   8                    // Activation operand bit width
`define IB_W   8                    // Weight operand bit width
`define OC_W   32                   // Output (psum) operand bit width

// FP Arithmetic definitions (LINKED TO FP_NEW PARAMS - DO NOT CHANGE)
`define FP_W    0                   // Total number of bits
`define MANT_W  0                   // Mantissa bits

// Memory Configuration
`define SRAMA_DEPTH     2048        // SRAM A depth
`define RF_A            0           // Set to 1 to partition SRAMA into several small Register Files
`define SRAMB_DEPTH     2048        // SRAM B depth
`define RF_B            1           // Set to 1 to partition SRAMB into several small Register Files
`define SRAMC_DEPTH     1024        // SRAM C depth
`define RF_C            0           // Set to 1 to partition SRAMC into several small Register Files

// Memory subsystem & Bandwidth Configuration
`define AXI_NOC_DATA_WIDTH  1024
`define DRAM_BANDWIDTH      160     // In bits/cycle - IMPORTANT: DRAM_BANDWIDTH <= AXI_NOC_DATA_WIDTH
`define DRAM_LATENCY        100     // In cycles

// PE Configuration
`define STAGES_MUL   0                      // Multiplier : Internal pipeline stages (Unsupported for FP)
`define INTERMEDIATE_PIPELINE_STAGE   1     // Pipeline stage between multiplier and adder (1=True    0=False)

// Feeders Configuration
`define M   3                               // Replication factor of IFmap Feeder
`define ACT_FIFO_POSITIONS   5              // IFmap FIFO positions (total registers:   Positions*M)
`define WEI_FIFO_POSITIONS   4              // Weight FIFO positions (total registers:   Positions)

// Approximation Configuration (0 = Exact)
`define MUL_TYPE   0                        // Type of Multiplier
`define M_APPROX   0                        // Primary Mult. approximation parameter
`define MM_APPROX   0                       // Secondary Mult. approximation parameter
`define ADD_TYPE   0                        // Type of Adder
`define A_APPROX   0          	            // Primary Adder approximation parameter
`define AA_APPROX   0                       // Secondary Adder approximation parameter
