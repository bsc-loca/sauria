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

module sauria_subsystem #(
    parameter CFG_AXI_DATA_WIDTH    = 32,       // Configuration AXI4-Lite Slave data width
    parameter CFG_AXI_ADDR_WIDTH    = 32,       // Configuration AXI4-Lite Slave address width
    parameter DATA_AXI_DATA_WIDTH   = 128,      // Data AXI4 Slave data width
    parameter DATA_AXI_ADDR_WIDTH   = 32,       // Data AXI4 Slave address width
    parameter DATA_AXI_ID_WIDTH      = 2,       // Data AXI4 Slave ID width
    
    localparam  BYTE = 8,
    localparam  CFG_AXI_BYTE_NUM = CFG_AXI_DATA_WIDTH/BYTE,
    localparam  DATA_AXI_BYTE_NUM = DATA_AXI_DATA_WIDTH/BYTE
)(
    // SAURIA Clk & RST @500M
	input  logic 				                i_sauria_clk,
	input  logic					            i_sauria_rstn,

    // System Clk & RST @1500M
	input  logic 				                i_system_clk,
	input  logic					            i_system_rstn,

    // Configuration AXI4-Lite SLAVE interface
    input   logic  [CFG_AXI_ADDR_WIDTH-1:0]     i_cfg_axi_araddr,
    input   axi_pkg::prot_t                     i_cfg_axi_arprot,
    input   logic                               i_cfg_axi_arvalid,
    output  logic                               o_cfg_axi_arready,

    output  logic  [CFG_AXI_DATA_WIDTH-1:0]     o_cfg_axi_rdata,
    output  axi_pkg::resp_t                     o_cfg_axi_rresp,
    output  logic                               o_cfg_axi_rvalid,
    input   logic                               i_cfg_axi_rready,

    input   logic  [CFG_AXI_ADDR_WIDTH-1:0]     i_cfg_axi_awaddr,
    input   axi_pkg::prot_t                     i_cfg_axi_awprot,
    input   logic                               i_cfg_axi_awvalid,
    output  logic                               o_cfg_axi_awready,

    input   logic  [CFG_AXI_DATA_WIDTH-1:0]     i_cfg_axi_wdata,
    input   logic  [CFG_AXI_BYTE_NUM-1:0]       i_cfg_axi_wstrb,
    input   logic                               i_cfg_axi_wvalid,
    output  logic                               o_cfg_axi_wready,

    output  axi_pkg::resp_t                     o_cfg_axi_bresp,
    output  logic                               o_cfg_axi_bvalid,
    input   logic                               i_cfg_axi_bready,

    // Data AXI4 MASTER interface
    output  logic  [DATA_AXI_ID_WIDTH-1:0]      o_dat_axi_arid,
    output  logic  [DATA_AXI_ADDR_WIDTH-1:0]    o_dat_axi_araddr,
    output  axi_pkg::prot_t                     o_dat_axi_arprot,
    output  axi_pkg::burst_t                    o_dat_axi_arburst,
    output  axi_pkg::len_t                      o_dat_axi_arlen,
    output  logic                               o_dat_axi_arvalid,
    output  axi_pkg::size_t                     o_dat_axi_arsize,
    output  logic                               o_dat_axi_arlock,
    output  axi_pkg::cache_t                    o_dat_axi_arcache,
    output  axi_pkg::qos_t                      o_dat_axi_arqos,
    output  axi_pkg::region_t                   o_dat_axi_arregion,
    input   logic                               i_dat_axi_arready,

    input   logic  [DATA_AXI_ID_WIDTH-1:0]      i_dat_axi_rid,
    input   logic  [DATA_AXI_DATA_WIDTH-1:0]    i_dat_axi_rdata,
    input   axi_pkg::resp_t                     i_dat_axi_rresp,
    input   logic                               i_dat_axi_rvalid,
    input   logic                               i_dat_axi_rlast,
    output  logic                               o_dat_axi_rready,

    output  logic  [DATA_AXI_ID_WIDTH-1:0]      o_dat_axi_awid,
    output  logic  [DATA_AXI_ADDR_WIDTH-1:0]    o_dat_axi_awaddr,
    output  axi_pkg::prot_t                     o_dat_axi_awprot,
    output  axi_pkg::burst_t                    o_dat_axi_awburst,
    output  axi_pkg::len_t                      o_dat_axi_awlen,
    output  logic                               o_dat_axi_awvalid,
    output  axi_pkg::size_t                     o_dat_axi_awsize,
    output  logic                               o_dat_axi_awlock,
    output  axi_pkg::cache_t                    o_dat_axi_awcache,
    output  axi_pkg::qos_t                      o_dat_axi_awqos,
    output  axi_pkg::region_t                   o_dat_axi_awregion,
    input   logic                               i_dat_axi_awready,

    output  logic  [DATA_AXI_DATA_WIDTH-1:0]    o_dat_axi_wdata,
    output  logic  [DATA_AXI_BYTE_NUM-1:0]      o_dat_axi_wstrb,
    output  logic                               o_dat_axi_wlast,
    output  logic                               o_dat_axi_wvalid,
    input   logic                               i_dat_axi_wready,

    input   logic  [DATA_AXI_ID_WIDTH-1:0]      i_dat_axi_bid,
    input   axi_pkg::resp_t                     i_dat_axi_bresp,
    input   logic                               i_dat_axi_bvalid,
    output  logic                               o_dat_axi_bready,

    // Control FSM Interrupt
    output logic                                o_intr,

    // DMA Interrupt
    output logic                                o_reader_dmaintr,       // DMA reader completion interrupt
    output logic                                o_writer_dmaintr,       // DMA writer completion interrupt
    
    // SAURIA Interrupt
    output logic                                o_sauriaintr            // SAURIA core completion interrupt
);

