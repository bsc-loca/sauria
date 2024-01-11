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
//      INCLUDES
// --------------------

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "common_cells/registers.svh"

// --------------------
// MODULE DECLARATION
// --------------------

module sauria_core #(

    parameter CFG_AXI_DATA_WIDTH    = 32,       // Configuration AXI4-Lite Slave data width
    parameter CFG_AXI_ADDR_WIDTH    = 32,       // Configuration AXI4-Lite Slave address width

    parameter DATA_AXI_DATA_WIDTH   = 128,      // Data AXI4 Slave data width
    parameter DATA_AXI_ADDR_WIDTH   = 32,       // Data AXI4 Slave address width
    parameter DATA_AXI_ID_WIDTH     = 2,        // Data AXI4 Slave ID width

    localparam  BYTE = 8,
    localparam  CFG_AXI_BYTE_NUM = CFG_AXI_DATA_WIDTH/BYTE,
    localparam  DATA_AXI_BYTE_NUM = DATA_AXI_DATA_WIDTH/BYTE
)(
    // Clk, RST
	  input  logic 			i_clk,
	  input  logic			i_rstn,

    // AXI Interfaces
    AXI_LITE.Slave    cfg_slv,
    AXI_BUS.Slave     mem_slv,

    // Done Interrupt
    output logic      o_doneintr          // Completion interrupt
);

// ------------------------------------------------------------
// AXI Interface Wrapper
// ------------------------------------------------------------

  // MEMORY (DATA) PORT
  typedef logic [DATA_AXI_ID_WIDTH-1:0]     id_t;
  typedef logic [DATA_AXI_ADDR_WIDTH-1:0]   addr_t;
  typedef logic [DATA_AXI_DATA_WIDTH-1:0]   data_t;
  typedef logic [DATA_AXI_DATA_WIDTH/8-1:0] strb_t;
  typedef logic [0:0]                       user_t;
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)
  `AXI_TYPEDEF_REQ_T(dat_req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(dat_resp_t, b_chan_t, r_chan_t)

  dat_req_t   dat_axi_req;          // Request
  dat_resp_t  dat_axi_resp;         // Response

  `AXI_ASSIGN_TO_REQ(dat_axi_req, mem_slv)
  `AXI_ASSIGN_FROM_RESP(mem_slv, dat_axi_resp)

  // CONFIG PORT
  typedef logic [CFG_AXI_ADDR_WIDTH-1:0]   addr_lite_t;
  typedef logic [CFG_AXI_DATA_WIDTH-1:0]   data_lite_t;
  typedef logic [CFG_AXI_DATA_WIDTH/8-1:0] strb_lite_t;
  `AXI_LITE_TYPEDEF_AW_CHAN_T(aw_chan_lite_t, addr_lite_t)
  `AXI_LITE_TYPEDEF_W_CHAN_T(w_chan_lite_t, data_lite_t, strb_lite_t)
  `AXI_LITE_TYPEDEF_B_CHAN_T(b_chan_lite_t)
  `AXI_LITE_TYPEDEF_AR_CHAN_T(ar_chan_lite_t, addr_lite_t)
  `AXI_LITE_TYPEDEF_R_CHAN_T(r_chan_lite_t, data_lite_t)
  `AXI_LITE_TYPEDEF_REQ_T(cfg_req_lite_t, aw_chan_lite_t, w_chan_lite_t, ar_chan_lite_t)
  `AXI_LITE_TYPEDEF_RESP_T(cfg_resp_lite_t, b_chan_lite_t, r_chan_lite_t)

  cfg_req_lite_t  cfg_axi_req;      // Request
  cfg_resp_lite_t cfg_axi_resp;     // Response

  `AXI_LITE_ASSIGN_TO_REQ(cfg_axi_req, cfg_slv)
  `AXI_LITE_ASSIGN_FROM_RESP(cfg_slv, cfg_axi_resp)

// ------------------------------------------------------------
// Signals for SRAM connection
// ------------------------------------------------------------

