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

// --------------------
//      DEFINES
// --------------------

`define PRINT_ERRORS

module sauria_tester(
    input  logic        rstn_sauria,
    input  logic        clk_sauria,
    input  logic        rstn_sys,
    input  logic        clk_sys,

    input  logic [1:0]  file_opts,       

    input  logic [31:0]     cfg_bus_lite_ar_addr,
    input  logic            cfg_bus_lite_ar_valid,
    output logic            cfg_bus_lite_ar_ready,
    output logic [31:0]     cfg_bus_lite_r_data,
    output logic            cfg_bus_lite_r_valid,
    input  logic            cfg_bus_lite_r_ready,
    input  logic [31:0]     cfg_bus_lite_aw_addr,
    input  logic            cfg_bus_lite_aw_valid,
    output logic            cfg_bus_lite_aw_ready,
    input  logic [31:0]     cfg_bus_lite_w_data,
    input  logic            cfg_bus_lite_w_valid,
    output logic            cfg_bus_lite_w_ready,

    input  logic [7:0]      test_idx,
    input  logic            check_flag,
    input  logic [31:0]     dram_startoffs,
    input  logic [31:0]     dram_endoffs,
    output logic [31:0]     errors,

    output logic        ctrl_interrupt,
    output logic        sauria_interrupt,
    output logic        dma_interrupt
);

	// ------------
	// Parameters
	// ------------ 

    localparam DRAM_OFFSET               = 32'h0;

    localparam CFG_AXI_DATA_WIDTH    = 32;
    localparam CFG_AXI_ADDR_WIDTH    = 32;

    localparam DATA_AXI_DATA_WIDTH    = 128;
    localparam DATA_AXI_ADDR_WIDTH    = 32;
    localparam DATA_AXI_ID_WIDTH      = 4;

    localparam  BYTE = 8;
    localparam  CFG_AXI_BYTE_NUM = CFG_AXI_DATA_WIDTH/BYTE;
    localparam  DATA_AXI_BYTE_NUM = DATA_AXI_DATA_WIDTH/BYTE;

    // FP16 parameters
    parameter TEST_TOLERANCE_REL = 0.05;   // For FP16 testing -> Relative tolerance for the output value
    parameter ABS_ERR_THRES = 0.5;

	// --------------------------
	// Signals
	// --------------------------
	
	// AXI type definitions
	typedef logic [DATA_AXI_ADDR_WIDTH-1:0]     dat_addr_t;
	typedef logic [DATA_AXI_ID_WIDTH-1:0]       dat_id_t;
	typedef logic [DATA_AXI_DATA_WIDTH-1:0]     dat_data_t;
	typedef logic [DATA_AXI_BYTE_NUM-1:0]       dat_strb_t;

	// Derivative typedefs (with macros)
	`AXI_TYPEDEF_AW_CHAN_T(    dat_aw_chan_t, dat_addr_t, dat_id_t, logic)
	`AXI_TYPEDEF_W_CHAN_T(     dat_w_chan_t, dat_data_t, dat_strb_t, logic)
	`AXI_TYPEDEF_B_CHAN_T(     dat_b_chan_t, dat_id_t, logic)
	`AXI_TYPEDEF_AR_CHAN_T(    dat_ar_chan_t, dat_addr_t, dat_id_t, logic)
	`AXI_TYPEDEF_R_CHAN_T(     dat_r_chan_t, dat_data_t, dat_id_t, logic)

	`AXI_TYPEDEF_REQ_T(    dat_req_t, dat_aw_chan_t, dat_w_chan_t, dat_ar_chan_t)
	`AXI_TYPEDEF_RESP_T(   dat_resp_t, dat_b_chan_t, dat_r_chan_t)

	// AXI responses and requests
	dat_req_t      axi_mem_req;
	dat_resp_t     axi_mem_resp;

    // AXI4 data interface
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( DATA_AXI_ADDR_WIDTH      ),
        .AXI_DATA_WIDTH ( DATA_AXI_DATA_WIDTH      ),
        .AXI_ID_WIDTH   ( DATA_AXI_ID_WIDTH        )
    ) dat_bus ();

	// Assign requests and responses to their respective slaves
	`AXI_ASSIGN_TO_REQ(        axi_mem_req, dat_bus)
	`AXI_ASSIGN_FROM_RESP(     dat_bus, axi_mem_resp)

    // -----------------------------------
    // Functions
	// -----------------------------------

    function real FP_to_real (input logic [sauria_pkg::FP_W-1:0] value);

        integer sign, exp, mant;

        sign =  value[sauria_pkg::FP_W-1];
        exp =   value[sauria_pkg::FP_W-2:sauria_pkg::MANT_W] - ($pow(2, (sauria_pkg::EXP_W-1)) - 1);
        mant =  value[sauria_pkg::MANT_W-1:0];

        FP_to_real = $pow(-1, sign)*$pow(2, real'(exp))*(1 + (real'(mant)/$pow(2, sauria_pkg::MANT_W)));

    endfunction

    function real abs (input real value);

        if(value>=0)begin
            abs = value;
        end else begin
            abs = 0 - value;
        end

    endfunction

    function real max (input real val1, input real val2);

        if(val1>=val2)begin
            max = val1;
        end else begin
            max = val2;
        end

    endfunction

	// --------------------------
    // Instantiate the DUTs
	// --------------------------

    sauria_subsystem #(
        .CFG_AXI_DATA_WIDTH(CFG_AXI_DATA_WIDTH),
        .CFG_AXI_ADDR_WIDTH(CFG_AXI_ADDR_WIDTH),
        .DATA_AXI_DATA_WIDTH(DATA_AXI_DATA_WIDTH),
        .DATA_AXI_ADDR_WIDTH(DATA_AXI_ADDR_WIDTH),
        .DATA_AXI_ID_WIDTH(DATA_AXI_ID_WIDTH)
	) dut(
		.i_system_clk           (clk_sys),
        .i_system_rstn          (rstn_sys),

		.i_sauria_clk           (clk_sauria),
        .i_sauria_rstn          (rstn_sauria),

        .i_cfg_axi_arprot         ('0),
        .i_cfg_axi_araddr         (cfg_bus_lite_ar_addr),
        .i_cfg_axi_arvalid        (cfg_bus_lite_ar_valid),
        .o_cfg_axi_arready        (cfg_bus_lite_ar_ready),
        .o_cfg_axi_rdata          (cfg_bus_lite_r_data),
        .o_cfg_axi_rresp          (),
        .o_cfg_axi_rvalid         (cfg_bus_lite_r_valid),
        .i_cfg_axi_rready         (cfg_bus_lite_r_ready),
        .i_cfg_axi_awprot         (),
        .i_cfg_axi_awaddr         (cfg_bus_lite_aw_addr),
        .i_cfg_axi_awvalid        (cfg_bus_lite_aw_valid),
        .o_cfg_axi_awready        (cfg_bus_lite_aw_ready),
        .i_cfg_axi_wdata          (cfg_bus_lite_w_data),
        .i_cfg_axi_wstrb          ('1),
        .i_cfg_axi_wvalid         (cfg_bus_lite_w_valid),
        .o_cfg_axi_wready         (cfg_bus_lite_w_ready),
        .o_cfg_axi_bresp          (),
        .o_cfg_axi_bvalid         (),
        .i_cfg_axi_bready         ('1),

        .o_dat_axi_arid           (dat_bus.ar_id),
        .o_dat_axi_arprot         (dat_bus.ar_prot),
        .o_dat_axi_araddr         (dat_bus.ar_addr),
        .o_dat_axi_arburst        (dat_bus.ar_burst),
        .o_dat_axi_arlen          (dat_bus.ar_len),
        .o_dat_axi_arvalid        (dat_bus.ar_valid),
        .i_dat_axi_arready        (dat_bus.ar_ready),
        .o_dat_axi_arsize         (dat_bus.ar_size),
        .o_dat_axi_arlock         (dat_bus.ar_lock),
        .o_dat_axi_arcache        (dat_bus.ar_cache),
        .o_dat_axi_arqos          (dat_bus.ar_qos),
        .i_dat_axi_rid            (dat_bus.r_id),
        .i_dat_axi_rdata          (dat_bus.r_data),
        .i_dat_axi_rresp          (dat_bus.r_resp),
        .i_dat_axi_rvalid         (dat_bus.r_valid),
        .i_dat_axi_rlast          (dat_bus.r_last),
        .o_dat_axi_rready         (dat_bus.r_ready),
        .o_dat_axi_awid           (dat_bus.aw_id),
        .o_dat_axi_awprot         (dat_bus.aw_prot),
        .o_dat_axi_awaddr         (dat_bus.aw_addr),
        .o_dat_axi_awburst        (dat_bus.aw_burst),
        .o_dat_axi_awlen          (dat_bus.aw_len),
        .o_dat_axi_awvalid        (dat_bus.aw_valid),
        .i_dat_axi_awready        (dat_bus.aw_ready),
        .o_dat_axi_awsize         (dat_bus.aw_size),
        .o_dat_axi_awlock         (dat_bus.aw_lock),
        .o_dat_axi_awcache        (dat_bus.aw_cache),
        .o_dat_axi_awqos          (dat_bus.aw_qos),
        .o_dat_axi_wdata          (dat_bus.w_data),
        .o_dat_axi_wstrb          (dat_bus.w_strb),
        .o_dat_axi_wlast          (dat_bus.w_last),
        .o_dat_axi_wvalid         (dat_bus.w_valid),
        .i_dat_axi_wready         (dat_bus.w_ready),
        .i_dat_axi_bid            (dat_bus.b_id),
        .i_dat_axi_bresp          (dat_bus.b_resp),
        .i_dat_axi_bvalid         (dat_bus.b_valid),
        .o_dat_axi_bready         (dat_bus.b_ready),

        .o_intr                 (ctrl_interrupt),
        .o_writer_dmaintr       (dma_interrupt),
        .o_sauriaintr           (sauria_interrupt)
    );

    // DRAM Memory simulation
    axi_mem_slave #(
        .AxiAddrWidth   (DATA_AXI_ADDR_WIDTH),
        .AxiDataWidth   (DATA_AXI_DATA_WIDTH),
        .AxiIdWidth     (DATA_AXI_ID_WIDTH),
		.req_t          (dat_req_t),
		.resp_t         (dat_resp_t)
    ) i_sim_mem_0 (
		.clk_i          (clk_sys),
		.rst_ni         (rstn_sys),

		.axi_req_i      (axi_mem_req),
		.axi_resp_o     (axi_mem_resp)
    );

    integer         n_errs, n_errs_prev;
    logic [7:0]     gold_dram[dat_addr_t];

    assign errors = n_errs;

    // Load memories
    initial begin: data_load_check
        case(file_opts)
            // 0 = bmk_small
            0: begin
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/bmk_small/initial_dram_approx.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/bmk_small/gold_dram_approx.txt", gold_dram, DRAM_OFFSET);
                `else
                    $readmemh("../stimuli/bmk_small/initial_dram.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/bmk_small/gold_dram.txt", gold_dram, DRAM_OFFSET);
                `endif
            end
            // 1 = bmk_torture
            1: begin
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/bmk_torture/initial_dram_approx.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/bmk_torture/gold_dram_approx.txt", gold_dram, DRAM_OFFSET);
                `else
                    $readmemh("../stimuli/bmk_torture/initial_dram.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/bmk_torture/gold_dram.txt", gold_dram, DRAM_OFFSET);
                `endif
            end
            // 2 = conv_validation
            2: begin
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/conv_validation/initial_dram_approx.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/conv_validation/gold_dram_approx.txt", gold_dram, DRAM_OFFSET);
                `else
                    $readmemh("../stimuli/conv_validation/initial_dram.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/conv_validation/gold_dram.txt", gold_dram, DRAM_OFFSET);
                `endif
            end
        endcase
    end

    // Check for data mismatches
    always @(posedge check_flag) begin

        // Check signals
        integer     n_checks = 0;
        logic       error;
        real        real_exp, real_acq;
        logic [7:0] exp_byte, acq_byte;

        logic [31:0] dram_region;

        logic [DATA_AXI_DATA_WIDTH-1:0] exp_data_out, acq_data_out;

        n_errs = 0;
        n_errs_prev = 0;

        // CHECK MEMORY POSITIONS WHEN REQUESTED
        if (check_flag) begin

            dram_region = 1+dram_endoffs-dram_startoffs;

            // GET ALL DATA WORDS FROM DRAM & GOLD_DRAM
            for (longint k=0; k<(dram_region); k++) begin

                n_checks += 1;
                error = 0;

                // Each test is an independent DRAM region
                exp_byte = gold_dram[DRAM_OFFSET + dram_startoffs + k];
                acq_byte = i_sim_mem_0.mem[DRAM_OFFSET + dram_startoffs + k];

                // Add byte to data word
                exp_data_out[8*(k%DATA_AXI_BYTE_NUM)+:8] = exp_byte;
                acq_data_out[8*(k%DATA_AXI_BYTE_NUM)+:8] = acq_byte;

                // When we have a full data word, check values
                if ((k%DATA_AXI_BYTE_NUM)==(DATA_AXI_BYTE_NUM-1)) begin

                    if (sauria_pkg::ARITHMETIC==0)begin
                        error = (exp_data_out != acq_data_out) || ($isunknown(acq_data_out));

                        if (error) begin
                            n_errs += 1;

                            `ifdef PRINT_ERRORS
                            $display("[Test ",test_idx,"] - WRITING mismatch occured at ", $time);
                            $displayh("[Address ",k,"] Expected = ", exp_data_out , " but got ", acq_data_out);
                            `endif
                        end

                    end else begin
                        
                        //$displayh("[Address ",k,"] Expected = ", exp_data_out , " and got ", acq_data_out);

                        for (integer j=0; j<(CFG_AXI_DATA_WIDTH/sauria_pkg::OC_W); j++) begin

                            real_exp = FP_to_real(exp_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W]);
                            real_acq = FP_to_real(acq_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W]);

                            if (abs(real_exp-real_acq)>max(ABS_ERR_THRES,abs(TEST_TOLERANCE_REL*real_exp))) begin
                                n_errs += 1;

                                `ifdef PRINT_ERRORS
                                $display("[Test ",test_idx,"] - WRITING mismatch occured at ", $time);
                                $displayh("Expected o_data_out[",j,"] = ", real_exp , " but got ", real_acq);
                                $displayh("[Address ",k,"] (Expected word = ", exp_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W] , " but got ", acq_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W], ")");
                                `endif
                            end
                        end
                    end
                end
            end
            n_errs_prev = n_errs;
        end
    end

endmodule
