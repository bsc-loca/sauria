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
// MODULE DECLARATION
// --------------------

module sauria_logic #(
    parameter IF_W = 32,                        // Accelerator config interface data width
    parameter IF_ADR_W = 32,                    // Accelerator config interface address width
    parameter ADRA_W = 10,                      // SRAM A address width
    parameter SRAMA_W = 64,                     // SRAM A data width
    parameter ADRB_W = 10,                      // SRAM B address width
    parameter SRAMB_W = 64,                     // SRAM B data width
    parameter ADRC_W = 10,                      // SRAM C address width
    parameter SRAMC_W = 64,                     // SRAM C data width
    parameter SRAMC_N = 0                       // SRAM C number of operands per data word
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Configuration Interface
    input  logic [IF_W-1:0]             i_data_in,          // Accelerator interface input data bus
    input  logic [IF_ADR_W-1:0]         i_address,          // Accelerator interface address
    input  logic                        i_wren,             // Accelerator interface write enable
    input  logic                        i_rden,             // Accelerator interface read enable
    input  logic [IF_W-1:0]             i_wmask,           // Accelerator interface write mask bus
    output logic [IF_W-1:0]             o_data_out,         // Accelerator interface output data bus

    // Activations SRAM Interface (SRAMA)
    input  logic [SRAMA_W-1:0]          i_srama_data,       // Data bus from SRAMA
    output logic [ADRA_W-1:0]           o_srama_addr,       // Address towards SRAMA
    output logic                        o_srama_rden,       // Read Enable for SRAMA

    // Weights SRAM Interface (SRAMB)
    input  logic [SRAMB_W-1:0]          i_sramb_data,       // Data bus from SRAMA
    output logic [ADRB_W-1:0]           o_sramb_addr,       // Address towards SRAMB
    output logic                        o_sramb_rden,       // Read Enable for SRAMB

    // Outputs SRAM Interface (SRAMC)
    input  logic [SRAMC_W-1:0]          i_sramc_rdata,      // Read data bus from SRAMC
    output logic [ADRC_W-1:0]           o_sramc_addr,       // Address towards SRAMC
    output logic                        o_sramc_rden,       // Read Enable for SRAMC
    output logic                        o_sramc_wren,       // Write Enable for SRAMC
    output logic [0:SRAMC_N-1]          o_sramc_wmask,      // Write Mask for SRAMC
    output logic [SRAMC_W-1:0]          o_sramc_wdata,      // Write data bus towards SRAMC

    // Global SRAM signals
    output logic [0:2]                  o_sram_select,      // Double-buffering SRAM selection
    output logic                        o_sram_deepsleep,   // DeepSleep control for all SRAMs
    output logic                        o_sram_powergate,   // Power gate control for all SRAMs

    // Done Interrupt
    output logic                        o_doneintr          // Completion interrupt towards host
);

// --------------------
// DERIVED PARAMETERS
// --------------------

// Operands per data word
localparam int SRAMA_N = SRAMA_W/sauria_pkg::IA_W;
localparam int SRAMB_N = SRAMB_W/sauria_pkg::IB_W;

// Counter index width: address width + word offset + 1
localparam int ACT_IDX_W = ADRA_W + $clog2(SRAMA_N) + 1;
localparam int WEI_IDX_W = ADRB_W + $clog2(SRAMB_N) + 1;
localparam int OUT_IDX_W = ADRC_W + $clog2(SRAMC_N) + 1;

// Processing Element latency
localparam int PE_LAT = sauria_pkg::STAGES_MUL + sauria_pkg::INTERMEDIATE_PIPELINE_STAGE + sauria_pkg::ZERO_GATING_MULT;

// ----------
// SIGNALS
// ----------

// Towards Config
logic                                               cg_done;
logic                                               cg_act_deadlock;
logic                                               cg_wei_deadlock;
logic                                               cg_feed_deadlock;
logic [4:0]                                         cg_ctx_status;
logic [4:0]                                         cg_feed_status;
logic [4:0]                                         cg_out_status;