localparam SRAMC_N = sauria_pkg::SRAMC_W/sauria_pkg::OC_W;

// SAURIA logic config interface (smol AXI)
logic  [CFG_AXI_ADDR_WIDTH-1:0]     cfg_addr;
logic  [CFG_AXI_DATA_WIDTH-1:0]     cfg_din;
logic  [CFG_AXI_DATA_WIDTH-1:0]     cfg_wmask;
logic                               cfg_wren;
logic                               cfg_rden;
logic  [CFG_AXI_DATA_WIDTH-1:0]     cfg_dout;

// Data interface (big AXI)
logic  [DATA_AXI_ADDR_WIDTH-1:0]    dat_addr;
logic  [DATA_AXI_DATA_WIDTH-1:0]    dat_din;
logic  [DATA_AXI_DATA_WIDTH-1:0]    dat_wmask;
logic                               dat_wren;
logic                               dat_rden;
logic  [DATA_AXI_DATA_WIDTH-1:0]    dat_dout;

// Activations SRAM Interface (SRAMA)
logic [sauria_pkg::SRAMA_W-1:0]     srama_data;
logic [sauria_pkg::ADRA_W-1:0]      srama_addr;
logic                               srama_rden;

// Weights SRAM Interface (SRAMB)
logic [sauria_pkg::SRAMB_W-1:0]     sramb_data;
logic [sauria_pkg::ADRB_W-1:0]      sramb_addr;
logic                               sramb_rden;

// Outputs SRAM Interface (SRAMC)
logic [sauria_pkg::SRAMC_W-1:0]     sramc_rdata;
logic [sauria_pkg::ADRC_W-1:0]      sramc_addr;
logic                               sramc_rden;
logic                               sramc_wren;
logic [0:sauria_pkg::SRAMC_N-1]     sramc_wmask;
logic [sauria_pkg::SRAMC_W-1:0]     sramc_wdata;

// Global SRAM signals
logic [0:2]                         sram_select;
logic                               sram_deepsleep;
logic                               sram_powergate;

// ------------------------------------------------------------
// Module instantiation
// ------------------------------------------------------------

// AXI4-Lite Interface to Configuration Registers
axi_lite_2ram #(
  .AxiAddrWidth ( CFG_AXI_ADDR_WIDTH ),
  .AxiDataWidth ( CFG_AXI_DATA_WIDTH ),
  .READ_LATENCY ( 1 ),
  .PrivProtOnly ( 0 ),                    // Don't use privileged access
  .SecuProtOnly ( 0 ),                    // Don't use secure access
  .req_lite_t   ( cfg_req_lite_t     ),
  .resp_lite_t  ( cfg_resp_lite_t    )
) i_cfg_axi_lite(
  .clk_i        (i_clk),
  .rst_ni       (i_rstn),
  .axi_req_i    (cfg_axi_req),
  .axi_resp_o   (cfg_axi_resp),
  .ram_addr_o   (cfg_addr),
  .ram_din_o    (cfg_din),
  .ram_wmask_o  (cfg_wmask),
  .ram_wren_o   (cfg_wren),
  .ram_rden_o   (cfg_rden),
  .ram_dout_i   (cfg_dout)
);