// ------------------------------------------------------------
// Signals
// ------------------------------------------------------------

// Interrupts
logic       sauria_intr2cdc, sauria_intr2control, dma_rd_intr2control, dma_wr_intr2control;

// AXI4 Lite Interfaces
AXI_LITE #(
  .AXI_ADDR_WIDTH (CFG_AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH (CFG_AXI_DATA_WIDTH)
)   io_cfg_port(),                                                      // FROM IOs
    cfg_controller(),cfg_sauria_core(),cfg_udma(),cfg_mem_debug(),      // FROM io_cfg_port() VIA DEMUX
    ctrl_sauria_core(),ctrl_udma(),                                     // FROM DF CONTROLLER
    udma_cfg_port(),                                                    // UDMA PORT
    sauria_cfg_port_HF(),sauria_cfg_port_LF(),                          // SAURIA PORT, PRE- AND POST-CDC
    err_slv_lite(),                                                     // AXI Lite Error Slave
    cfg_demux[4:0](), core_cfg_mux[1:0](), dma_cfg_mux[1:0]();

// AXI4 Lite Interfaces (Intermediate step on Lite->Full conversion)
AXI_LITE #(
  .AXI_ADDR_WIDTH (CFG_AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH (DATA_AXI_DATA_WIDTH)
)   debug_mem_sauria_intermediate();                                    // FROM AXI DW CONVERTER

// AXI4 Interfaces (Masters)
AXI_BUS #(
  .AXI_ADDR_WIDTH (DATA_AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH (DATA_AXI_DATA_WIDTH),
  .AXI_ID_WIDTH   (DATA_AXI_ID_WIDTH),
  .AXI_USER_WIDTH (1) // Unused, but 0 can cause compilation errors
)   io_mem_port(),                                                      // TO IOs
    dma_mem_sauria(),debug_mem_sauria(),                                // TO SAURIA LOCAL MEMORIES
    core_mem_mux[1:0]();

// AXI4 Interfaces (Slaves)
AXI_BUS #(
  .AXI_ADDR_WIDTH (DATA_AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH (DATA_AXI_DATA_WIDTH),
  .AXI_ID_WIDTH   (DATA_AXI_ID_WIDTH+1),
  .AXI_USER_WIDTH (1) // Unused, but 0 can cause compilation errors
)   sauria_mem_port_HF(),sauria_mem_port_LF();                          // SAURIA PORT, PRE- AND POST-CDC

// ------------------------------------------------------------
// IO signals mapping
// ------------------------------------------------------------

