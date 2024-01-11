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

module dma_top #(

    parameter CFG_AXI_DATA_WIDTH    = 32,       // Configuration AXI4-Lite Slave data width
    parameter CFG_AXI_ADDR_WIDTH    = 32,       // Configuration AXI4-Lite Slave address width

    parameter DATA_AXI_DATA_WIDTH    = 128,     // Data AXI4 Slave data width
    parameter DATA_AXI_ADDR_WIDTH    = 32,      // Data AXI4 Slave address width
    parameter DATA_AXI_ID_WIDTH      = 2,       // Data AXI4 Slave ID width

    parameter                           DMA_MAX_ARLEN    = 0,
    parameter                           DMA_MAX_AWLEN    = 0,
    parameter                           DMA_RFIFO_LEN    = 0,
    parameter                           DMA_WFIFO_LEN    = 0,
    parameter [DATA_AXI_ADDR_WIDTH-1:0] DMA_RADDR_OFFSET = 0, //offset of the DMA AXI master reader addresses, must be multiple of 4GB
    parameter [DATA_AXI_ADDR_WIDTH-1:0] DMA_WADDR_OFFSET = 0, //offset of the DNA AXI master writer addresses, must be multiple of 4GB

    parameter DATA_ELM_BITS                 = 8,       // Width of the axi data bus elements (integer multiple of 8)
    parameter DMA_SYNC_AW_W                 = 0,       // synchronize AW and W channels, adress is not valid until there is data availbale in the writer FIFO
    parameter DMA_MAX_OUTSTANDING_READS     = 2,       // Max concurrent reads
    parameter DMA_MAX_OUTSTANDING_WRITES    = 2,       // Max concurrent writes

    localparam  BYTE = 8,
    localparam  DATA_AXI_BYTE_NUM = DATA_AXI_DATA_WIDTH/BYTE,
    localparam  BYTE_CNT_BITS = $clog2(256*DATA_AXI_BYTE_NUM)
)(
    // Clk, RST
	input  logic 				                i_clk,
	input  logic					            i_rstn,

    // AXI Interfaces
    AXI_LITE.Slave                              cfg_slv,
    AXI_BUS.Master                              sauria_mst,
    AXI_BUS.Master                              mem_mst,

    // DMA Interrupt
    output logic                                o_reader_dmaintr,       // DMA reader completion interrupt
    output logic                                o_writer_dmaintr        // DMA writer completion interrupt
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

  dat_req_t   sauria_axi_req, mem_axi_req;      // Request
  dat_resp_t  sauria_axi_resp, mem_axi_resp;    // Response

  `AXI_ASSIGN_FROM_REQ(sauria_mst, sauria_axi_req)
  `AXI_ASSIGN_TO_RESP(sauria_axi_resp, sauria_mst)
  `AXI_ASSIGN_FROM_REQ(mem_mst, mem_axi_req)
  `AXI_ASSIGN_TO_RESP(mem_axi_resp, mem_mst)

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
// Signals for interconnection
// ------------------------------------------------------------

// DMA Master from fastvDMA
dat_req_t           dma_req;
dat_resp_t          dma_resp;

// Realigner modules
dat_req_t           dma_align0_req,    dma_align1_req;
dat_resp_t          dma_align0_resp,   dma_align1_resp;

localparam  N_ELEMENTS = DATA_AXI_DATA_WIDTH/DATA_ELM_BITS;
localparam  WOFFS_BITS = $clog2(N_ELEMENTS);

// Data between realigners
logic [WOFFS_BITS-1:0]  src_woffs_init_0_to_1, src_woffs_init_1_to_0;

logic [31:0]        dma_btt_reg;

// ------------------------------------------------------------
// AXI Demux selection signals
// ------------------------------------------------------------

// AXI demux works with two special signals for selection, handled externally
logic           demx_aw_sel, demx_ar_sel;
logic           demx_aw_sel_q, demx_ar_sel_q;

always_comb begin : demux_sel
    
    // Default to zero (MEMORY port)
    demx_aw_sel = demx_aw_sel_q;
    demx_ar_sel = demx_ar_sel_q;

    // Only if valid
    if (dma_req.aw_valid) begin
        // Switch to 1 if data region is selected
        if ((dma_req.aw.addr & sauria_addr_pkg::DMA_ADDR_MASK) == sauria_addr_pkg::SAURIA_DMA_OFFSET) begin
            demx_aw_sel = 1'b1;
        end else begin
            demx_aw_sel = 1'b0;
        end
    end

    // Only if valid
    if (dma_req.ar_valid) begin
        // Switch to 1 if data region is selected
        if ((dma_req.ar.addr & sauria_addr_pkg::DMA_ADDR_MASK) == sauria_addr_pkg::SAURIA_DMA_OFFSET) begin
            demx_ar_sel = 1'b1;
        end else begin
            demx_ar_sel = 1'b0;
        end
    end
end

// Register - Only accept new values if axvalid
always_ff @(posedge i_clk or negedge i_rstn) begin : demx_reg
    if(~i_rstn) begin
        demx_aw_sel_q <= 0;
        demx_ar_sel_q <= 0;
    end else begin
        demx_aw_sel_q <= demx_aw_sel;
        demx_ar_sel_q <= demx_ar_sel;
    end
end

// ------------------------------------------------------------
// Module instantiation
// ------------------------------------------------------------

udma_top #(
    .AXI_LITE_ADDR_WIDTH(32),
    .AXI_ADDR_WIDTH(DATA_AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(DATA_AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(DATA_AXI_ID_WIDTH),
    .AXI_MAX_ARLEN(DMA_MAX_ARLEN),
    .AXI_MAX_AWLEN(DMA_MAX_AWLEN),
    .READER_FIFO_LEN(DMA_RFIFO_LEN),
    .WRITER_FIFO_LEN(DMA_WFIFO_LEN),
    .AXI_READER_ADDR_OFFSET(DMA_RADDR_OFFSET), //offset of the AXI addresses, must be multiple of 4GB
    .AXI_WRITER_ADDR_OFFSET(DMA_WADDR_OFFSET), //offset of the AXI addresses, must be multiple of 4GB
    .ELM_BITS(DATA_ELM_BITS),
    .SYNC_AW_W(DMA_SYNC_AW_W),
    .MAX_OUTSTANDING_READS(DMA_MAX_OUTSTANDING_READS),
    .MAX_OUTSTANDING_WRITES(DMA_MAX_OUTSTANDING_WRITES)
) dma_i(
    .clk(i_clk),
    .rstn(i_rstn),

    .io_control_ar_arprot		(cfg_axi_req.ar.prot),
    .io_control_ar_araddr		(cfg_axi_req.ar.addr),
    .io_control_ar_arvalid		(cfg_axi_req.ar_valid),
    .io_control_ar_arready		(cfg_axi_resp.ar_ready),
    .io_control_r_rdata			(cfg_axi_resp.r.data),
    .io_control_r_rresp			(cfg_axi_resp.r.resp),
    .io_control_r_rvalid		(cfg_axi_resp.r_valid),
    .io_control_r_rready		(cfg_axi_req.r_ready),
    .io_control_aw_awprot		(cfg_axi_req.aw.prot),
    .io_control_aw_awaddr		(cfg_axi_req.aw.addr),
    .io_control_aw_awvalid		(cfg_axi_req.aw_valid),
    .io_control_aw_awready 		(cfg_axi_resp.aw_ready),
    .io_control_w_wdata			(cfg_axi_req.w.data),
    .io_control_w_wstrb			(cfg_axi_req.w.strb),
    .io_control_w_wvalid		(cfg_axi_req.w_valid),
    .io_control_w_wready		(cfg_axi_resp.w_ready),
    .io_control_b_bresp			(cfg_axi_resp.b.resp),
    .io_control_b_bvalid		(cfg_axi_resp.b_valid),
    .io_control_b_bready		(cfg_axi_req.b_ready),

    .m_axi_ar_arid				(dma_req.ar.id),
    .m_axi_ar_araddr			(dma_req.ar.addr),
    .m_axi_ar_arlen				(dma_req.ar.len),
    .m_axi_ar_arsize			(dma_req.ar.size),
    .m_axi_ar_arburst			(dma_req.ar.burst),
    .m_axi_ar_arlock			(dma_req.ar.lock),
    .m_axi_ar_arcache			(dma_req.ar.cache),
    .m_axi_ar_arprot			(dma_req.ar.prot),
    .m_axi_ar_arqos				(dma_req.ar.qos),
    .m_axi_ar_region			(dma_req.ar.region),
    .m_axi_ar_arvalid			(dma_req.ar_valid),
    .m_axi_ar_arready			(dma_resp.ar_ready),
    .m_axi_r_rid				(dma_resp.r.id),
    .m_axi_r_rdata				(dma_resp.r.data),
    .m_axi_r_rresp				(dma_resp.r.resp),
    .m_axi_r_rlast				(dma_resp.r.last),
    .m_axi_r_rvalid				(dma_resp.r_valid),
    .m_axi_r_rready				(dma_req.r_ready),
    .m_axi_aw_awid 				(dma_req.aw.id),
    .m_axi_aw_awaddr 			(dma_req.aw.addr),
    .m_axi_aw_awlen 			(dma_req.aw.len),
    .m_axi_aw_awsize			(dma_req.aw.size),
    .m_axi_aw_awburst			(dma_req.aw.burst),
    .m_axi_aw_awlock			(dma_req.aw.lock),
    .m_axi_aw_awcache			(dma_req.aw.cache),
    .m_axi_aw_awprot			(dma_req.aw.prot),
    .m_axi_aw_awqos				(dma_req.aw.qos),
    .m_axi_aw_region			(dma_req.aw.region),
    .m_axi_aw_awvalid			(dma_req.aw_valid),
    .m_axi_aw_awready			(dma_resp.aw_ready),
    .m_axi_w_wdata				(dma_req.w.data),
    .m_axi_w_wstrb				(dma_req.w.strb),
    .m_axi_w_wlast				(dma_req.w.last),
    .m_axi_w_wvalid				(dma_req.w_valid),
    .m_axi_w_wready				(dma_resp.w_ready),
    .m_axi_b_bid				(dma_resp.b.id),
    .m_axi_b_bresp				(dma_resp.b.resp),
    .m_axi_b_bvalid				(dma_resp.b_valid),
    .m_axi_b_bready				(dma_req.b_ready),
    .reader_intr                (o_reader_dmaintr),
    .writer_intr                (o_writer_dmaintr)	
);

// AXI Demux
axi_demux #(
    .AxiIdWidth     (DATA_AXI_ID_WIDTH),
    .aw_chan_t      (aw_chan_t),
    .w_chan_t       (w_chan_t),
    .b_chan_t       (b_chan_t),
    .ar_chan_t      (ar_chan_t),
    .r_chan_t       (r_chan_t),
    .axi_req_t      (dat_req_t),
    .axi_resp_t     (dat_resp_t),
    .NoMstPorts     (2),
    .MaxTrans       (8),                    // Not sure how to dimension this...
    .AxiLookBits    (DATA_AXI_ID_WIDTH),    // Not sure how to dimension this...
    .UniqueIds      (1'b1),                 // Less than or equal to ID (so set it to ID) 
    .FallThrough    (1'b0),                 
    .SpillAw        (1'b1),                 // Add spill registers before the multiplexer (+1 latency)
    .SpillW         (1'b1),
    .SpillB         (1'b1),
    .SpillAr        (1'b1),
    .SpillR         (1'b1)
) axi_demux_i (
    .clk_i              (i_clk),
    .rst_ni             (i_rstn),
    .test_i             (1'b0),

    .slv_aw_select_i    (demx_aw_sel),
    .slv_ar_select_i    (demx_ar_sel),

    .slv_req_i          (dma_req),
    .slv_resp_o         (dma_resp),

    .mst_reqs_o         ({dma_align0_req,  dma_align1_req}),
    .mst_resps_i        ({dma_align0_resp, dma_align1_resp})
);

assign sauria_axi_req = dma_align0_req;
assign dma_align0_resp = sauria_axi_resp;
assign mem_axi_req = dma_align1_req;
assign dma_align1_resp = mem_axi_resp;

endmodule