// SAURIA main logic + configuration registers
sauria_logic #(
    .IF_W               (CFG_AXI_DATA_WIDTH),
    .IF_ADR_W           (CFG_AXI_ADDR_WIDTH),
    .ADRA_W             (sauria_pkg::ADRA_W),
    .SRAMA_W            (sauria_pkg::SRAMA_W),
    .ADRB_W             (sauria_pkg::ADRB_W),
    .SRAMB_W            (sauria_pkg::SRAMB_W),
    .ADRC_W             (sauria_pkg::ADRC_W),
    .SRAMC_W            (sauria_pkg::SRAMC_W),
    .SRAMC_N            (sauria_pkg::SRAMC_N)
) sauria_logic_top_i(
    .i_clk              (i_clk),
    .i_rstn             (i_rstn),

    .i_data_in          (cfg_din),
    .i_address          (cfg_addr),
    .i_wren             (cfg_wren),
    .i_rden             (cfg_rden),
    .i_wmask            (cfg_wmask),
    .o_data_out         (cfg_dout),

    .i_srama_data       (srama_data),
    .i_sramb_data       (sramb_data),
    .i_sramc_rdata      (sramc_rdata),
    .o_srama_addr       (srama_addr),
    .o_srama_rden       (srama_rden),
    .o_sramb_addr       (sramb_addr),
    .o_sramb_rden       (sramb_rden),
    .o_sramc_addr       (sramc_addr),
    .o_sramc_rden       (sramc_rden),
    .o_sramc_wren       (sramc_wren),
    .o_sramc_wmask      (sramc_wmask),
    .o_sramc_wdata      (sramc_wdata),
    .o_sram_select      (sram_select),
    .o_sram_deepsleep   (sram_deepsleep),
    .o_sram_powergate   (sram_powergate),
    .o_doneintr         (o_doneintr)
);

// AXI4 Interface to Data SRAMs
axi_full_2ram #(
  .AxiAddrWidth ( DATA_AXI_ADDR_WIDTH ),
  .AxiDataWidth ( DATA_AXI_DATA_WIDTH ),
  .AxiIdWidth   ( DATA_AXI_ID_WIDTH),
  .READ_LATENCY ( 2 ),
  .PrivProtOnly ( 0 ),                    // Don't use privileged access
  .SecuProtOnly ( 0 ),                    // Don't use secure access
  .req_t        ( dat_req_t     ),
  .resp_t       ( dat_resp_t    )
) i_data_axi_full (
  .clk_i        (i_clk),
  .rst_ni       (i_rstn),
  .axi_req_i    (dat_axi_req),
  .axi_resp_o   (dat_axi_resp),
  .ram_addr_o   (dat_addr),
  .ram_din_o    (dat_din),
  .ram_wmask_o  (dat_wmask),
  .ram_wren_o   (dat_wren),
  .ram_rden_o   (dat_rden),
  .ram_dout_i   (dat_dout)
);

// Double-buffered SRAM system (A,B,C)
sram_top #(
    .IF_W         (DATA_AXI_DATA_WIDTH),
    .IF_ADR_W     (DATA_AXI_ADDR_WIDTH),
    .ADRA_W       (sauria_pkg::ADRA_W),
    .SRAMA_W      (sauria_pkg::SRAMA_W),
    .RF_A         (sauria_pkg::RF_A),
    .ADRB_W       (sauria_pkg::ADRB_W),
    .SRAMB_W      (sauria_pkg::SRAMB_W),
    .RF_B         (sauria_pkg::RF_B),
    .ADRC_W       (sauria_pkg::ADRC_W),
    .SRAMC_W      (sauria_pkg::SRAMC_W),
    .RF_C         (sauria_pkg::RF_C),
    .SRAMC_N      (sauria_pkg::SRAMC_N)
) sram_top_i(
    .i_clk          (i_clk),
    .i_rstn         (i_rstn),

    .i_deepsleep    (sram_deepsleep),
    .i_powergate    (sram_powergate),
    .i_select       (sram_select),
    .i_data         (dat_din),
    .i_address      (dat_addr),
    .i_wren         (dat_wren),
    .i_rden         (dat_rden),
    .i_wmask        (dat_wmask),
    .o_data_out     (dat_dout),

    .i_srama_addr   (srama_addr),
    .i_srama_rden   (srama_rden),
    .o_srama_data   (srama_data),

    .i_sramb_addr   (sramb_addr),
    .i_sramb_rden   (sramb_rden),
    .o_sramb_data   (sramb_data),

    .i_sramc_data   (sramc_wdata),
    .i_sramc_addr   (sramc_addr),
    .i_sramc_wmask  (sramc_wmask),
    .i_sramc_wren   (sramc_wren),
    .i_sramc_rden   (sramc_rden),
    .o_sramc_data   (sramc_rdata)
);

endmodule 