// CONFIGURATION
// ^^^^^^^^^^^^^^
// AR
assign io_cfg_port.ar_addr =    i_cfg_axi_araddr;
assign io_cfg_port.ar_valid =   i_cfg_axi_arvalid;
assign o_cfg_axi_arready =      io_cfg_port.ar_ready;
assign io_cfg_port.ar_prot =    i_cfg_axi_arprot;
// AW
assign io_cfg_port.aw_addr =    i_cfg_axi_awaddr;
assign io_cfg_port.aw_valid =   i_cfg_axi_awvalid;
assign o_cfg_axi_awready =      io_cfg_port.aw_ready;
assign io_cfg_port.aw_prot =    i_cfg_axi_awprot;
// R
assign io_cfg_port.r_ready =    i_cfg_axi_rready;
assign o_cfg_axi_rdata =        io_cfg_port.r_data;
assign o_cfg_axi_rresp =        io_cfg_port.r_resp;
assign o_cfg_axi_rvalid =       io_cfg_port.r_valid;
// W
assign io_cfg_port.w_data =     i_cfg_axi_wdata;
assign io_cfg_port.w_strb =     i_cfg_axi_wstrb;
assign io_cfg_port.w_valid =    i_cfg_axi_wvalid;
assign o_cfg_axi_wready =       io_cfg_port.w_ready;
// B
assign io_cfg_port.b_ready =    i_cfg_axi_bready;
assign o_cfg_axi_bresp =        io_cfg_port.b_resp;
assign o_cfg_axi_bvalid =       io_cfg_port.b_valid;

// DATA (MASTER DRIVEN BY DMA)
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// AR
assign o_dat_axi_arid =         io_mem_port.ar_id;
assign o_dat_axi_araddr =       io_mem_port.ar_addr;
assign o_dat_axi_arlen =        io_mem_port.ar_len;
assign o_dat_axi_arburst =      io_mem_port.ar_burst;
assign o_dat_axi_arvalid =      io_mem_port.ar_valid;
assign io_mem_port.ar_ready =   i_dat_axi_arready;
assign o_dat_axi_arprot =       io_mem_port.ar_prot;
assign o_dat_axi_arsize =       io_mem_port.ar_size;
assign o_dat_axi_arlock =       io_mem_port.ar_lock;
assign o_dat_axi_arcache =      io_mem_port.ar_cache;
assign o_dat_axi_arqos =        io_mem_port.ar_qos;
assign o_dat_axi_arregion =     io_mem_port.ar_region;
// AW
assign o_dat_axi_awid =         io_mem_port.aw_id;
assign o_dat_axi_awaddr =       io_mem_port.aw_addr;
assign o_dat_axi_awlen =        io_mem_port.aw_len;
assign o_dat_axi_awburst =      io_mem_port.aw_burst;
assign o_dat_axi_awvalid =      io_mem_port.aw_valid;
assign io_mem_port.aw_ready =   i_dat_axi_awready;
assign o_dat_axi_awprot =       io_mem_port.aw_prot;
assign o_dat_axi_awsize =       io_mem_port.aw_size;
assign o_dat_axi_awlock =       io_mem_port.aw_lock;
assign o_dat_axi_awcache =      io_mem_port.aw_cache;
assign o_dat_axi_awqos =        io_mem_port.aw_qos;
assign o_dat_axi_awregion =     io_mem_port.aw_region;
// R
assign o_dat_axi_rready =       io_mem_port.r_ready;
assign io_mem_port.r_id =       i_dat_axi_rid;
assign io_mem_port.r_data =     i_dat_axi_rdata;
assign io_mem_port.r_resp =     i_dat_axi_rresp;
assign io_mem_port.r_last =     i_dat_axi_rlast;
assign io_mem_port.r_valid =    i_dat_axi_rvalid;
// W
assign o_dat_axi_wdata =        io_mem_port.w_data;
assign o_dat_axi_wstrb =        io_mem_port.w_strb;
assign o_dat_axi_wlast =        io_mem_port.w_last;
assign o_dat_axi_wvalid =       io_mem_port.w_valid;
assign io_mem_port.w_ready =    i_dat_axi_wready;
// B
assign o_dat_axi_bready =       io_mem_port.b_ready;
assign io_mem_port.b_id =       i_dat_axi_bid;
assign io_mem_port.b_resp =     i_dat_axi_bresp;
assign io_mem_port.b_valid =    i_dat_axi_bvalid;

// ------------------------------------------------------------
// AXI LITE Network
// ------------------------------------------------------------

// Configuration IO Port Demux
logic [2:0] lite_demx_aw_sel, lite_demx_ar_sel;

