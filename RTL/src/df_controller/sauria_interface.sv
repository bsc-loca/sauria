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

module sauria_interface #(
    parameter N_REGS = 1
)(
    input  logic clk,
    input  logic rst,
    input  logic dma_interface_operating,
    input  logic fsm_start,
    output logic fsm_done,
    input  logic sauria_interrupt_in,
    output logic fwd_sauria_interrupt_out,
    input  logic dma_reader_interrupt_in,
    input  logic dma_writer_interrupt_in,
    output logic fwd_dma_reader_interrupt_out,
    output logic fwd_dma_writer_interrupt_out,
    AXI4Lite.master sauria_axilite,
    AXI4Lite.master dma_axilite,
    input  logic [N_REGS-1:0][31:0] control_regs
);

    localparam CONTROL_OFFSET               = 13'h0000;
    localparam INTERRUPT_EN_OFFSET          = 13'h0004;
    localparam INTERRUPT_STATUS_OFFSET      = 13'h000C;
    localparam MAIN_FSM_BASE_OFFSET         = sauria_addr_pkg::CFG_CON_OFFSET;
    localparam LFMAP_FEEDER_BASE_OFFSET     = sauria_addr_pkg::CFG_ACT_OFFSET;
    localparam WEIGHT_FEEDER_BASE_OFFSET    = sauria_addr_pkg::CFG_WEI_OFFSET;
    localparam PS_MANAGER_BASE_OFFSET       = sauria_addr_pkg::CFG_OUT_OFFSET;

    localparam N_SAURIA_CFG_WRITES = 22;

    typedef enum bit [4:0] {
        IDLE,
        READ_ARGS,
        SEND_ARGS,
        SYNC_WRESP,
        SEND_START_ADDR,
        SEND_START_DATA,
        WAIT_START_WRESP,
        WAIT_ACC_FINISH,
        SEND_CLR_INTR_ADDR,
        SEND_CLR_INTR_DATA,
        WAIT_CLR_INTR_WRESP,
        DMA_SYNC,
        WAIT_FINISHQ_WRITE
    } State_t;

    typedef enum bit [2:0] {
        MAIN_FSM,
        LFMAP_FEEDER,
        WEIGHT_FEEDER,
        PS_MANAGER,
        INTERRUPTS
    } AddrRegion;

    AddrRegion current_addr_region;
    State_t state;
    reg [31:0] start_SRAMA_addr;
    reg [31:0] start_SRAMB_addr;
    reg [31:0] start_SRAMC_addr;
    reg [1:0] loop_order;
    reg [12:0] addr;
    reg [3:0] count;
    reg [4:0] sauria_reg_idx;
    reg part_sel;
    reg addr_sent;
    reg data_sent;
    reg last_sync_1;
    reg last_sync_2;
    reg start_dma_controller;
    reg stand_alone;
    reg stand_alone_keep_A;
    reg stand_alone_keep_B;
    reg stand_alone_keep_C;

    reg [4:0] wresp_count;
    reg start_wresp_sync;
    reg wresp_sync_state;

    wire sauria_sync;
    wire dma_sync;
    wire last_iter;
    wire keep_A;
    wire keep_B;
    wire keep_C;
    reg start;

    df_ctrl_pkg::DMAParams dma_params;
    reg Cw_eq;
    reg Ch_eq;
    reg Ck_eq;

    assign sauria_axilite.arvalid = 1'b0;
    assign sauria_axilite.araddr = 32'd0;
    assign sauria_axilite.arprot = 3'd0;
    assign sauria_axilite.rready = 1'b0;
    assign sauria_axilite.awvalid = (state == SEND_ARGS && !addr_sent) || state == SEND_START_ADDR || state == SEND_CLR_INTR_ADDR;
    assign sauria_axilite.awaddr = {20'd0, addr};
    assign sauria_axilite.awprot = 3'd0;
    assign sauria_axilite.wvalid = (state == SEND_ARGS && !data_sent) || state == SEND_START_DATA || state == SEND_CLR_INTR_DATA;
    assign sauria_axilite.wstrb = 4'hF;
    assign sauria_axilite.bready = wresp_sync_state || state == WAIT_CLR_INTR_WRESP || state == WAIT_START_WRESP;

    assign fwd_sauria_interrupt_out = state == IDLE && sauria_interrupt_in;
    assign fwd_dma_reader_interrupt_out = state == IDLE && !dma_interface_operating && dma_reader_interrupt_in;
    assign fwd_dma_writer_interrupt_out = state == IDLE && !dma_interface_operating && dma_writer_interrupt_in;

    assign sauria_sync = state == DMA_SYNC;

    sauria_dma_controller sauria_dma_controller_I (
        .clk(clk),
        .rst(rst),
        .sauria_sync(sauria_sync),
        .dma_sync(dma_sync),
        .dma_reader_interrupt(dma_reader_interrupt_in),
        .dma_writer_interrupt(dma_writer_interrupt_in),
        .sauria_axilite_bvalid(sauria_axilite.bvalid),
        .start_SRAMA_addr(start_SRAMA_addr),
        .start_SRAMB_addr(start_SRAMB_addr),
        .start_SRAMC_addr(start_SRAMC_addr),
        .loop_order(loop_order),
        .Cw_eq(Cw_eq),
        .Ch_eq(Ch_eq),
        .Ck_eq(Ck_eq),
        .params(dma_params),
        .last_iter(last_iter),
        .keep_A(keep_A),
        .keep_B(keep_B),
        .keep_C(keep_C),
        .start(start_dma_controller),
        .dma_axilite(dma_axilite)
    );
    
    always_comb begin

        sauria_axilite.wdata = '0;

        case (state)

            SEND_ARGS: begin
                case (sauria_reg_idx)
                    0:   sauria_axilite.wdata = control_regs[14];
                    1:   sauria_axilite.wdata = control_regs[15];
                    2:   sauria_axilite.wdata = control_regs[16];
                    3:   sauria_axilite.wdata = control_regs[17];
                    4:   sauria_axilite.wdata = control_regs[18];
                    5:   sauria_axilite.wdata = control_regs[19];
                    6:   sauria_axilite.wdata = control_regs[20];
                    7:   sauria_axilite.wdata = control_regs[21];
                    8:   sauria_axilite.wdata = control_regs[22];
                    9:   sauria_axilite.wdata = control_regs[23];
                    10:  sauria_axilite.wdata = control_regs[24];
                    11:  sauria_axilite.wdata = control_regs[25];
                    12:  sauria_axilite.wdata = control_regs[26];
                    13:  sauria_axilite.wdata = control_regs[27];
                    14:  sauria_axilite.wdata = control_regs[28];
                    15:  sauria_axilite.wdata = control_regs[29];
                    16:  sauria_axilite.wdata = control_regs[30];
                    17:  sauria_axilite.wdata = control_regs[31];
                    18:  sauria_axilite.wdata = control_regs[32];
                    19:  sauria_axilite.wdata = control_regs[33];
                    20:  sauria_axilite.wdata = 32'h1;              // Global interrupt enable
                    21:  sauria_axilite.wdata = 32'h1;              // Done interrupt enable
                    default:  sauria_axilite.wdata = '0;
                endcase
            end

            SEND_START_DATA: begin
                sauria_axilite.wdata = 32'd0;
                sauria_axilite.wdata[0] = start;
                sauria_axilite.wdata[1] = 1'b1;
                sauria_axilite.wdata[7] = 1'b0;
                sauria_axilite.wdata[16] = 1'b1; //buffer swap
                sauria_axilite.wdata[17] = stand_alone ? stand_alone_keep_A : keep_A;
                sauria_axilite.wdata[18] = stand_alone ? stand_alone_keep_B : keep_B;
                sauria_axilite.wdata[19] = stand_alone ? stand_alone_keep_C : (!start ? 1'b0 : keep_C);
                sauria_axilite.wdata[24] = 1'b0;
                sauria_axilite.wdata[31] = 1'b0;
            end

            SEND_CLR_INTR_DATA: begin
                sauria_axilite.wdata[0] = 1'b1;
            end

        endcase
    end

    always_ff @(posedge clk) begin
        if (!wresp_sync_state) begin
            if (start_wresp_sync) begin
                wresp_count <= 5'd0;
                wresp_sync_state <= 1'b1;
            end
        end else begin
            if (sauria_axilite.bvalid) begin
                wresp_count <= wresp_count + 5'd1;
                if (wresp_count == N_SAURIA_CFG_WRITES) begin
                    wresp_sync_state <= 1'b0;
                end
            end
        end

        if (rst) begin
            wresp_sync_state <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin

        start_wresp_sync <= 1'b0;
        start_dma_controller <= 1'b0;

        dma_params.dma.psums.k_lim <= dma_params.tile.weights.k_step - 12'd1;
        dma_params.dma.psums.y_lim <= dma_params.tile.psums.y_step - {12'd0, dma_params.dma.psums.y_step};
        dma_params.dma.weights.w_lim <= dma_params.tile.weights.c_step - {12'd0, dma_params.dma.weights.w_step};

        if (Cw_eq && Ch_eq) begin
            dma_params.dma.psums.ett <= dma_params.tile.psums.k_step;
        end else if (Cw_eq) begin
            dma_params.dma.psums.ett <= dma_params.tile.psums.y_step;
        end else begin
            dma_params.dma.psums.ett <= {12'd0, dma_params.tile.psums.x_step};
        end

        if (Ck_eq) begin
            dma_params.dma.weights.ett <= dma_params.tile.weights.c_step;
        end else begin
            dma_params.dma.weights.ett <= {12'd0, dma_params.tile.weights.k_step};
        end

        case (state)

            IDLE: begin
                addr <= MAIN_FSM_BASE_OFFSET;
                current_addr_region <= MAIN_FSM;
                part_sel <= 1'b0;
                addr_sent <= 1'b0;
                data_sent <= 1'b0;
                count <= 4'd1;
                sauria_reg_idx <= '0;
                last_sync_1 <= 1'b0;
                last_sync_2 <= 1'b0;
                start <= 1'b1;
                fsm_done <= 1'b0;
                if (fsm_start) begin
                    state <= READ_ARGS;
                end
            end

            READ_ARGS: begin

                // REG 0
                dma_params.tile.x_lim                   <= control_regs[0][11:0]; //12
                dma_params.tile.y_lim                   <= control_regs[0][23:12]; //12
                dma_params.tile.c_lim[7:0]              <= control_regs[0][31:24]; //12

                // REG 1
                dma_params.tile.c_lim[11:8]             <= control_regs[1][3:0]; //12
                dma_params.tile.k_lim                   <= control_regs[1][15:4]; //12
                dma_params.tile.psums.x_step            <= control_regs[1][27:16]; //12
                dma_params.tile.psums.y_step[3:0]       <= control_regs[1][31:28]; //24

                // REG 2
                dma_params.tile.psums.y_step[23:4]      <= control_regs[2][19:0];
                dma_params.tile.psums.k_step[11:0]      <= control_regs[2][31:20]; //24

                // REG 3
                dma_params.tile.psums.k_step[23:12]     <= control_regs[3][11:0]; //24
                dma_params.tile.ifmaps.x_step           <= control_regs[3][23:12]; //12
                dma_params.tile.ifmaps.y_step[7:0]      <= control_regs[3][31:24]; //24

                // REG 4
                dma_params.tile.ifmaps.y_step[23:8]     <= control_regs[4][15:0];
                dma_params.tile.ifmaps.c_step[15:0]     <= control_regs[4][31:16]; //24

                // REG 5
                dma_params.tile.ifmaps.c_step[23:16]    <= control_regs[5][7:0]; //24
                dma_params.tile.weights.k_step          <= control_regs[5][19:8]; //12
                dma_params.tile.weights.c_step[11:0]    <= control_regs[5][31:20]; //24

                // REG 6
                dma_params.tile.weights.c_step[23:12]   <= control_regs[6][11:0];
                dma_params.dma.ifmaps.y_lim             <= control_regs[6][23:12]; //12
                dma_params.dma.ifmaps.c_lim[7:0]        <= control_regs[6][31:24]; //12

                // REG 7
                dma_params.dma.ifmaps.c_lim[11:8]       <= control_regs[7][3:0]; //12
                dma_params.dma.psums.y_step             <= control_regs[7][15:4]; //12
                dma_params.dma.psums.k_step[15:0]       <= control_regs[7][31:16]; //24

                // REG 8
                dma_params.dma.psums.k_step[23:16]      <= control_regs[8][7:0];
                dma_params.dma.ifmaps.y_step            <= control_regs[8][19:8]; //12
                dma_params.dma.ifmaps.c_step[11:0]      <= control_regs[8][31:20]; //24

                // REG 9
                dma_params.dma.ifmaps.c_step[23:12]     <= control_regs[9][11:0]; //24
                dma_params.dma.weights.w_step           <= control_regs[9][23:12]; //12
                dma_params.dma.ifmaps.ett[7:0]          <= control_regs[9][31:24]; //12

                // REG 10
                dma_params.dma.ifmaps.ett[23:8]         <= control_regs[10][15:0];
                start_SRAMA_addr[15:0]                  <= control_regs[10][31:16];

                // REG 11
                start_SRAMA_addr[31:16]                 <= control_regs[11][15:0];
                start_SRAMB_addr[15:0]                  <= control_regs[11][31:16];

                // REG 12
                start_SRAMB_addr[31:16]                 <= control_regs[12][15:0];
                start_SRAMC_addr[15:0]                  <= control_regs[12][31:16];

                // REG 13
                start_SRAMC_addr[31:16]                 <= control_regs[13][15:0];
                loop_order                              <= control_regs[13][17:16];
                stand_alone                             <= control_regs[13][18];
                stand_alone_keep_A                      <= control_regs[13][19];
                stand_alone_keep_B                      <= control_regs[13][20];
                stand_alone_keep_C                      <= control_regs[13][21];
                if (control_regs[13][18]) begin
                    start                               <= !control_regs[13][22];
                end
                Cw_eq                                   <= control_regs[13][23];
                Ch_eq                                   <= control_regs[13][24];
                Ck_eq                                   <= control_regs[13][25];
                start_wresp_sync                        <= 1'b1;

                start_dma_controller                    <= !control_regs[13][18];

                state <= SEND_ARGS;
            end

            SEND_ARGS: begin
                if ((!addr_sent && !data_sent && sauria_axilite.awready && sauria_axilite.wready) ||
                     (addr_sent && !data_sent && sauria_axilite.wready) ||
                     (!addr_sent && data_sent && sauria_axilite.awready)) begin
                    addr_sent <= 1'b0;
                    data_sent <= 1'b0;
                    part_sel <= !part_sel;
                    sauria_reg_idx <= sauria_reg_idx + 1;
                    if (count == 4'd0) begin
                        case (current_addr_region)
                            MAIN_FSM: begin
                                count <= 4'd8;
                                addr <= LFMAP_FEEDER_BASE_OFFSET;
                                current_addr_region <= LFMAP_FEEDER;
                            end
                            LFMAP_FEEDER: begin
                                count <= 4'd3;
                                addr <= WEIGHT_FEEDER_BASE_OFFSET;
                                current_addr_region <= WEIGHT_FEEDER;
                            end
                            WEIGHT_FEEDER: begin
                                count <= 4'd4;
                                addr <= PS_MANAGER_BASE_OFFSET;
                                current_addr_region <= PS_MANAGER;
                            end
                            PS_MANAGER: begin
                                count <= 4'd2;
                                addr <= INTERRUPT_EN_OFFSET;
                                current_addr_region <= INTERRUPTS;
                            end
                            INTERRUPTS: begin
                                state <= SYNC_WRESP;
                                sauria_reg_idx <= 0;
                            end
                        endcase
                    end else begin
                        addr <= addr + 12'd4;
                        count <= count - 4'd1;
                    end
                end else if (sauria_axilite.awready) begin
                    addr_sent <= 1'b1;
                end else if (sauria_axilite.wready) begin
                    data_sent <= 1'b1;
                end
            end

            SYNC_WRESP: begin
                addr <= CONTROL_OFFSET;
                if (!wresp_sync_state) begin
                    if (stand_alone) begin
                        state <= SEND_START_ADDR;
                    end else begin
                        state <= DMA_SYNC;
                    end
                end
            end

            SEND_START_ADDR: begin
                if (sauria_axilite.awready) begin
                    state <= SEND_START_DATA;
                end
            end

            SEND_START_DATA: begin
                if (sauria_axilite.wready) begin
                    state <= WAIT_START_WRESP;
                end
            end

            WAIT_START_WRESP: begin
                if (sauria_axilite.bvalid) begin
                    if (!start && stand_alone) begin
                        // write_finishq <= 1'b1;
                        state <= WAIT_FINISHQ_WRITE;
                    end else if (start) begin
                        state <= WAIT_ACC_FINISH;
                    end else begin
                        state <= DMA_SYNC;
                    end
                end
            end

            WAIT_ACC_FINISH: begin
                addr <= INTERRUPT_STATUS_OFFSET;
                if (sauria_interrupt_in) begin
                    state <= SEND_CLR_INTR_ADDR;
                end
            end

            SEND_CLR_INTR_ADDR: begin
                if (sauria_axilite.awready) begin
                    state <= SEND_CLR_INTR_DATA;
                end
            end

            SEND_CLR_INTR_DATA: begin
                if (sauria_axilite.wready) begin
                    state <= WAIT_CLR_INTR_WRESP;
                end
            end

            WAIT_CLR_INTR_WRESP: begin
                if (sauria_axilite.bvalid) begin
                    if (stand_alone) begin
                        // write_finishq <= 1'b1;
                        state <= WAIT_FINISHQ_WRITE;
                    end else begin
                        state <= DMA_SYNC;
                    end
                end
            end

            DMA_SYNC: begin
                addr <= CONTROL_OFFSET;
                if (dma_sync) begin
                   if (last_sync_2) begin
                        // write_finishq <= 1'b1;
                        state <= WAIT_FINISHQ_WRITE;
                    end else if (last_sync_1) begin
                        last_sync_2 <= 1'b1;
                        start <= 1'b0;
                        state <= SEND_START_ADDR;
                    end else begin
                        last_sync_1 <= last_iter;
                        state <= SEND_START_ADDR;
                    end
                end
            end

            WAIT_FINISHQ_WRITE: begin
                state <= IDLE;
                fsm_done <= 1'b1;
            end

        endcase

        if (rst) begin
            state <= IDLE;
        end
    end

endmodule