// Towards Main Controller
logic                                               mc_start;
logic [ACT_IDX_W-1:0]                               mc_incntlim;
logic [OUT_IDX_W-1:0]                               mc_act_reps;
logic [OUT_IDX_W-1:0]                               mc_wei_reps;
logic                                               mc_outbuf_done;
logic                                               mc_shift_done;
logic                                               mc_finalwrite;
logic                                               mc_act_done;
logic                                               mc_act_til_done;
logic                                               mc_act_fifo_empty;
logic                                               mc_act_fifo_full;
logic                                               mc_act_stall;
logic                                               mc_wei_done;
logic                                               mc_wei_til_done;
logic                                               mc_wei_fifo_empty;
logic                                               mc_wei_fifo_full;
logic                                               mc_wei_stall;

// Towards Activation Feeder
logic [0:sauria_pkg::Y-1]                           af_rows_active;
logic [ACT_IDX_W-1:0]		                        af_xlim;
logic [ACT_IDX_W-1:0]		                        af_xstep;
logic [ACT_IDX_W-1:0]		                        af_ylim;
logic [ACT_IDX_W-1:0]		                        af_ystep;
logic [ACT_IDX_W-1:0]		                        af_chlim;
logic [ACT_IDX_W-1:0]		                        af_chstep;
logic [ACT_IDX_W-1:0]		                        af_til_xlim;
logic [ACT_IDX_W-1:0]		                        af_til_xstep;
logic [ACT_IDX_W-1:0]		                        af_til_ylim;
logic [ACT_IDX_W-1:0]		                        af_til_ystep;
logic					                            af_act_feeder_en;
logic                                               af_act_feeder_clear;
logic                                               af_act_valid;
logic                                               af_act_start;
logic                                               af_act_finalpush;
logic                                               af_act_cnt_en;
logic                                               af_act_cnt_clear;
logic                                               af_act_clearfifo;
logic                                               af_act_pop_en;
logic                                               af_act_finalctx;
logic [0:sauria_pkg::Y-1][sauria_pkg::PARAMS_W-1:0] af_loc_woffs;
logic [0:sauria_pkg::DILP_W-1]	                    af_Dil_pat;

// Towards Weight Feeder
logic [0:sauria_pkg::X-1]                           wf_cols_active;
logic                                               wf_waligned;
logic [WEI_IDX_W-1:0]		                        wf_wlim;
logic [WEI_IDX_W-1:0]		                        wf_wstep;
logic [WEI_IDX_W-1:0]		                        wf_auxlim;
logic [WEI_IDX_W-1:0]		                        wf_auxstep;
logic [WEI_IDX_W-1:0]		                        wf_til_klim;
logic [WEI_IDX_W-1:0]		                        wf_til_kstep;
logic					                            wf_wei_feeder_en;
logic                                               wf_wei_feeder_clear;
logic                                               wf_wei_valid;
logic                                               wf_wei_start;
logic                                               wf_wei_finalpush;
logic                                               wf_wei_cnt_en;
logic                                               wf_wei_cnt_clear;
logic                                               wf_wei_clearfifo;
logic                                               wf_wei_pop_en;
logic                                               wf_wei_cswitch;

// Towards Output Buffer
logic            		                            ob_preload_en;
logic [OUT_IDX_W-1:0]		                        ob_ncontexts;
logic [OUT_IDX_W-1:0]		                        ob_cxlim;
logic [OUT_IDX_W-1:0]		                        ob_cxstep;
logic [OUT_IDX_W-1:0]		                        ob_cklim;
logic [OUT_IDX_W-1:0]		                        ob_ckstep;
logic [OUT_IDX_W-1:0]		                        ob_til_cylim;
logic [OUT_IDX_W-1:0]		                        ob_til_cystep;
logic [OUT_IDX_W-1:0]		                        ob_til_cklim;
logic [OUT_IDX_W-1:0]		                        ob_til_ckstep;
logic					                            ob_outbuf_start;
logic                                               ob_outbuf_reset;
logic [sauria_pkg::PARAMS_W-1:0]                    ob_inactive_cols;
logic [0:sauria_pkg::Y-1][sauria_pkg::OC_W-1:0] 	ob_c_arr;