axi_lite_demux_intf #(
    .AxiAddrWidth   (CFG_AXI_ADDR_WIDTH),
    .AxiDataWidth   (CFG_AXI_DATA_WIDTH),
    .NoMstPorts     (5),
    .MaxTrans       (8),
    .SpillAw        (1'b1),     // Add spill registers (+1 latency)
    .SpillW         (1'b1),
    .SpillB         (1'b1),
    .SpillAr        (1'b1),
    .SpillR         (1'b1)
) config_demux_i (
    .clk_i              (i_system_clk),
    .rst_ni             (i_system_rstn),
    .test_i             (1'b0),
    .slv_aw_select_i    (lite_demx_aw_sel),
    .slv_ar_select_i    (lite_demx_ar_sel),
    .slv                (io_cfg_port),
    .mst                (cfg_demux)
);

`AXI_LITE_ASSIGN(cfg_controller,    cfg_demux[0])
`AXI_LITE_ASSIGN(cfg_udma,          cfg_demux[1])
`AXI_LITE_ASSIGN(cfg_sauria_core,   cfg_demux[2]) 
`AXI_LITE_ASSIGN(cfg_mem_debug,     cfg_demux[3])
`AXI_LITE_ASSIGN(err_slv_lite,      cfg_demux[4]) 

// Demux Control
always_comb begin : demux_sel
    
    // Default to zero (DF Controller)
    lite_demx_aw_sel = 3'd4;
    lite_demx_ar_sel = 3'd4;

    // AW - Controller region
    if      ((io_cfg_port.aw_addr & sauria_addr_pkg::AXI_CONTROLLER_ADDR_MASK) == sauria_addr_pkg::CONTROLLER_OFFSET)
        lite_demx_aw_sel = 3'd0;
    // AW - DMA region
    else if ((io_cfg_port.aw_addr & sauria_addr_pkg::AXI_DMA_ADDR_MASK) == sauria_addr_pkg::DMA_OFFSET)
        lite_demx_aw_sel = 3'd1;
    // AW - SAURIA region
    else if ((io_cfg_port.aw_addr & sauria_addr_pkg::AXI_SAURIA_ADDR_MASK) == sauria_addr_pkg::SAURIA_OFFSET) begin
        
        // SAURIA Core Config
        if ((io_cfg_port.aw_addr & sauria_addr_pkg::SAURIA_MEM_ADDR_MASK) == 0)
            lite_demx_aw_sel = 3'd2;
        // SAURIA Memory Debug access
        else
            lite_demx_aw_sel = 3'd3;
    end

    // AR - Controller region
    if      ((io_cfg_port.ar_addr & sauria_addr_pkg::AXI_CONTROLLER_ADDR_MASK) == sauria_addr_pkg::CONTROLLER_OFFSET)
        lite_demx_ar_sel = 3'd0;
    // AR - DMA region
    else if ((io_cfg_port.ar_addr & sauria_addr_pkg::AXI_DMA_ADDR_MASK) == sauria_addr_pkg::DMA_OFFSET)
        lite_demx_ar_sel = 3'd1;
    // AR - SAURIA region
    else if ((io_cfg_port.ar_addr & sauria_addr_pkg::AXI_SAURIA_ADDR_MASK) == sauria_addr_pkg::SAURIA_OFFSET) begin
        
        // SAURIA Core Config
        if ((io_cfg_port.ar_addr & sauria_addr_pkg::SAURIA_MEM_ADDR_MASK) == 0)
            lite_demx_ar_sel = 3'd2;
        // SAURIA Memory Debug access
        else
            lite_demx_ar_sel = 3'd3;
    end
end

// Error slave to catch unmapped addresses
axi_lite_err_slv_intf #(
    .AxiDataWidth (CFG_AXI_DATA_WIDTH),
    .ReadDataWord (32'h0BADADD2)
) err_slv_i (
    .clk    (i_system_clk),
    .rstn   (i_system_rstn),
    .slv    (err_slv_lite)
);

// SAURIA config port Mux
axi_lite_mux_intf #(
    .AxiAddrWidth   (CFG_AXI_ADDR_WIDTH),
    .AxiDataWidth   (CFG_AXI_DATA_WIDTH),
    .NoSlvPorts     (2),
    .MaxTrans       (8),
    .SpillAw        (1'b1),     // Add spill registers (+1 latency)
    .SpillW         (1'b1),
    .SpillB         (1'b1),
    .SpillAr        (1'b1),
    .SpillR         (1'b1)
) core_cfg_mux_i (
    .clk_i              (i_system_clk),
    .rst_ni             (i_system_rstn),
    .test_i             (1'b0),
    .slv                (core_cfg_mux),
    .mst                (sauria_cfg_port_HF)
);

`AXI_LITE_ASSIGN(core_cfg_mux[0],   cfg_sauria_core)
`AXI_LITE_ASSIGN(core_cfg_mux[1],   ctrl_sauria_core)

// DMA config port Mux
axi_lite_mux_intf #(
    .AxiAddrWidth   (CFG_AXI_ADDR_WIDTH),
    .AxiDataWidth   (CFG_AXI_DATA_WIDTH),
    .NoSlvPorts     (2),
    .MaxTrans       (8),
    .SpillAw        (1'b1),     // Add spill registers (+1 latency)
    .SpillW         (1'b1),
    .SpillB         (1'b1),
    .SpillAr        (1'b1),
    .SpillR         (1'b1)
) dma_cfg_mux_i (
    .clk_i              (i_system_clk),
    .rst_ni             (i_system_rstn),
    .test_i             (1'b0),
    .slv                (dma_cfg_mux),
    .mst                (udma_cfg_port)
);

`AXI_LITE_ASSIGN(dma_cfg_mux[0],   cfg_udma)
`AXI_LITE_ASSIGN(dma_cfg_mux[1],   ctrl_udma)

// Data witdh upsizer to connect debug path to memories
axi_lite_dw_converter_intf #(
    .AXI_SLV_PORT_DATA_WIDTH    (CFG_AXI_DATA_WIDTH),
    .AXI_MST_PORT_DATA_WIDTH    (DATA_AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH             (CFG_AXI_ADDR_WIDTH)
) debug_axi_upsize_i (
    .clk_i              (i_system_clk),
    .rst_ni             (i_system_rstn),
    .slv                (cfg_mem_debug),
    .mst                (debug_mem_sauria_intermediate)
);

// AXI Lite to AXI Full converter
axi_lite_to_axi_intf #(
    .AXI_DATA_WIDTH (DATA_AXI_DATA_WIDTH)
) axi_lite_to_axi_i (
    .slv_aw_cache_i     ('0),
    .slv_ar_cache_i     ('0),
    .in                 (debug_mem_sauria_intermediate),
    .out                (debug_mem_sauria)
);

// ------------------------------------------------------------
// AXI (FULL) Network
// ------------------------------------------------------------

// SAURIA memory port Mux
axi_mux_intf #(
    .SLV_AXI_ID_WIDTH   (DATA_AXI_ID_WIDTH),
    .MST_AXI_ID_WIDTH   (DATA_AXI_ID_WIDTH+1),
    .AXI_ADDR_WIDTH     (DATA_AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH     (DATA_AXI_DATA_WIDTH),
    .AXI_USER_WIDTH     (1),            // Unused, but 0 can cause compilation errors
    .NO_SLV_PORTS       (2),
    .MAX_W_TRANS        (8),
    .SPILL_AW           (1'b1),         // Add spill registers => +1 latency
    .SPILL_W            (1'b1),
    .SPILL_B            (1'b1),
    .SPILL_AR           (1'b1),
    .SPILL_R            (1'b1)
) core_mem_mux_i (
    .clk_i              (i_system_clk),
    .rst_ni             (i_system_rstn),
    .test_i             (1'b0),
    .slv                (core_mem_mux),
    .mst                (sauria_mem_port_HF)
);

`AXI_ASSIGN(core_mem_mux[0],   dma_mem_sauria)
`AXI_ASSIGN(core_mem_mux[1],   debug_mem_sauria)

// ------------------------------------------------------------
// CLOCK DOMAIN CROSSINGS (CDCs)
// ------------------------------------------------------------

// CDC for SAURIA interrupt signal
cdc_sync_reg #(
    .STAGES(3)
) cdc_intr_i (
    .i_dst_clk      (i_system_clk),
    .i_dst_rstn     (i_system_rstn),
    .i_signal       (sauria_intr2cdc),
    .o_signal       (sauria_intr2control)
);

// CDC for SAURIA Config port
axi_lite_cdc_intf #(
    .LOG_DEPTH      (sauria_pkg::CFG_CDC_FIFO_BITS),
    .AXI_ADDR_WIDTH (CFG_AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (CFG_AXI_DATA_WIDTH)
) cdc_cfg_i (
    .src_clk_i      (i_system_clk),
    .src_rst_ni     (i_system_rstn),
    .src            (sauria_cfg_port_HF),

    .dst_clk_i      (i_sauria_clk),
    .dst_rst_ni     (i_sauria_rstn),
    .dst            (sauria_cfg_port_LF)
);

// CDC for SAURIA Memory port
axi_cdc_intf #(
    .LOG_DEPTH      (sauria_pkg::DATA_CDC_FIFO_BITS),
    .AXI_ADDR_WIDTH (DATA_AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (DATA_AXI_DATA_WIDTH),
    .AXI_ID_WIDTH   (DATA_AXI_ID_WIDTH+1),
    .AXI_USER_WIDTH (1) // Unused, but 0 can cause compilation errors
) cdc_mem_i (
    .src_clk_i      (i_system_clk),
    .src_rst_ni     (i_system_rstn),
    .src            (sauria_mem_port_HF),

    .dst_clk_i      (i_sauria_clk),
    .dst_rst_ni     (i_sauria_rstn),
    .dst            (sauria_mem_port_LF)
);

// ------------------------------------------------------------
// Module instantiation
// ------------------------------------------------------------

// Dataflow Controller
df_controller_top #(
    .AXI_LITE_DATA_WIDTH            (CFG_AXI_DATA_WIDTH),
    .AXI_LITE_ADDR_WIDTH            (CFG_AXI_ADDR_WIDTH)
) df_controller_i (
    .clk                            (i_system_clk),
    .rst                            (!i_system_rstn),

    .cfg_slv                        (cfg_controller),
    .sauria_mst                     (ctrl_sauria_core),
    .dma_mst                        (ctrl_udma),

    .sauria_interrupt_in            (sauria_intr2control),
    .fwd_sauria_interrupt_out       (o_sauriaintr),
    .dma_reader_interrupt_in        (dma_rd_intr2control),
    .fwd_dma_reader_interrupt_out   (o_reader_dmaintr),
    .dma_writer_interrupt_in        (dma_wr_intr2control),
    .fwd_dma_writer_interrupt_out   (o_writer_dmaintr),
    .control_interrput_out          (o_intr)
);

// uDMA
dma_top #(
    .CFG_AXI_DATA_WIDTH         (CFG_AXI_DATA_WIDTH),
    .CFG_AXI_ADDR_WIDTH         (CFG_AXI_ADDR_WIDTH),
    .DATA_AXI_DATA_WIDTH        (DATA_AXI_DATA_WIDTH),
    .DATA_AXI_ADDR_WIDTH        (DATA_AXI_ADDR_WIDTH),
    .DATA_AXI_ID_WIDTH          (DATA_AXI_ID_WIDTH),
    .DMA_MAX_ARLEN              (sauria_pkg::DMA_MAX_ARLEN),
    .DMA_MAX_AWLEN              (sauria_pkg::DMA_MAX_AWLEN),
    .DMA_RFIFO_LEN              (sauria_pkg::DMA_RFIFO_LEN),
    .DMA_WFIFO_LEN              (sauria_pkg::DMA_WFIFO_LEN),
    .DMA_RADDR_OFFSET           (sauria_pkg::DMA_RADDR_OFFSET),
    .DMA_WADDR_OFFSET           (sauria_pkg::DMA_WADDR_OFFSET),
    .DATA_ELM_BITS              (sauria_pkg::DATA_ELM_BITS),
    .DMA_SYNC_AW_W              (sauria_pkg::DMA_SYNC_AW_W),
    .DMA_MAX_OUTSTANDING_READS  (sauria_pkg::DMA_MAX_OUTSTANDING_READS),
    .DMA_MAX_OUTSTANDING_WRITES (sauria_pkg::DMA_MAX_OUTSTANDING_WRITES)
) dma_top_i (
    .i_clk              (i_system_clk),
    .i_rstn             (i_system_rstn),

    .cfg_slv            (udma_cfg_port),
    .sauria_mst         (dma_mem_sauria),
    .mem_mst            (io_mem_port),

    .o_reader_dmaintr   (dma_rd_intr2control),
    .o_writer_dmaintr   (dma_wr_intr2control)
);

// SAURIA Core
sauria_core #(
    .CFG_AXI_DATA_WIDTH             (CFG_AXI_DATA_WIDTH),
    .CFG_AXI_ADDR_WIDTH             (CFG_AXI_ADDR_WIDTH),
    .DATA_AXI_DATA_WIDTH            (DATA_AXI_DATA_WIDTH),
    .DATA_AXI_ADDR_WIDTH            (DATA_AXI_ADDR_WIDTH),
    .DATA_AXI_ID_WIDTH              (DATA_AXI_ID_WIDTH+1)
) sauria_core_i(
    .i_clk      (i_sauria_clk),
    .i_rstn     (i_sauria_rstn),

    .cfg_slv    (sauria_cfg_port_LF),
    .mem_slv    (sauria_mem_port_LF),

    .o_doneintr (sauria_intr2cdc)
);

endmodule 
