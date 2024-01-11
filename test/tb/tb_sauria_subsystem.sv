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

`timescale 1ps/1ps

//`define POWER
//`define NETLIST_TOP
//`define APPROXIMATE

//`define BMK_SMALL
`define BMK_TORTURE

module tb_sauria_subsystem ();

	// --------------------------
	// Simulation Parameters
	// --------------------------
	
    // timeunit 1ps;
    // timeprecision 1ps;

    localparam time CLK_PERIOD          = 600ps;
	localparam time APPL_DELAY          = 200ps;
    localparam time ACQ_DELAY           = 300ps;
    localparam time TEST_DELAY          = 400ps;
	
    localparam time CLK_PERIOD_SAURIA   = 2500ps;
    localparam time PHASE_DLY_SAURIA    = 300ps;
	
    localparam DRAM_OFFSET               = 32'h0;

    localparam unsigned RST_CLK_CYCLES  = 10;

	// Number of Input Vectors & Number of tests
    localparam N_TESTS_MAX = 100;
    `ifdef POWER
	    localparam unsigned N_VECTORS = 20000;
    `else
        localparam unsigned N_VECTORS = 150000;
    `endif

    // Number of cycles without activity to declare the system stuck (dead)
    localparam longint DEAD_CYCLES = 10000000;

    // DUT Parameters
    localparam CFG_AXI_DATA_WIDTH    = 32;
    localparam CFG_AXI_ADDR_WIDTH    = 32;

    localparam DATA_AXI_DATA_WIDTH    = 128;
    localparam DATA_AXI_ADDR_WIDTH    = 32;
    localparam DATA_AXI_ID_WIDTH      = 4;

    localparam  BYTE = 8;
    localparam  CFG_AXI_BYTE_NUM = CFG_AXI_DATA_WIDTH/BYTE;
    localparam  DATA_AXI_BYTE_NUM = DATA_AXI_DATA_WIDTH/BYTE;

    // FP16 parameters
    localparam FP_W = sauria_pkg::FP_W;
    localparam MANT_W = sauria_pkg::MANT_W;
    localparam EXP_W = FP_W-MANT_W-1;

    parameter TEST_TOLERANCE_REL = 0.05;   // For FP16 testing -> Relative tolerance for the output value
    parameter ABS_ERR_THRES = 0.5;

	// --------------------------
	// Signals
	// --------------------------
	
    logic       clk, rstn;
    logic       clk_sauria, rstn_sauria;
    logic       sauria_interrupt, dma_interrupt, controller_interrupt;

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

	// ----------------------------------------------------
	// CFG AXI Lite Driver - Definitions and instantiation
	// ----------------------------------------------------

    // AXI4 Lite Master for CONFIG
    typedef axi_test::axi_lite_rand_master #(
        // AXI interface parameters
        .AW ( CFG_AXI_ADDR_WIDTH ),
        .DW ( CFG_AXI_DATA_WIDTH ),
        // Stimuli application and test time
        .TA ( 0  ),
        .TT ( 0  ),
        .MIN_ADDR ( '0 ),
        .MAX_ADDR ( '1   ),
        .MAX_READ_TXNS  ( 10 ),
        .MAX_WRITE_TXNS ( 10 )
    ) cfg_rand_lite_master_t;

    // AXI4 Lite configuration interface
    AXI_LITE #(
        .AXI_ADDR_WIDTH ( CFG_AXI_ADDR_WIDTH      ),
        .AXI_DATA_WIDTH ( CFG_AXI_DATA_WIDTH      )
    ) cfg_bus_lite ();

    // AXI4 data interface
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( DATA_AXI_ADDR_WIDTH      ),
        .AXI_DATA_WIDTH ( DATA_AXI_DATA_WIDTH      ),
        .AXI_ID_WIDTH   ( DATA_AXI_ID_WIDTH        ),
        .AXI_USER_WIDTH (1) // Unused, but 0 can cause compilation errors
    ) dat_bus ();

    // AXI4 Lite configuration interface (DESIGN VERIFICATION)
    AXI_LITE_DV #(
        .AXI_ADDR_WIDTH ( CFG_AXI_ADDR_WIDTH      ),
        .AXI_DATA_WIDTH ( CFG_AXI_DATA_WIDTH      )
    ) cfg_bus_lite_dv (clk);

    // Assign interfaces to simulated ones
    `AXI_LITE_ASSIGN(cfg_bus_lite, cfg_bus_lite_dv)

	// Assign requests and responses to their respective slaves
	`AXI_ASSIGN_TO_REQ(        axi_mem_req, dat_bus)
	`AXI_ASSIGN_FROM_RESP(     dat_bus, axi_mem_resp)

	// ------------------------------------------
	// Golden Stimuli and Golden Outputs (IF)
	// ------------------------------------------

    // Test configuration from file
    integer n_tests, n_tiles;
    logic   [N_TESTS_MAX-1:0][9:0]                      test_tiles;
    logic   [N_TESTS_MAX-1:0][DATA_AXI_ADDR_WIDTH-1:0]  test_startoffs;
    logic   [N_TESTS_MAX-1:0][DATA_AXI_ADDR_WIDTH-1:0]  test_endoffs;

    // Golden model stimuli
    logic [N_VECTORS-1:0][CFG_AXI_DATA_WIDTH-1:0]   gold_cfg_data_in;
    logic [N_VECTORS-1:0][CFG_AXI_ADDR_WIDTH-1:0]   gold_cfg_address;
    logic [N_VECTORS-1:0]                           gold_cfg_wren;
    logic [N_VECTORS-1:0]                           gold_cfg_rden;
    logic [N_VECTORS-1:0][1:0]                      gold_cfg_waitflag;

    logic [N_VECTORS-1:0][CFG_AXI_DATA_WIDTH-1:0]   gold_dma_data_in;
    logic [N_VECTORS-1:0][CFG_AXI_ADDR_WIDTH-1:0]   gold_dma_address;
    logic [N_VECTORS-1:0]                           gold_dma_wren;
    logic [N_VECTORS-1:0]                           gold_dma_rden;
    logic [N_VECTORS-1:0][1:0]                      gold_dma_waitflag;

    logic [N_VECTORS-1:0]                           gold_wake_cfg;
    logic [N_VECTORS-1:0]                           gold_wake_dat;

    // Golden model outputs
    logic [N_VECTORS-1:0][CFG_AXI_DATA_WIDTH-1:0]   gold_o_data_out;
    logic [N_VECTORS-1:0]                           gold_checkflag;

    logic [N_VECTORS-1:0][CFG_AXI_DATA_WIDTH-1:0]   gold_cfg_data_out;
    logic [N_VECTORS-1:0]                           gold_cfg_checkflag;

    localparam IM_size = 5;

    longint  cfg_Matrix         [2+3*N_TESTS_MAX-1:0];
    longint  Input_Matrix       [0:N_VECTORS-1][0:IM_size-1];
    longint  Output_Matrix      [0:N_VECTORS-1][0:1];

	// Gold DRAM
    logic [7:0]     gold_dram[dat_addr_t];

    // Current test index
    integer test_idx = 0;

    // Check flags
    logic check_flag;

    // Wait flag (for SAURIA)
    logic wait_flag_cfg;

    // Expected data_out
    logic [DATA_AXI_DATA_WIDTH-1:0] exp_data_out, acq_data_out;

	// ------------------------------------------
	// Activity watchdog
	// ------------------------------------------

    logic stuck_detected = 0;

	// --------------------------
	// Reset and Clock generation
	// --------------------------
	initial begin: reset_block
		rstn = 0;
        rstn_sauria = 0;
		#(CLK_PERIOD*RST_CLK_CYCLES);
		rstn = 1;
        rstn_sauria = 1;
	end
	
    // System clock at high frequency
	initial begin: clock_block
		forever begin
			clk = 0;
			#(CLK_PERIOD/2);
			clk = 1;
			#(CLK_PERIOD/2);
		end
	end

    // SAURIA clock at a lower frequency
	initial begin: SAURIA_clock_block
		#(PHASE_DLY_SAURIA);
        forever begin
			clk_sauria = 0;
			#(CLK_PERIOD_SAURIA/2);
			clk_sauria = 1;
			#(CLK_PERIOD_SAURIA/2);
		end
	end

	// --------------------------
    // Instantiate the DUTs
	// --------------------------
	
    // If netlist we do not need parameters
    `ifdef NETLIST_TOP            
        sauria_subsystem_syn #(  

    // If not netlist, instantiate the module with params
    `else
        sauria_subsystem #(
            .CFG_AXI_DATA_WIDTH(CFG_AXI_DATA_WIDTH),
            .CFG_AXI_ADDR_WIDTH(CFG_AXI_ADDR_WIDTH),
            .DATA_AXI_DATA_WIDTH(DATA_AXI_DATA_WIDTH),
            .DATA_AXI_ADDR_WIDTH(DATA_AXI_ADDR_WIDTH),
            .DATA_AXI_ID_WIDTH(DATA_AXI_ID_WIDTH)
    `endif
	) dut(
		.i_system_clk           (clk),
        .i_system_rstn          (rstn),

		.i_sauria_clk           (clk_sauria),
        .i_sauria_rstn          (rstn_sauria),

        .i_cfg_axi_arprot         (cfg_bus_lite.ar_prot),
        .i_cfg_axi_araddr         (cfg_bus_lite.ar_addr),
        .i_cfg_axi_arvalid        (cfg_bus_lite.ar_valid),
        .o_cfg_axi_arready        (cfg_bus_lite.ar_ready),
        .o_cfg_axi_rdata          (cfg_bus_lite.r_data),
        .o_cfg_axi_rresp          (cfg_bus_lite.r_resp),
        .o_cfg_axi_rvalid         (cfg_bus_lite.r_valid),
        .i_cfg_axi_rready         (cfg_bus_lite.r_ready),
        .i_cfg_axi_awprot         (cfg_bus_lite.aw_prot),
        .i_cfg_axi_awaddr         (cfg_bus_lite.aw_addr),
        .i_cfg_axi_awvalid        (cfg_bus_lite.aw_valid),
        .o_cfg_axi_awready        (cfg_bus_lite.aw_ready),
        .i_cfg_axi_wdata          (cfg_bus_lite.w_data),
        .i_cfg_axi_wstrb          (cfg_bus_lite.w_strb),
        .i_cfg_axi_wvalid         (cfg_bus_lite.w_valid),
        .o_cfg_axi_wready         (cfg_bus_lite.w_ready),
        .o_cfg_axi_bresp          (cfg_bus_lite.b_resp),
        .o_cfg_axi_bvalid         (cfg_bus_lite.b_valid),
        .i_cfg_axi_bready         (cfg_bus_lite.b_ready),

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

        .o_intr                 (controller_interrupt),
        .o_writer_dmaintr       (dma_interrupt),
        .o_sauriaintr           (sauria_interrupt)
    );

    // DRAM Memory simulation (AXI Slave)
	axi_mem_slave #(
        .AxiAddrWidth   (DATA_AXI_ADDR_WIDTH),
        .AxiDataWidth   (DATA_AXI_DATA_WIDTH),
        .AxiIdWidth     (DATA_AXI_ID_WIDTH),
		.req_t          (dat_req_t),
		.resp_t         (dat_resp_t)
	) i_sim_mem_0(
		.clk_i(clk),
		.rst_ni(rstn),

		.axi_req_i      (axi_mem_req),
		.axi_resp_o     (axi_mem_resp)
	);

    // -----------------------------------
    // Functions
	// -----------------------------------
    function real FP_to_real (input logic [FP_W-1:0] value);

        integer sign, exp, mant;

        sign =  value[FP_W-1];
        exp =   value[FP_W-2:MANT_W] - ($pow(2, (EXP_W-1)) - 1);
        mant =  value[MANT_W-1:0];

        FP_to_real = $pow(-1, sign)*$pow(2, real'(exp))*(1 + (real'(mant)/$pow(2, MANT_W)));

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

	// -----------------------------------
    // Load golden stimuli & outputs
	// -----------------------------------

    initial begin: load_golden_model

        `ifdef BMK_SMALL
            `ifdef APPROXIMATE
                $readmemh("../stimuli/bmk_small/tstcfg_approx.txt", cfg_Matrix);
                $readmemh("../stimuli/bmk_small/GoldenStimuli_approx.txt", Input_Matrix);
                $readmemh("../stimuli/bmk_small/GoldenOutputs_approx.txt", Output_Matrix);
            `else
                $readmemh("../stimuli/bmk_small/tstcfg.txt", cfg_Matrix);
                $readmemh("../stimuli/bmk_small/GoldenStimuli.txt", Input_Matrix);
                $readmemh("../stimuli/bmk_small/GoldenOutputs.txt", Output_Matrix);
            `endif
        `else
            `ifdef BMK_TORTURE
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/bmk_torture/tstcfg_approx.txt", cfg_Matrix);
                    $readmemh("../stimuli/bmk_torture/GoldenStimuli_approx.txt", Input_Matrix);
                    $readmemh("../stimuli/bmk_torture/GoldenOutputs_approx.txt", Output_Matrix);
                `else
                    $readmemh("../stimuli/bmk_torture/tstcfg.txt", cfg_Matrix);
                    $readmemh("../stimuli/bmk_torture/GoldenStimuli.txt", Input_Matrix);
                    $readmemh("../stimuli/bmk_torture/GoldenOutputs.txt", Output_Matrix);
                `endif
            `else
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/conv_validation/tstcfg_approx.txt", cfg_Matrix);
                    $readmemh("../stimuli/conv_validation/GoldenStimuli_approx.txt", Input_Matrix);
                    $readmemh("../stimuli/conv_validation/GoldenOutputs_approx.txt", Output_Matrix);
                `else
                    $readmemh("../stimuli/conv_validation/tstcfg.txt", cfg_Matrix);
                    $readmemh("../stimuli/conv_validation/GoldenStimuli.txt", Input_Matrix);
                    $readmemh("../stimuli/conv_validation/GoldenOutputs.txt", Output_Matrix);
                `endif
            `endif
        `endif

        // Get total number of tests & total number of tiles
        n_tests = cfg_Matrix[0];
        n_tiles = cfg_Matrix[1];

        // Assign test cfg values to vectors
        for (integer j=0; j < n_tests; j++) begin
            test_tiles[j] =         cfg_Matrix[2+3*j];
            test_startoffs[j] =     cfg_Matrix[2+3*j+1];
            test_endoffs[j] =       cfg_Matrix[2+3*j+2];
        end

        // Assign control/data values to the specific vectors
        for (integer i=0; i < N_VECTORS; i++) begin

            gold_cfg_data_in[i] =     Input_Matrix[i][0];
            gold_cfg_address[i] =     Input_Matrix[i][1];
            gold_cfg_wren[i] =        Input_Matrix[i][2];
            gold_cfg_rden[i] =        Input_Matrix[i][3];
            gold_cfg_waitflag[i] =    Input_Matrix[i][4];

            gold_o_data_out[i] =            Output_Matrix[i][0];
            gold_checkflag[i] =             Output_Matrix[i][1];
        end
    end

    // DRAM DATA LOADING
    // ***********************************
    
    initial begin: data_load_block

        // LOAD DATA INTO ACTUAL AND GOLD DRAM
        `ifdef BMK_SMALL
            `ifdef APPROXIMATE
                $readmemh("../stimuli/bmk_small/initial_dram_approx.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                $readmemh("../stimuli/bmk_small/gold_dram_approx.txt", gold_dram, DRAM_OFFSET);
            `else
                $readmemh("../stimuli/bmk_small/initial_dram.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                $readmemh("../stimuli/bmk_small/gold_dram.txt", gold_dram, DRAM_OFFSET);
            `endif
        `else
            `ifdef BMK_TORTURE
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/bmk_torture/initial_dram_approx.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/bmk_torture/gold_dram_approx.txt", gold_dram, DRAM_OFFSET);
                `else
                    $readmemh("../stimuli/bmk_torture/initial_dram.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/bmk_torture/gold_dram.txt", gold_dram, DRAM_OFFSET);
                `endif
            `else
                `ifdef APPROXIMATE
                    $readmemh("../stimuli/conv_validation/initial_dram_approx.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/conv_validation/gold_dram_approx.txt", gold_dram, DRAM_OFFSET);
                `else
                    $readmemh("../stimuli/conv_validation/initial_dram.txt", i_sim_mem_0.mem, DRAM_OFFSET);
                    $readmemh("../stimuli/conv_validation/gold_dram.txt", gold_dram, DRAM_OFFSET);
                `endif
            `endif
        `endif
    end

	// --------------------------------------------------------------------------------------------------------------
	// Activity Watchdog => If activities & responses do not change in K cycles, declare the experiment dead
	// --------------------------------------------------------------------------------------------------------------

    initial begin: watchdog

        logic   prev_cfg_w_valid;
        logic   prev_cfg_r_valid;
        logic   prev_dat_w_valid;
        logic   prev_dat_r_valid;

        logic eq;
        longint cycle_cnt;

        cycle_cnt = 0;

        forever begin
            @(posedge clk);

            eq =  (prev_cfg_w_valid==cfg_bus_lite.w_valid)
                &&(prev_cfg_r_valid==cfg_bus_lite.r_valid)
                &&(prev_dat_w_valid==dat_bus.w_valid)
                &&(prev_dat_r_valid==dat_bus.r_valid);

            if(eq) begin
                cycle_cnt = cycle_cnt+1;

                if(cycle_cnt >= DEAD_CYCLES)begin
                    $display("EXPERIMENT ABORTED - DECLARED STUCK at ", $time);
                    $finish();
                end
            end else begin
                cycle_cnt = 0;
            end

            prev_cfg_w_valid = cfg_bus_lite.w_valid;
            prev_cfg_r_valid = cfg_bus_lite.r_valid;
            prev_dat_w_valid = dat_bus.w_valid;
            prev_dat_r_valid = dat_bus.r_valid;

        end
    end

	// ----------------------------------
	// Apply stimuli & get exp. response
	// ----------------------------------

    // PROCESS FOR CONFIGURATION INTERFACE
    // ***********************************

    initial begin: config_stimuli_block

        // AXI Lite Master tasks
        automatic cfg_rand_lite_master_t cfg_lite_axi_master = new ( cfg_bus_lite_dv, "Lite Master");

        // Temp response and data for reading     
        axi_pkg::resp_t                     rsp_tmp;
        logic [CFG_AXI_DATA_WIDTH-1:0]      data_tmp;

        // Check signals
        integer     idx_i = 0;
        integer     n_checks = 0;
        integer     n_errs = 0;
        logic       error;
        real        real_exp, real_acq;
        integer     n_errs_prev = 0;

        logic [31:0]    dram_startoffs, dram_endoffs, dram_region;

        // Expected amd acquired bytes from DRAM
        logic [7:0] exp_byte, acq_byte;

        logic   [CFG_AXI_DATA_WIDTH-1:0]    cfg_data_in;
        logic   [CFG_AXI_ADDR_WIDTH-1:0]    cfg_addr;
        logic                               cfg_wren;
        logic                               cfg_rden;

        // Start by RESET-ing the masters
        cfg_lite_axi_master.reset();
        
        // Wait until RST is high
        wait (rstn);

        while (idx_i < N_VECTORS) begin

            // @(posedge clk);          // Clock is managed internally by AXI masters
			// #(APPL_DELAY);

            // Gather stimuli
            cfg_data_in =       gold_cfg_data_in[idx_i];
            cfg_addr =          gold_cfg_address[idx_i];
            cfg_wren =          gold_cfg_wren[idx_i];
            cfg_rden =          gold_cfg_rden[idx_i];

            // Get control flags
            check_flag =        gold_checkflag[idx_i];
            wait_flag_cfg =     gold_cfg_waitflag[idx_i];
            
            // If we are writing
            if (cfg_wren) begin
                cfg_lite_axi_master.write(cfg_addr, '0, cfg_data_in, '1, rsp_tmp);

            // If we are reading
            end else if (cfg_rden) begin
                cfg_lite_axi_master.read(cfg_addr, '0, data_tmp, rsp_tmp);

                // // Get expected and acquired values
                // exp_cfg_data =      gold_cfg_data_out[idx_i];
                // acq_cfg_data =      data_tmp;

            // If we need to do nothing, wait during the current CLK cycle
            end else begin
                @(posedge clk);
            end

            // Checking block
            if (check_flag) begin
    
                // Get DRAM region to check
                dram_startoffs = test_startoffs[test_idx-1];
                dram_endoffs =   test_endoffs[test_idx-1];

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

                                $display("[Test ",test_idx-1,"] - WRITING mismatch occured at ", $time);
                                $displayh("[Address ",k,"] Expected = ", exp_data_out , " but got ", acq_data_out);
                            end

                        end else begin
                            
                            //$displayh("[Address ",k,"] Expected = ", exp_data_out , " and got ", acq_data_out);

                            for (integer j=0; j<(CFG_AXI_DATA_WIDTH/sauria_pkg::OC_W); j++) begin

                                real_exp = FP_to_real(exp_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W]);
                                real_acq = FP_to_real(acq_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W]);

                                if (abs(real_exp-real_acq)>max(ABS_ERR_THRES,abs(TEST_TOLERANCE_REL*real_exp))) begin
                                    n_errs += 1;

                                    $display("[Test ",test_idx-1,"] - WRITING mismatch occured at ", $time);
                                    $displayh("Expected o_data_out[",j,"] = ", real_exp , " but got ", real_acq);
                                    $displayh("[Address ",k,"] (Expected word = ", exp_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W] , " but got ", acq_data_out[j*sauria_pkg::OC_W+:sauria_pkg::OC_W], ")");
                                end
                            end
                        end
                    end
                end

                // If n errors did not change, test passed
                if (n_errs == n_errs_prev) begin
                    $display("Test ",test_idx-1," passed on all positions :)");
                end else begin
                    $display("Test ",test_idx-1," FAILED!");
                end

                n_errs_prev = n_errs;
            end

            // Upon SAURIA wait flag, wait for done interrupt
            if (wait_flag_cfg) begin

                // If interrupt is already high we don't need to wait
                if (!controller_interrupt) begin
                    @(controller_interrupt);
                end

                test_idx += 1;
            end

            idx_i += 1;

            // WHEN FINAL TEST IS FINISHED
            if (test_idx >= (n_tests)) begin

                // If n errors did not change, last test passed
                if (n_errs == n_errs_prev) begin
                    $display("Test ",test_idx-1," passed on all positions :)");
                end else begin
                    $display("Test ",test_idx-1," FAILED!");
                end
        
                // ------------------
                // FINAL ERROR SUMMARY
                // ------------------
        
                if ((n_errs) > 0) begin
                    $display("Test failed with ", n_errs, " mismatches out of ", n_checks, " checks.");
                end
                else begin
                    $display("Test passed with 0 mismatches out of ", n_checks, " checks.");
                end
        
                $stop();

            end
        end
    end

    // -----------------------------------
    // Cycle count for computations
	// -----------------------------------

    `ifdef GET_CYCLES

        // Signal that watches for a start flag in CFG AXI
        logic start_watch;

        assign start_watch = (cfg_bus_lite.aw_addr[15:0]=='0)&&(cfg_bus_lite.aw_valid)&&(cfg_bus_lite.aw_ready)&&(cfg_bus_lite.w_data==3);

        initial begin: cycle_counter
            
            integer cycles=0;
            integer f = $fopen("cycles.txt", "w");

            wait (rstn);

            while (test_idx < (n_tests+1)) begin

                @(negedge start_watch);

                while (controller_interrupt == 1'b0) begin
                    @(posedge clk);
                    cycles += 1;
                end

                $display("Convolution took ", cycles, " clock cycles.");
                $fdisplay(f, cycles);
                cycles = 0;
            end
        end
    `endif

endmodule