// Towards Systolic Array
logic [0:sauria_pkg::Y-1][sauria_pkg::IA_W-1:0]     sa_a_arr;
logic [0:sauria_pkg::X-1][sauria_pkg::IB_W-1:0]	    sa_b_arr;
logic [0:sauria_pkg::Y-1][sauria_pkg::OC_W-1:0] 	sa_c_arr;
logic                                               sa_reg_clear;
logic					                            sa_pipeline_en;
logic [0:sauria_pkg::X-1]				            sa_cswitch_arr;
logic					                            sa_cscan_en;
logic [sauria_pkg::TH_W-1:0]                        sa_thres;

// Towards all (soft_reset)
logic soft_reset;

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// Configuration Interface
config_regs #(
        .IF_W       (IF_W),
        .IF_ADR_W   (IF_ADR_W),
        .X          (sauria_pkg::X),
        .Y          (sauria_pkg::Y),
        .ACT_IDX_W  (ACT_IDX_W),
        .WEI_IDX_W  (WEI_IDX_W),
        .OUT_IDX_W  (OUT_IDX_W),
        .TH_W       (sauria_pkg::TH_W),
        .PARAMS_W   (sauria_pkg::PARAMS_W),
        .DILP_W     (sauria_pkg::DILP_W)
    ) config_regs_i
       (.i_clk              (i_clk),
        .i_rstn             (i_rstn),
        
        .i_data_in	        (i_data_in),
        .i_done             (cg_done),
        .i_act_deadlock     (cg_act_deadlock),
        .i_wei_deadlock     (cg_wei_deadlock),
        .i_feed_deadlock    (cg_feed_deadlock),
        .i_ctx_status       (cg_ctx_status),
        .i_feed_status      (cg_feed_status),
        .i_out_status       (cg_out_status),
        .i_pipeline_en      (sa_pipeline_en),
        .i_pop_en           (af_act_pop_en & wf_wei_pop_en),
        .i_address	        (i_address),
        .i_wren             (i_wren),
        .i_rden	            (i_rden),
        .i_wmask            (i_wmask),

        .o_start            (mc_start),
        .o_sram_select      (o_sram_select),
        .o_sram_deepsleep   (o_sram_deepsleep),
        .o_sram_powergate   (o_sram_powergate),

        .o_soft_reset       (soft_reset),

        .o_incntlim         (mc_incntlim),
        .o_act_reps	        (mc_act_reps),
        .o_wei_reps	        (mc_wei_reps),
        .o_thres            (sa_thres),

        .o_rows_active      (af_rows_active),
        .o_xlim	            (af_xlim),
        .o_xstep            (af_xstep),
        .o_ylim             (af_ylim),
        .o_ystep            (af_ystep),
        .o_chlim            (af_chlim),
        .o_chstep	        (af_chstep),
        .o_til_xlim	        (af_til_xlim),
        .o_til_xstep        (af_til_xstep),
        .o_til_ylim	        (af_til_ylim),
        .o_til_ystep        (af_til_ystep),
        .o_loc_woffs        (af_loc_woffs),
        .o_Dil_pat          (af_Dil_pat),

        .o_cols_active      (wf_cols_active),
        .o_waligned         (wf_waligned),
        .o_wlim	            (wf_wlim),
        .o_wstep            (wf_wstep),
        .o_auxlim           (wf_auxlim),
        .o_auxstep          (wf_auxstep),
        .o_til_klim	        (wf_til_klim),
        .o_til_kstep        (wf_til_kstep),

        .o_preload_en       (ob_preload_en),
        .o_inactive_cols    (ob_inactive_cols),
        .o_ncontexts        (ob_ncontexts),
        .o_cxlim            (ob_cxlim),
        .o_cxstep           (ob_cxstep),
        .o_cklim	        (ob_cklim),
        .o_ckstep           (ob_ckstep),
        .o_til_cylim        (ob_til_cylim),
        .o_til_cystep       (ob_til_cystep),
        .o_til_cklim        (ob_til_cklim),
        .o_til_ckstep	    (ob_til_ckstep),

        .o_doneintr         (o_doneintr),
        .o_data_out	        (o_data_out));

