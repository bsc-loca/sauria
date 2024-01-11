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
//

module sauria_dma_controller (
    input clk,
    input rst,
    input sauria_sync,
    output dma_sync,
    input dma_reader_interrupt,
    input dma_writer_interrupt,
    input sauria_axilite_bvalid,
    input [31:0] start_SRAMA_addr,
    input [31:0] start_SRAMB_addr,
    input [31:0] start_SRAMC_addr,
    input df_ctrl_pkg::DMAParams params,
    input [1:0] loop_order,
    input Cw_eq,
    input Ch_eq,
    input Ck_eq,
    output keep_A,
    output keep_B,
    output keep_C,
    input start,
    output last_iter,
    AXI4Lite.master dma_axilite
);

    localparam CONTROL_OFFSET = 6'h00;
    localparam INTERRUPT_MASK_REGISTER_OFFSET = 6'h04;
    localparam INTERRUPT_STATUS_REGISTER_OFFSET = 6'h0C;
    localparam READER_START_ADDR_OFFSET = 6'h10;
    localparam WRITER_START_ADDR_OFFSET = 6'h20;
    localparam BTT_OFFSET = 6'h30;

    localparam SRAMA_OFFSET = sauria_addr_pkg::SAURIA_DMA_OFFSET+sauria_addr_pkg::SRAMA_OFFSET;
    localparam SRAMB_OFFSET = sauria_addr_pkg::SAURIA_DMA_OFFSET+sauria_addr_pkg::SRAMB_OFFSET;
    localparam SRAMC_OFFSET = sauria_addr_pkg::SAURIA_DMA_OFFSET+sauria_addr_pkg::SRAMC_OFFSET;

    typedef enum bit [3:0] {
        IDLE,
        SEND_CMD,
        SYNC_WRESP,
        WAIT_DMA_INTR_READER,
        WAIT_DMA_INTR_WRITER,
        SEND_START_ADDR,
        SEND_START_DATA,
        WAIT_START_WRESP,
        SEND_CLR_INTR_ADDR,
        SEND_CLR_INTR_DATA,
        WAIT_CLR_INTR_WRESP,
        WRESP_SYNC,
        SAURIA_SYNC,
        CHECK_NEXT_ACTION,
        COPY_OPT
    } State_t;

    typedef enum bit [1:0] {
        DMA_BRING_A,
        DMA_BRING_B,
        DMA_BRING_C,
        DMA_SEND_C
    } SubState_t;

    typedef enum bit [1:0] {
        GOTO_IDLE,
        GOTO_SYNC_WRESP,
        GOTO_SYNC_SAURIA
    } NextAction_t;

    State_t state;
    SubState_t sub_state;
    NextAction_t next_action;

    //Vivado synthesis detects this as an FSM and changes the encoding
    (* DONT_TOUCH = "true" *) reg [5:0] addr;
    reg [31:0] SRAMA_addr;
    reg [31:0] SRAMB_addr;
    reg [31:0] SRAMC_addr;
    reg [14:0] local_SRAM_addr; //32KB SRAM
    reg first_tile;
    reg first_dma_iter;
    reg goto_sync_sauria;
    reg last_iter_1;
    reg last_iter_2;

    reg [3:0] wresp_counter;
    reg start_wresp_sync;
    reg wresp_sync_state;

    reg [31:0] wdata;

    reg addr_sent;
    reg data_sent;

    reg [23:0] ett;
    wire [24:0] btt;
    reg [23:0] ystep;
    reg [23:0] zstep;
    reg [23:0] ycounter;
    reg [23:0] zcounter;
    reg [23:0] y;
    reg [23:0] z;
    reg [23:0] ylim;
    reg [23:0] zlim;
    reg [23:0] y_incr;
    reg [23:0] z_incr;

    reg advance;
    wire [23:0] ifmap_xcounter;
    wire [23:0] ifmap_ycounter;
    wire [23:0] ifmap_ccounter;
    wire [23:0] psums_xcounter;
    wire [23:0] psums_ycounter;
    wire [23:0] psums_kcounter;
    wire [23:0] weights_kcounter;
    wire [23:0] weights_ccounter;
    wire last_iter_sig;
    reg last_iter_reg;
    wire single_tile;
    wire ifmaps_change;
    wire weights_change;
    wire psums_change;
    reg last_psums_change;
    reg last_ifmaps_change;
    reg last_weights_change;

    reg [24:0] SRAMA_tile_offset;
    reg [24:0] SRAMB_tile_offset;
    reg [24:0] SRAMC_tile_offset;
    reg [24:0] tmp_SRAMC_tile_offset;
    reg [24:0] send_SRAMC_tile_offset;

    assign dma_axilite.arvalid = 1'b0;
    assign dma_axilite.araddr = 32'd0;
    assign dma_axilite.arprot = 3'd0;
    assign dma_axilite.rready = 1'b0;
    assign dma_axilite.awvalid = (state == SEND_CMD && !addr_sent) || state == SEND_CLR_INTR_ADDR || state == SEND_START_ADDR;
    assign dma_axilite.awaddr = {26'd0, addr};
    assign dma_axilite.awprot = 3'd0;
    assign dma_axilite.wvalid = (state == SEND_CMD && !data_sent) || state == SEND_CLR_INTR_DATA || state == SEND_START_DATA;
    assign dma_axilite.wdata = wdata;
    assign dma_axilite.wstrb = 4'hF;
    assign dma_axilite.bready = wresp_sync_state || state == WAIT_CLR_INTR_WRESP || state == WAIT_START_WRESP;

    assign dma_sync = state == SAURIA_SYNC;

    assign single_tile = first_tile && last_iter_reg;

    assign last_iter = last_iter_reg;

    assign keep_A = !last_ifmaps_change;
    assign keep_B = !last_weights_change;
    assign keep_C = !last_psums_change;

    assign btt =    (sub_state == DMA_BRING_A)?     df_ctrl_pkg::A_BYTES*ett :
                    (sub_state == DMA_BRING_B)?     df_ctrl_pkg::B_BYTES*ett :
                                                    df_ctrl_pkg::C_BYTES*ett;

    function void set_A_params();
        y_incr <= 24'd1;
        z_incr <= 24'd1;
        ylim <= params.dma.ifmaps.y_lim;
        zlim <= params.dma.ifmaps.c_lim;
        ett <= params.dma.ifmaps.ett;
        ystep <= params.dma.ifmaps.y_step;
        zstep <= params.dma.ifmaps.c_step;
    endfunction

    function void set_B_params();
        y_incr <= params.dma.weights.w_step;
        ylim <= Ck_eq ? 24'd0 : params.dma.weights.w_lim;
        zlim <= 24'd0;
        ett <= params.dma.weights.ett;
        ystep <= params.dma.weights.w_step;
    endfunction

    function void set_C_params();
        y_incr <= params.dma.psums.y_step;
        z_incr <= 24'd1;
        ylim <= Cw_eq ? 24'd0 : params.dma.psums.y_lim;
        zlim <= Cw_eq && Ch_eq ? 24'd0 : params.dma.psums.k_lim;
        ett <= params.dma.psums.ett;
        ystep <= params.dma.psums.y_step;
        zstep <= params.dma.psums.k_step;
    endfunction

    sauria_dma_pointer_generator sauria_dma_pointer_generator_I (
        .clk(clk),
        .rst(state == IDLE),
        .advance(advance),
        .p(params.tile),
        .loop_order(loop_order),
        .ifmap_xcounter(ifmap_xcounter),
        .ifmap_ycounter(ifmap_ycounter),
        .ifmap_ccounter(ifmap_ccounter),
        .psums_xcounter(psums_xcounter),
        .psums_ycounter(psums_ycounter),
        .psums_kcounter(psums_kcounter),
        .weights_ccounter(weights_ccounter),
        .weights_kcounter(weights_kcounter),
        .ifmaps_change(ifmaps_change),
        .weights_change(weights_change),
        .psums_change(psums_change),
        .last_iter(last_iter_sig)
    );

    always_ff @(posedge clk) begin
        if (!wresp_sync_state) begin
            if (start_wresp_sync) begin
                wresp_counter <= 4'd0;
                wresp_sync_state <= 1'b1;
            end
        end else begin
            if (dma_axilite.bvalid) begin
                wresp_counter <= wresp_counter + 4'd1;
                if (wresp_counter == 4'd3) begin
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
        advance <= 1'b0;
        last_iter_reg <= last_iter_sig;

        SRAMA_tile_offset <= (ifmap_xcounter*df_ctrl_pkg::A_BYTES) + (ifmap_ycounter*df_ctrl_pkg::A_BYTES) + (ifmap_ccounter*df_ctrl_pkg::A_BYTES);
        SRAMB_tile_offset <= (weights_kcounter*df_ctrl_pkg::B_BYTES) + (weights_ccounter*df_ctrl_pkg::B_BYTES);
        if (sub_state == DMA_SEND_C) begin
            SRAMC_tile_offset <= send_SRAMC_tile_offset;
        end else begin
            SRAMC_tile_offset <= (psums_xcounter*df_ctrl_pkg::C_BYTES) + (psums_ycounter*df_ctrl_pkg::C_BYTES) + (psums_kcounter*df_ctrl_pkg::C_BYTES);
        end
        SRAMA_addr <= start_SRAMA_addr + (ycounter*df_ctrl_pkg::A_BYTES) + (zcounter*df_ctrl_pkg::A_BYTES);
        SRAMB_addr <= start_SRAMB_addr + (ycounter*df_ctrl_pkg::B_BYTES);
        SRAMC_addr <= start_SRAMC_addr + (ycounter*df_ctrl_pkg::C_BYTES) + (zcounter*df_ctrl_pkg::C_BYTES);

        case (state)

            IDLE: begin
                local_SRAM_addr <= 15'd0;
                ycounter <= 24'd0;
                zcounter <= 24'd0;
                y <= 24'd0;
                z <= 24'd0;
                set_A_params();
                addr <= INTERRUPT_MASK_REGISTER_OFFSET;
                wdata[0] <= 1'b1; //writer interrupt enable
                wdata[1] <= 1'b1; //reader interrupt enable
                addr_sent <= 1'b0;
                data_sent <= 1'b0;
                last_iter_1 <= 1'b0;
                last_iter_2 <= 1'b0;
                first_tile <= 1'b1;
                first_dma_iter <= 1'b1;
                sub_state <= DMA_BRING_A;
                goto_sync_sauria <= 1'b0;
                if (start) begin
                    start_wresp_sync <= 1'b1;
                    state <= SEND_CMD;
                end
            end

            SEND_CMD: begin
                if ((!addr_sent && !data_sent && dma_axilite.awready && dma_axilite.wready) ||
                     (addr_sent && !data_sent && dma_axilite.wready) ||
                     (!addr_sent && data_sent && dma_axilite.awready)) begin
                    addr_sent <= 1'b0;
                    data_sent <= 1'b0;
                    case (addr)
                        INTERRUPT_MASK_REGISTER_OFFSET: begin
                            wdata <= {7'd0, btt};
                            addr <= BTT_OFFSET;
                        end
                        BTT_OFFSET: begin
                            case (sub_state)
                                DMA_BRING_A: begin
                                    wdata <= SRAMA_tile_offset + SRAMA_addr;
                                end
                                DMA_BRING_B: begin
                                    wdata <= SRAMB_tile_offset + SRAMB_addr;
                                end
                                DMA_BRING_C: begin
                                    wdata <= SRAMC_tile_offset + SRAMC_addr;
                                end
                                DMA_SEND_C: begin
                                    wdata <= SRAMC_OFFSET + {15'd0, local_SRAM_addr};
                                end
                            endcase
                            addr <= READER_START_ADDR_OFFSET;
                        end
                        READER_START_ADDR_OFFSET: begin
                            case (sub_state)
                                DMA_BRING_A: begin
                                    wdata <= SRAMA_OFFSET + {15'd0, local_SRAM_addr};
                                end
                                DMA_BRING_B: begin
                                    wdata <= SRAMB_OFFSET + {15'd0, local_SRAM_addr};
                                end
                                DMA_BRING_C: begin
                                    wdata <= SRAMC_OFFSET + {15'd0, local_SRAM_addr};
                                end
                                DMA_SEND_C: begin
                                    wdata <= SRAMC_tile_offset + SRAMC_addr;
                                end
                            endcase
                            addr <= WRITER_START_ADDR_OFFSET;
                        end
                        WRITER_START_ADDR_OFFSET: begin
                            addr <= CONTROL_OFFSET;
                            wdata[0] <= 1'b1; //start reader
                            wdata[1] <= 1'b1; //start writer
                            wdata[8] <= 1'b0; //write zero mode
                            state <= SYNC_WRESP;
                        end
                        default: begin
                        end
                    endcase
                end else if (dma_axilite.awready) begin
                    addr_sent <= 1'b1;
                end else if (dma_axilite.wready) begin
                    data_sent <= 1'b1;
                end
            end

            SYNC_WRESP: begin
                if (!wresp_sync_state) begin
                    if (first_dma_iter) begin
                        state <= SEND_START_ADDR;
                    end else begin
                        state <= WAIT_DMA_INTR_READER;
                    end
                end
            end

            SEND_START_ADDR: begin
                if (dma_axilite.awready) begin
                    state <= SEND_START_DATA;
                end
            end

            SEND_START_DATA: begin
                if (dma_axilite.wready) begin
                    state <= WAIT_START_WRESP;
                end
            end

            WAIT_START_WRESP: begin
                if (dma_axilite.bvalid) begin
                    if (wdata[1] == 1'b1) begin //start writer
                        state <= CHECK_NEXT_ACTION;
                    end else begin
                        state <= WAIT_DMA_INTR_WRITER;
                    end
                end
            end

            WAIT_DMA_INTR_READER: begin
                addr <= INTERRUPT_STATUS_REGISTER_OFFSET;
                wdata[0] <= 1'b1; //start reader / clear reader interrupt
                wdata[1] <= 1'b0; //start writer / clear writer interrupt
                wdata[8] <= 1'b0; //write zero mode
                if (dma_reader_interrupt) begin
                    if (goto_sync_sauria) begin
                        state <= WAIT_DMA_INTR_WRITER;
                    end else begin
                        state <= SEND_CLR_INTR_ADDR;
                    end
                end
            end

            WAIT_DMA_INTR_WRITER: begin
                addr <= INTERRUPT_STATUS_REGISTER_OFFSET;
                wdata[0] <= goto_sync_sauria; //start reader / clear reader interrupt
                wdata[1] <= 1'b1; //start writer / clear writer interrupt
                wdata[8] <= 1'b0; //write zero mode
                if (dma_writer_interrupt) begin
                    state <= SEND_CLR_INTR_ADDR;
                end
            end

            SEND_CLR_INTR_ADDR: begin
                if (dma_axilite.awready) begin
                    state <= SEND_CLR_INTR_DATA;
                end
            end

            SEND_CLR_INTR_DATA: begin
                if (dma_axilite.wready) begin
                    state <= WAIT_CLR_INTR_WRESP;
                end
            end

            WAIT_CLR_INTR_WRESP: begin
                addr <= CONTROL_OFFSET;
                if (dma_axilite.bvalid) begin
                    if (goto_sync_sauria) begin
                        state <= SAURIA_SYNC;
                    end else begin
                        state <= SEND_START_ADDR;
                    end
                end
            end

            CHECK_NEXT_ACTION: begin
                first_dma_iter <= 1'b0;
                wdata[0] <= 1'b1; //reader interrupt enable
                wdata[1] <= 1'b1; //writer interrupt enable
                addr <= INTERRUPT_MASK_REGISTER_OFFSET;
                local_SRAM_addr <= local_SRAM_addr + btt;
                if (y == ylim) begin
                    ycounter <= 24'd0;
                    y <= 24'd0;
                    if (z == zlim) begin
                        last_iter_1 <= last_iter_reg;
                        local_SRAM_addr <= 15'd0;
                        zcounter <= 24'd0;
                        z <= 24'd0;
                    end else begin
                        zcounter <= zcounter + zstep;
                        z <= z + z_incr;
                    end
                end else begin
                    ycounter <= ycounter + ystep;
                    y <= y + y_incr;
                end
                case (sub_state)
                    DMA_BRING_A: begin
                        start_wresp_sync <= 1'b1;
                        if (y == ylim && z == zlim) begin
                            if (weights_change) begin
                                set_B_params();
                                sub_state <= DMA_BRING_B;
                            end else begin
                                set_C_params();
                                sub_state <= DMA_BRING_C;
                            end
                        end
                        state <= SEND_CMD;
                    end

                    DMA_BRING_B: begin
                        if (y == ylim) begin
                            set_C_params();
                            if (psums_change) begin
                                sub_state <= DMA_BRING_C;
                                start_wresp_sync <= 1'b1;
                                state <= SEND_CMD;
                            end else begin
                                sub_state <= DMA_SEND_C;
                                next_action <= GOTO_SYNC_WRESP;
                                goto_sync_sauria <= 1'b1;
                                state <= WAIT_DMA_INTR_READER;
                            end
                        end else begin
                            start_wresp_sync <= 1'b1;
                            state <= SEND_CMD;
                        end
                    end

                    DMA_BRING_C: begin
                        tmp_SRAMC_tile_offset <= SRAMC_tile_offset;
                        if (first_tile) begin
                            send_SRAMC_tile_offset <= SRAMC_tile_offset;
                        end
                        if (y == ylim && z == zlim) begin
                            if (first_tile && !single_tile) begin
                                set_A_params();
                                first_tile <= 1'b0;
                                sub_state <= DMA_BRING_A;
                            end else begin
                                sub_state <= DMA_SEND_C;
                            end
                            if (single_tile) begin
                                next_action <= GOTO_SYNC_SAURIA;
                            end else begin
                                next_action <= GOTO_SYNC_WRESP;
                            end
                            goto_sync_sauria <= 1'b1;
                            state <= WAIT_DMA_INTR_READER;
                        end else begin
                            start_wresp_sync <= 1'b1;
                            state <= SEND_CMD;
                        end
                    end

                    DMA_SEND_C: begin
                        if (y == ylim && z == zlim) begin
                            send_SRAMC_tile_offset <= tmp_SRAMC_tile_offset;
                            if (last_iter_2 || single_tile) begin
                                next_action <= GOTO_IDLE;
                                goto_sync_sauria <= 1'b1;
                                state <= WAIT_DMA_INTR_READER;
                            end else if (last_iter_1) begin
                                last_iter_2 <= 1'b1;
                                next_action <= GOTO_SYNC_WRESP;
                                goto_sync_sauria <= 1'b1;
                                state <= WAIT_DMA_INTR_READER;
                            end else begin
                                if (ifmaps_change) begin
                                    set_A_params();
                                    sub_state <= DMA_BRING_A;
                                end else begin
                                    set_B_params();
                                    sub_state <= DMA_BRING_B;
                                end
                                start_wresp_sync <= 1'b1;
                                state <= SEND_CMD;
                            end
                        end else begin
                            start_wresp_sync <= 1'b1;
                            state <= SEND_CMD;
                        end
                    end
                endcase
            end

            SAURIA_SYNC: begin
                goto_sync_sauria <= 1'b0;
                first_dma_iter <= 1'b1;
                last_psums_change <= psums_change;
                last_ifmaps_change <= ifmaps_change;
                last_weights_change <= weights_change;
                if (sauria_sync) begin
                    case (next_action)

                        GOTO_IDLE: begin
                            state <= IDLE;
                        end

                        GOTO_SYNC_SAURIA: begin
                            next_action <= GOTO_SYNC_WRESP;
                        end

                        GOTO_SYNC_WRESP: begin
                            if (!last_iter_2) begin
                                advance <= 1'b1;
                            end
                            state <= WRESP_SYNC;
                        end

                    endcase
                end
            end

            WRESP_SYNC: begin
                if (sauria_axilite_bvalid) begin
                    state <= COPY_OPT;
                end
            end

            COPY_OPT: begin
                wdata[0] <= 1'b1; //reader interrupt enable
                wdata[1] <= 1'b1; //writer interrupt enable
                addr <= INTERRUPT_MASK_REGISTER_OFFSET;
                if (sub_state == DMA_BRING_A && !ifmaps_change) begin
                    set_B_params();
                    sub_state <= DMA_BRING_B;
                    start_wresp_sync <= 1'b1;
                    state <= SEND_CMD;
                end else if (!last_iter_2 && sub_state == DMA_SEND_C && !last_psums_change) begin
                    if (last_iter_1) begin
                        last_iter_2 <= 1'b1;
                        next_action <= GOTO_SYNC_WRESP;
                        state <= SAURIA_SYNC;
                    end else begin
                        set_A_params();
                        sub_state <= DMA_BRING_A;
                        start_wresp_sync <= 1'b1;
                        state <= SEND_CMD;
                    end
                end else begin
                    start_wresp_sync <= 1'b1;
                    state <= SEND_CMD;
                end
            end

        endcase

        if (rst) begin
            state <= IDLE;
        end
    end

endmodule
