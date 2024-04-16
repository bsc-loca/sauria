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

package sauria_addr_pkg;

    // Configuration AXI Address Space
    parameter CONTROLLER_OFFSET = 32'h4410_0000;
    parameter SAURIA_OFFSET     = 32'h4420_0000;
    parameter DMA_OFFSET        = 32'h4430_0000;

    // SAURIA Internal Address Space
    parameter CFG_REGS_OFFSET   = 32'h0000_0000;
    parameter CFG_CON_OFFSET    = 32'h0000_0200;
    parameter CFG_ACT_OFFSET    = 32'h0000_0400;
    parameter CFG_WEI_OFFSET    = 32'h0000_0600;
    parameter CFG_OUT_OFFSET    = 32'h0000_0800;
    parameter SRAMA_OFFSET      = 32'h0001_0000;
    parameter SRAMB_OFFSET      = 32'h0002_0000;
    parameter SRAMC_OFFSET      = 32'h0003_0000;

    // DMA Internal Address Space
    parameter SAURIA_DMA_OFFSET         = 32'hD000_0000;
    parameter SAURIA_DMA_ADDR_MASK      = 32'hF000_0000;

    // Address masks
    parameter AXI_CONTROLLER_ADDR_MASK      = 32'hFFFF_FF00;
    parameter AXI_SAURIA_ADDR_MASK          = 32'hFFF0_0000;
    parameter AXI_DMA_ADDR_MASK             = 32'hFFFF_FFC0;

    parameter SAURIA_MEM_ADDR_MASK          = 32'h000F_0000;
    parameter SAURIA_REG_ADDR_MASK          = 32'h000F_FE00;

endpackage