// Main Controller
main_controller #(
        .X                  (sauria_pkg::X),
        .Y                  (sauria_pkg::Y),
        .ACT_IDX_W          (ACT_IDX_W),
        .OUT_IDX_W          (OUT_IDX_W),
        .ACT_FIFO_POSITIONS (sauria_pkg::ACT_FIFO_POSITIONS),
        .WEI_FIFO_POSITIONS (sauria_pkg::WEI_FIFO_POSITIONS),
        .PE_LAT             (PE_LAT),
        .EXTRA_CSREG        (sauria_pkg::EXTRA_CSREG)
    ) main_controller_i
       (.i_clk              (i_clk),
        .i_rstn             (i_rstn),
        .i_soft_reset       (soft_reset),
        
        .i_start	        (mc_start),
        .i_outbuf_done      (mc_outbuf_done),
        .i_shift_done       (mc_shift_done),
        .i_finalwrite       (mc_finalwrite),
        .i_incntlim	        (mc_incntlim),
        .i_act_reps         (mc_act_reps),
        .i_wei_reps         (mc_wei_reps),
        .i_act_done         (mc_act_done),
        .i_act_til_done     (mc_act_til_done),
        .i_act_fifo_empty   (mc_act_fifo_empty),
        .i_act_fifo_full    (mc_act_fifo_full),
        .i_act_stall        (mc_act_stall),
        .i_wei_done         (mc_wei_done),
        .i_wei_til_done     (mc_wei_til_done),
        .i_wei_fifo_empty   (mc_wei_fifo_empty),
        .i_wei_fifo_full    (mc_wei_fifo_full),
        .i_wei_stall        (mc_wei_stall),

        .o_outbuf_start     (ob_outbuf_start),
        .o_outbuf_reset	    (ob_outbuf_reset),
        .o_cswitch_arr	    (sa_cswitch_arr),
        .o_act_feeder_en    (af_act_feeder_en),
        .o_act_feeder_clear (af_act_feeder_clear),
        .o_act_valid        (af_act_valid),
        .o_act_start	    (af_act_start),
        .o_act_finalpush	(af_act_finalpush),
        .o_act_cnt_en       (af_act_cnt_en),
        .o_act_cnt_clear    (af_act_cnt_clear),
        .o_act_clearfifo	(af_act_clearfifo),
        .o_act_pop_en	    (af_act_pop_en),
        .o_act_finalctx     (af_act_finalctx),
        .o_wei_feeder_en    (wf_wei_feeder_en),
        .o_wei_feeder_clear (wf_wei_feeder_clear),
        .o_wei_valid        (wf_wei_valid),
        .o_wei_start	    (wf_wei_start),
        .o_wei_finalpush	(wf_wei_finalpush),
        .o_wei_cnt_en       (wf_wei_cnt_en),
        .o_wei_cnt_clear    (wf_wei_cnt_clear),
        .o_wei_clearfifo	(wf_wei_clearfifo),
        .o_wei_pop_en	    (wf_wei_pop_en),
        .o_wei_cswitch      (wf_wei_cswitch),
        .o_sa_clear         (sa_reg_clear),
        .o_pipeline_en      (sa_pipeline_en),
        .o_feed_deadlock    (cg_feed_deadlock),
        .o_ctx_status       (cg_ctx_status),
        .o_feed_status      (cg_feed_status),
        .o_done             (cg_done));

