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
// Jordi Fornt <jfornt@bsc.es>
//

module df_controller_top #(
    parameter AXI_LITE_DATA_WIDTH = 0,
    parameter AXI_LITE_ADDR_WIDTH = 0
)(
    input               clk,
    input               rst,
    input               sauria_interrupt_in,
    output              fwd_sauria_interrupt_out,
    input               dma_reader_interrupt_in,
    output              fwd_dma_reader_interrupt_out,
    input               dma_writer_interrupt_in,
    output              fwd_dma_writer_interrupt_out,
    AXI_LITE.Slave      cfg_slv,
    AXI_LITE.Master     sauria_mst,
    AXI_LITE.Master     dma_mst,
    output              control_interrput_out
);

    // Params and signals
    localparam N_REGS = df_ctrl_pkg::SAURIA_NARGS*2;
    localparam N_REGS_BITS = $clog2(N_REGS);

    logic start_d, start_q, start_q_prv, start_edge;
    logic ready_d, ready_q;
    logic done_d, done_q, fsm_done;
    logic ien_d, ien_q;
    logic intr_d, intr_q;

    logic [N_REGS-1:0][31:0] ctrl_regs_d, ctrl_regs_q, ctrl_regs_q2;

    logic [N_REGS_BITS-1:0]     rd_idx, wr_idx;
    logic                       rd_idx_valid, wr_idx_valid;

    // AXI response signals
    logic cfg_arready_d, cfg_awready_d, cfg_wready_d;
    logic cfg_rvalid_d, cfg_bvalid_d;
    logic [31:0]    cfg_rdata_d;
    logic [1:0]     cfg_rresp_d, cfg_bresp_d;

    // INTERNAL AXI INTERFACE
    AXI4Lite #(
        .WIDTH          (AXI_LITE_DATA_WIDTH),
        .ADDR_WIDTH     (AXI_LITE_ADDR_WIDTH)
    ) config_axilite(), sauria_axilite(), dma_axilite();
    
    // ASSIGN INTERNAL AXI TO IO AXI
    AXI4Lite_to_AXI_LITE sauria_axi_conv_i  (sauria_axilite,    sauria_mst);
    AXI4Lite_to_AXI_LITE dma_axi_conv_i     (dma_axilite,       dma_mst);
    AXI_LITE_to_AXI4Lite cfg_axi_conv_i     (cfg_slv,           config_axilite);

    sauria_interface #( 
        .N_REGS(N_REGS)
    ) sauria_interface_I
    (
        .clk(clk),
        .rst(rst),
        .dma_interface_operating('0),
        .sauria_interrupt_in(sauria_interrupt_in),
        .fwd_sauria_interrupt_out(fwd_sauria_interrupt_out),
        .dma_reader_interrupt_in(dma_reader_interrupt_in),
        .fwd_dma_reader_interrupt_out(fwd_dma_reader_interrupt_out),
        .dma_writer_interrupt_in(dma_writer_interrupt_in),
        .fwd_dma_writer_interrupt_out(fwd_dma_writer_interrupt_out),
        .sauria_axilite(sauria_axilite),
        .dma_axilite(dma_axilite),
        .control_regs(ctrl_regs_q2),
        .fsm_start(start_edge),
        .fsm_done(fsm_done)
    );

    // Start edge detection
    assign start_edge = start_q & (!start_q_prv);

    // DMA controller registers
    always_ff @(posedge clk or posedge rst) begin : registers
        if(rst) begin
            start_q         <= '0;
            start_q_prv     <= '0;
            ready_q         <= '1;
            done_q          <= '0;
            ien_q           <= '0;
            intr_q          <= '0;
            ctrl_regs_q     <= '0;
            ctrl_regs_q2    <= '0;
        end else begin
            start_q         <= start_d;
            start_q_prv     <= start_q;
            ready_q         <= ready_d;
            done_q          <= done_d;
            ien_q           <= ien_d;
            intr_q          <= intr_d;
            ctrl_regs_q     <= ctrl_regs_d;

            // Secondary registers hold the previous data and are only updated on rising edge of start
            if (start_edge & ready_q) begin
                ctrl_regs_q2 <= ctrl_regs_q;
            end
        end
    end

    // Adress decoding
    always_comb begin : addr_dec
        rd_idx = config_axilite.araddr[7:2]- (5'h10>>2);
        wr_idx = config_axilite.awaddr[7:2]- (5'h10>>2);

        rd_idx_valid = (config_axilite.araddr[7:0]>=5'h10) && (rd_idx<N_REGS);        
        wr_idx_valid = (config_axilite.awaddr[7:0]>=5'h10) && (wr_idx<N_REGS);
    end

    // Register Write logic
    always_comb begin : reg_write
        start_d         = start_q;
        ready_d         = ready_q;
        done_d          = done_q;
        ien_d           = ien_q;
        intr_d          = intr_q;
        ctrl_regs_d     = ctrl_regs_q;

        // Response defaults to zero
        cfg_awready_d =       '0;
        cfg_wready_d =      1'b0;
        cfg_bvalid_d =      1'b0;
        cfg_bresp_d =       1'b0;

        // Start is auto-deasserted
        if (start_q) begin
            start_d = 1'b0;
        end

        // Write condition
        if (config_axilite.awvalid && config_axilite.wvalid) begin

            cfg_awready_d = 1'b1;
            cfg_wready_d = 1'b1;
            cfg_bvalid_d = 1'b1;

            // Write strobe
            for (integer bb=0; bb<32; bb++) begin
                if (config_axilite.wstrb[bb/8]) begin
                    
                    // CONTROL SIGNALS      - Addr = 0x0
                    if (config_axilite.awaddr[7:2] == 0) begin

                        if (bb==0)      start_d         = config_axilite.wdata[bb];
                        if (bb==1)      done_d          = done_q & (~config_axilite.wdata[bb]);    // COW

                    end else
                    // INTERRUPT ENABLE     - Addr = 0x8
                    if (config_axilite.awaddr[7:2] == 2) begin

                        if (bb==0)      ien_d           = config_axilite.wdata[bb];

                    end else
                    // INTERRUPT STATUS     - Addr = 0xC
                    if (config_axilite.awaddr[7:2] == 3) begin

                        if (bb==0)      intr_d          = intr_q & (~config_axilite.wdata[bb]);     // COW 

                    end else 
                    // REST OF REGISTERS    - Addr = 0x10...
                    if (wr_idx_valid) begin
                        ctrl_regs_d[wr_idx][bb]         = config_axilite.wdata[bb];
                    end
                end
            end
        end 

        // Set done if HW done is raised
        if (fsm_done) begin
            done_d = 1'b1;
            intr_d = 1'b1;
            ready_d = 1'b1;
        end

        // Deassert ready when we start
        if (start_edge) begin
            ready_d = 1'b0;
        end
    end

    // Register Read logic
    always_comb begin : reg_read

        // Data defaults to "bad address 1"
        cfg_rdata_d =       32'h1BADADD2;

        // Response defaults to zero
        cfg_arready_d =     1'b0;
        cfg_rvalid_d =      1'b0;
        cfg_rresp_d =       1'b0;

        // Read condition
        if (config_axilite.arvalid) begin
                   
            cfg_arready_d =     1'b1;
            cfg_rvalid_d =      1'b1;

            // CONTROL SIGNALS      - Addr = 0x0
            if (config_axilite.araddr[7:2] == 0) begin

                cfg_rdata_d[0] = start_q;
                cfg_rdata_d[1] = done_q;
                cfg_rdata_d[23:2]  = '0;
                cfg_rdata_d[31:24] = 8'hC0;

            end else
            // INTERRUPT ENABLE     - Addr = 0x8
            if (config_axilite.araddr[7:2] == 2) begin

                cfg_rdata_d[31:1] = '0;
                cfg_rdata_d[0] = ien_q;

            end else 
            // INTERRUPT STATUS     - Addr = 0xC
            if (config_axilite.araddr[7:2] == 3) begin

                cfg_rdata_d[31:1] = '0;
                cfg_rdata_d[0] = intr_q;

            end else 
            // REST OF REGISTERS    - Addr = 0x10...
            if (rd_idx_valid) begin
                cfg_rdata_d   = ctrl_regs_q[rd_idx];
            end
        end
    end

    // AXI response spill registers
    typedef logic [1:0] bresp_t;
    spill_register #(
        .T      ( bresp_t   ),
        .Bypass ( 1'b0          )
      ) i_b_spill_register (
        .clk_i   (clk),
        .rst_ni  (!rst),
        .valid_i ( cfg_bvalid_d       ),
        .ready_o (                    ),
        .data_i  ( cfg_bresp_d        ),
        .valid_o ( config_axilite.bvalid ),
        .ready_i ( config_axilite.bready ),
        .data_o  ( config_axilite.bresp  )
      );

    typedef logic [32+2-1:0] rchan_t;
    rchan_t rchan_spill_out;
    spill_register #(
        .T      ( rchan_t ),
        .Bypass ( 1'b0          )
    ) i_r_spill_register (
        .clk_i   (clk),
        .rst_ni  (!rst),
        .valid_i ( cfg_rvalid_d       ),
        .ready_o (                    ),
        .data_i  ( {cfg_rdata_d, cfg_rresp_d} ),
        .valid_o ( config_axilite.rvalid ),
        .ready_i ( config_axilite.rready ),
        .data_o  ( rchan_spill_out       )
    );

    assign {config_axilite.rdata, config_axilite.rresp} = rchan_spill_out;

    // Ready signals connected directly
    assign config_axilite.awready   = cfg_awready_d;
    assign config_axilite.wready    = cfg_wready_d;
    assign config_axilite.arready   = cfg_arready_d;

    // Interrupt signal
    assign control_interrput_out = intr_q & ien_q;

endmodule