// Activation Feeder
ifmap_feeder #(
        .Y              (sauria_pkg::Y),
        .FIFO_POSITIONS (sauria_pkg::ACT_FIFO_POSITIONS),
        .IA_W           (sauria_pkg::IA_W),
        .SRAMA_W        (SRAMA_W),
        .IDX_W          (ACT_IDX_W),
        .ADRA_W         (ADRA_W),
        .DILP_W         (sauria_pkg::DILP_W),
        .PARAMS_W       (sauria_pkg::PARAMS_W),
        .M              (sauria_pkg::M)
    ) ifmap_feeder_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_srama_data   (i_srama_data),
        .i_cnt_en	    (af_act_cnt_en),
        .i_cnt_clear    (af_act_cnt_clear | soft_reset),
        .i_finalctx     (af_act_finalctx),
        .i_rows_active  (af_rows_active),
        .i_xlim	        (af_xlim),
        .i_xstep        (af_xstep),
        .i_ylim         (af_ylim),
        .i_ystep        (af_ystep),
        .i_chlim        (af_chlim),
        .i_chstep       (af_chstep),
        .i_til_xlim	    (af_til_xlim),
        .i_til_xstep    (af_til_xstep),
        .i_til_ylim     (af_til_ylim),
        .i_til_ystep    (af_til_ystep),

        .i_feeder_en    (af_act_feeder_en),
        .i_feeder_clear (af_act_feeder_clear | soft_reset),
        .i_act_valid    (af_act_valid),
        .i_start        (af_act_start),
        .i_finalpush    (af_act_finalpush),
        .i_loc_woffs    (af_loc_woffs),
        .i_Dil_pat      (af_Dil_pat),
        .i_clearfifo    (af_act_clearfifo | soft_reset),
        .i_pipeline_en  (sa_pipeline_en),
        .i_pop_en       (af_act_pop_en),

        .o_act_deadlock (cg_act_deadlock),

        .o_done         (mc_act_done),
        .o_til_done     (mc_act_til_done),
        .o_fifo_empty   (mc_act_fifo_empty),
        .o_fifo_full    (mc_act_fifo_full),
        .o_feeder_stall (mc_act_stall),
        .o_srama_addr   (o_srama_addr),
        .o_srama_rden   (o_srama_rden),
        .o_a_arr	    (sa_a_arr));

// Weight Feeder
wei_feeder #(
        .X              (sauria_pkg::X),
        .FIFO_POSITIONS (sauria_pkg::WEI_FIFO_POSITIONS),
        .IB_W           (sauria_pkg::IB_W),
        .SRAMB_W        (SRAMB_W),
        .IDX_W          (WEI_IDX_W),
        .ADRB_W         (ADRB_W),
        .PARAMS_W       (sauria_pkg::PARAMS_W)
    ) weight_feeder_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_sramb_data   (i_sramb_data),
        .i_cnt_en	    (wf_wei_cnt_en),
        .i_cnt_clear    (wf_wei_cnt_clear | soft_reset),
        .i_cols_active  (wf_cols_active),
        .i_cswitch      (wf_wei_cswitch),
        .i_waligned     (wf_waligned),
        .i_auxlim       (wf_auxlim),
        .i_auxstep      (wf_auxstep),
        .i_wlim	        (wf_wlim),
        .i_wstep        (wf_wstep),
        .i_til_klim     (wf_til_klim),
        .i_til_kstep    (wf_til_kstep),
        .i_feeder_en    (wf_wei_feeder_en),
        .i_feeder_clear (wf_wei_feeder_clear | soft_reset),
        .i_wei_valid    (wf_wei_valid),
        .i_finalpush    (wf_wei_finalpush),
        .i_clearfifo    (wf_wei_clearfifo | soft_reset),
        .i_pipeline_en  (sa_pipeline_en),
        .i_pop_en       (wf_wei_pop_en),

        .o_wei_deadlock (cg_wei_deadlock),

        .o_done         (mc_wei_done),
        .o_til_done     (mc_wei_til_done),
        .o_fifo_empty   (mc_wei_fifo_empty),
        .o_fifo_full    (mc_wei_fifo_full),
        .o_feeder_stall (mc_wei_stall),
        .o_sramb_addr   (o_sramb_addr),
        .o_sramb_rden   (o_sramb_rden),
        .o_b_arr	    (sa_b_arr));

// Output Buffer
psm_top #(
        .X          (sauria_pkg::X),
        .Y          (sauria_pkg::Y),
        .PARAMS_W   (sauria_pkg::PARAMS_W),
        .OC_W       (sauria_pkg::OC_W),
        .SRAMC_W    (SRAMC_W),
        .IDX_W      (OUT_IDX_W),
        .ADRC_W     (ADRC_W)
    ) psm_top_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_sramc_rdata  (i_sramc_rdata),
        .i_c_arr        (ob_c_arr),
        .i_cxlim	    (ob_cxlim),
        .i_cxstep       (ob_cxstep),
        .i_cklim        (ob_cklim),
        .i_ckstep       (ob_ckstep),
        .i_til_cylim	(ob_til_cylim),
        .i_til_cystep   (ob_til_cystep),
        .i_til_cklim	(ob_til_cklim),
        .i_til_ckstep   (ob_til_ckstep),
        .i_ncontexts	(ob_ncontexts),
        .i_preload_en   (ob_preload_en),
        .i_inactive_cols(ob_inactive_cols),
        .i_rows_active  (af_rows_active),
        .i_fsm_start    (ob_outbuf_start),
        .i_fsm_reset    (ob_outbuf_reset | soft_reset),
        .i_pipeline_en  (sa_pipeline_en),

        .o_done         (mc_outbuf_done),
        .o_out_status   (cg_out_status),
        .o_shift_done   (mc_shift_done),
        .o_finalwrite   (mc_finalwrite),
        .o_cscan_en     (sa_cscan_en),
        .o_sramc_addr   (o_sramc_addr),
        .o_sramc_rden   (o_sramc_rden),
        .o_sramc_wren   (o_sramc_wren),
        .o_sramc_wmask  (o_sramc_wmask),
        .o_sramc_wdata  (o_sramc_wdata),
        .o_c_arr	    (sa_c_arr));

// Systolic Array
sa_array #(
        .X                              (sauria_pkg::X),
        .Y                              (sauria_pkg::Y),
        .ARITHMETIC                     (sauria_pkg::ARITHMETIC),
        .MUL_TYPE                       (sauria_pkg::MUL_TYPE),
        .M_APPROX                       (sauria_pkg::M_APPROX),
        .MM_APPROX                      (sauria_pkg::MM_APPROX),
        .ADD_TYPE                       (sauria_pkg::ADD_TYPE),
        .A_APPROX                       (sauria_pkg::A_APPROX),
        .AA_APPROX                      (sauria_pkg::AA_APPROX),
        .STAGES_MUL                     (sauria_pkg::STAGES_MUL),
        .INTERMEDIATE_PIPELINE_STAGE    (sauria_pkg::INTERMEDIATE_PIPELINE_STAGE),
        .ZERO_GATING_MULT               (sauria_pkg::ZERO_GATING_MULT),
        .ZERO_GATING_ADD                (sauria_pkg::ZERO_GATING_ADD),
        .ZD_LOOKAHEAD                   (sauria_pkg::ZD_LOOKAHEAD),
        .EXTRA_CSREG                    (sauria_pkg::EXTRA_CSREG),
        .IA_W                           (sauria_pkg::IA_W),
        .IB_W                           (sauria_pkg::IB_W),
        .OC_W                           (sauria_pkg::OC_W),
        .TH_W                           (sauria_pkg::TH_W)
    ) sa_array_i
       (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_a_arr        (sa_a_arr),
        .i_b_arr        (sa_b_arr),
        .i_c_arr	    (sa_c_arr),
        .i_reg_clear    (sa_reg_clear | soft_reset),
        .i_pipeline_en  (sa_pipeline_en),
        .i_cswitch_arr  (sa_cswitch_arr),
        .i_cscan_en     (sa_cscan_en),
        .i_thres	    (sa_thres),

        .o_c_arr	    (ob_c_arr));

endmodule 
