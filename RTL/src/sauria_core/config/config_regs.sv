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

// ----------
// MACROS
// ----------

// --------------------
// MODULE DECLARATION
// --------------------

module config_regs #(
    parameter IF_W = 32,
    parameter IF_ADR_W = 32,
    parameter X = 8,
    parameter Y = 8,
    parameter TH_W = 2,
    parameter ACT_IDX_W = 15,
    parameter WEI_IDX_W = 15,
    parameter OUT_IDX_W = 15,
    parameter PARAMS_W = 8,
    parameter DILP_W = 64,
    parameter SRAMB_N = 8
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

	// Data Inputs
    input  logic [IF_W-1:0]             i_data_in,          // Accelerator interface input data bus
	
	// Control Inputs
    input  logic [IF_ADR_W-1:0]         i_address,          // Accelerator interface address
    input  logic                        i_wren,             // Accelerator interface write enable
    input  logic                        i_rden,             // Accelerator interface read enable
    input  logic [IF_W-1:0]             i_wmask,           // Accelerator interface write mask bus

    // Status Inputs
    input  logic                        i_done,             // Main Controller done flag => End of a convolution
    input  logic                        i_act_deadlock,     // Activation feeders deadlock flag
    input  logic                        i_wei_deadlock,     // Weight feeders deadlock flag
    input  logic                        i_feed_deadlock,    // Semi-deadlock flag between feeders (not blocking per se)
    input  logic [4:0]                  i_ctx_status,       // Context FSM status code
    input  logic [4:0]                  i_feed_status,      // Feeders FSM status code
    input  logic [4:0]                  i_out_status,       // Output scan FSM status code
    input  logic                        i_pipeline_en,      // Array Pipeline Enable
    input  logic                        i_pop_en,           // Feeders Pop Enable

    // Control Outputs
    output logic                        o_start,            // Main Controller start flag => Starts a convolution

    // Soft-Reset signal
    output logic                        o_soft_reset,       // Soft reset signal to restart all FSMs

    // Global SRAM signals
    output logic [0:2]                  o_sram_select,      // Double-buffering SRAM selection
    output logic                        o_sram_deepsleep,   // DeepSleep control for all SRAMs
    output logic                        o_sram_powergate,   // Power gate control for all SRAMs

	// Configuration Outputs (CONTROL FSM)
    output logic [ACT_IDX_W-1:0]        o_incntlim,         // Input counter limit
    output logic [OUT_IDX_W-1:0]        o_act_reps,         // Total activation data repetitions
    output logic [OUT_IDX_W-1:0]        o_wei_reps,         // Total weight data repetitions

    // Configuration Outputs (Systolic Array)
    output logic [TH_W-1:0]             o_thres,            // Threshold for bit negligence in zero detection

	// Configuration Outputs (ACTIVATION FEEDER)
    output logic [0:Y-1]		        o_rows_active,      // Active Rows configuration
    output logic [ACT_IDX_W-1:0]		o_xlim,             // Idx Counters : X counter limit
    output logic [ACT_IDX_W-1:0]		o_xstep,            // Idx Counters : X counter step size
    output logic [ACT_IDX_W-1:0]		o_ylim,             // Idx Counters : Y counter limit
    output logic [ACT_IDX_W-1:0]		o_ystep,            // Idx Counters : Y counter step size
    output logic [ACT_IDX_W-1:0]		o_chlim,            // Idx Counters : In-Channel counter limit
    output logic [ACT_IDX_W-1:0]		o_chstep,           // Idx Counters : In-Channel counter step size
    output logic [ACT_IDX_W-1:0]		o_til_xlim,         // Idx Counters : Tiling x counter limit
    output logic [ACT_IDX_W-1:0]		o_til_xstep,        // Idx Counters : Tiling x counter step size
    output logic [ACT_IDX_W-1:0]		o_til_ylim,         // Idx Counters : Tiling y counter limit
    output logic [ACT_IDX_W-1:0]		o_til_ystep,        // Idx Counters : Tiling y counter step size
    output logic [0:Y-1][PARAMS_W-1:0]  o_loc_woffs,        // Local word offset array (encodes strides)
    output logic [0:DILP_W-1]	        o_Dil_pat,          // Dilation pattern (encodes dilation coeff.)

	// Configuration Outputs (WEIGHT FEEDER)
    output logic [0:X-1]		        o_cols_active,      // Active Columns configuration
    output logic                        o_waligned,         // Bit that indicates if weight values are aligned in memory (better perf.)
    output logic [WEI_IDX_W-1:0]		o_auxlim,           // Idx Counters : Auxiliary counter limit
    output logic [WEI_IDX_W-1:0]		o_auxstep,          // Idx Counters : Auxiliary counter step size
    output logic [WEI_IDX_W-1:0]		o_wlim,             // Idx Counters : Weight counter limit
    output logic [WEI_IDX_W-1:0]		o_wstep,            // Idx Counters : Weight counter step size
    output logic [WEI_IDX_W-1:0]		o_til_klim,         // Idx Counters : Tiling Out-Channel counter limit
    output logic [WEI_IDX_W-1:0]		o_til_kstep,        // Idx Counters : Tiling Out-Channel counter step

	// Configuration Outputs (OUTPUT BUFFER)
    output logic            		    o_preload_en,       // Output (psum) value preload enable
    output logic [PARAMS_W-1:0]		    o_inactive_cols,    // Number of inactive columns
    output logic [OUT_IDX_W-1:0]		o_ncontexts,        // Total number of contexts to compute
    output logic [OUT_IDX_W-1:0]		o_cxlim,            // Idx Counters : X counter limit
    output logic [OUT_IDX_W-1:0]		o_cxstep,           // Idx Counters : X counter step size
    output logic [OUT_IDX_W-1:0]		o_cklim,            // Idx Counters : Out-Channel counter limit
    output logic [OUT_IDX_W-1:0]		o_ckstep,           // Idx Counters : Out-Channel counter step size
    output logic [OUT_IDX_W-1:0]		o_til_cylim,        // Idx Counters : Tiling X-Y counter limit
    output logic [OUT_IDX_W-1:0]		o_til_cystep,       // Idx Counters : Tiling X-Y counter step size
    output logic [OUT_IDX_W-1:0]		o_til_cklim,        // Idx Counters : Tiling Out-Channel counter limit
    output logic [OUT_IDX_W-1:0]		o_til_ckstep,       // Idx Counters : Tiling Out-Channel counter step size

    // Done Interrupt
    output logic                        o_doneintr,         // Completion interrupt towards host

    // Data Outputs
	output logic [IF_W-1:0]             o_data_out          // Accelerator interface output data bus

);

// ---------------------------------------------------------------------------
// SIGNALS
// ---------------------------------------------------------------------------

localparam IF_LSB_BITS = $clog2(IF_W/8);
localparam SUB_ADR_W = 8;

// Registers bitcount
localparam real TOTAL_BITS_CON =         ACT_IDX_W + 2*OUT_IDX_W + TH_W + 2;
localparam real TOTAL_BITS_ACT =         Y + DILP_W + 10*ACT_IDX_W + Y*PARAMS_W;
localparam real TOTAL_BITS_WEI =         X + 6*WEI_IDX_W + 1;
localparam real TOTAL_BITS_OUT =         1 + PARAMS_W + 9*OUT_IDX_W;

// Register count
localparam int TOTAL_REGS_CON =         $ceil(TOTAL_BITS_CON/IF_W);
localparam int TOTAL_REGS_ACT =         $ceil(TOTAL_BITS_ACT/IF_W);
localparam int TOTAL_REGS_WEI =         $ceil(TOTAL_BITS_WEI/IF_W);
localparam int TOTAL_REGS_OUT =         $ceil(TOTAL_BITS_OUT/IF_W);

// Offset regions
localparam logic [3:0] CON_OFFSET = 4'b001;
localparam logic [3:0] ACT_OFFSET = 4'b010;
localparam logic [3:0] WEI_OFFSET = 4'b011;
localparam logic [3:0] OUT_OFFSET = 4'b100;

// Addressing index
logic [SUB_ADR_W-1:0]       addressing_idx;

// Main registers
logic [0:TOTAL_REGS_CON-1][IF_W-1:0]    reg_con_q, reg_con_q2, reg_con_d, reg_con_mux;
logic [0:TOTAL_REGS_ACT-1][IF_W-1:0]    reg_act_q, reg_act_q2, reg_act_d, reg_act_mux;
logic [0:TOTAL_REGS_WEI-1][IF_W-1:0]    reg_wei_q, reg_wei_q2, reg_wei_d, reg_wei_mux;
logic [0:TOTAL_REGS_OUT-1][IF_W-1:0]    reg_out_q, reg_out_q2, reg_out_d, reg_out_mux;

// Default values of main registers
logic [0:TOTAL_REGS_CON-1][IF_W-1:0]    reg_con_default;
logic [0:TOTAL_REGS_ACT-1][IF_W-1:0]    reg_act_default;
logic [0:TOTAL_REGS_WEI-1][IF_W-1:0]    reg_wei_default;
logic [0:TOTAL_REGS_OUT-1][IF_W-1:0]    reg_out_default;

// Unpacked arrays to load values from memory
logic [IF_W-1:0] reg_con_file [0:TOTAL_REGS_CON-1];
logic [IF_W-1:0] reg_act_file [0:TOTAL_REGS_ACT-1];
logic [IF_W-1:0] reg_wei_file [0:TOTAL_REGS_WEI-1];
logic [IF_W-1:0] reg_out_file [0:TOTAL_REGS_OUT-1];

// Special registers
logic start_q, start_q_prv, start_d;
logic done_q, done_d;
logic idle_q, idle_d;
logic ready_q, ready_d;
logic auto_restart_d, auto_restart_q;
logic mem_switch_q, mem_switch_q_prv, mem_switch_d;
logic mem_keep_A_d, mem_keep_A_q;
logic mem_keep_B_d, mem_keep_B_q;
logic mem_keep_C_d, mem_keep_C_q;
logic global_ien_d, global_ien_q;
logic done_ien_d, done_ien_q;
logic done_intr_d, done_intr_q;
logic soft_rst_d, soft_rst_q, soft_rst_q_prv;

// Cycle counters (RD only)
logic [IF_W-1:0] cycle_cnt_q, cycle_cnt_d;
logic [IF_W-1:0] stalls_cnt_q, stalls_cnt_d;
logic count_enable_q, count_enable_d;

// Status registers (RD only)
logic [IF_W-1:0] status_q, status_d;

// Actual Write and Read Enables
logic wren, rden;

// Output data register
logic [IF_W-1:0] out_databuf_d, out_databuf_q;

// Edge flags
logic start_edge, done_edge, mem_switch_edge, soft_rst_edge;

// SRAM select signal
logic [0:2] sram_select_q, sram_select_d;

// Big Endian signals for mapping
logic [DILP_W-1:0] Dil_pat_BE;
logic [Y-1:0] rows_active_BE;
logic [X-1:0] cols_active_BE;

// Mapped as BE, output is LE
assign o_Dil_pat = Dil_pat_BE;
assign o_rows_active = rows_active_BE;
assign o_cols_active = cols_active_BE;

// ---------------------------------------------------------------------------
// REGISTERS DEFAULT VALUES
// ---------------------------------------------------------------------------

// // Read default values from files
// always_comb begin
//     $readmemh("conf_default/reg_con.txt", reg_con_file);
//     $readmemh("conf_default/reg_act.txt", reg_act_file);
//     $readmemh("conf_default/reg_wei.txt", reg_wei_file);
//     $readmemh("conf_default/reg_out.txt", reg_out_file);   
// end

// Assign values to wires
genvar i_con;
    generate
        for (i_con=0; i_con < TOTAL_REGS_CON; i_con++) begin
			assign reg_con_default[i_con] = reg_con_file[i_con];
        end
    endgenerate
genvar i_act;
    generate
        for (i_act=0; i_act < TOTAL_REGS_ACT; i_act++) begin
			assign reg_act_default[i_act] = reg_act_file[i_act];
        end
    endgenerate
genvar i_wei;
    generate
        for (i_wei=0; i_wei < TOTAL_REGS_WEI; i_wei++) begin
			assign reg_wei_default[i_wei] = reg_wei_file[i_wei];
        end
    endgenerate
genvar i_out;
    generate
        for (i_out=0; i_out < TOTAL_REGS_OUT; i_out++) begin
			assign reg_out_default[i_out] = reg_out_file[i_out];
        end
    endgenerate

// ---------------------------------------------------------------------------
// REGISTERS INSTANTIATION
// ---------------------------------------------------------------------------

// Start edge detection
assign start_edge = start_q & (!start_q_prv);

always_ff @(posedge i_clk or negedge i_rstn) begin : registers
    if(~i_rstn) begin
        start_q <= 0;
        start_q_prv <= 0;
        idle_q <= 1;
        ready_q <= 1;
        mem_switch_q <= 0;
        mem_switch_q_prv <= 0;
        mem_keep_A_q <= 0;
        mem_keep_B_q <= 0;
        mem_keep_C_q <= 0;
        auto_restart_q <= 0;
        done_q <= 0;
        soft_rst_q <= 0;
        soft_rst_q_prv <= 0;
        status_q <= 0;
        global_ien_q <= 0;
        done_ien_q <= 0;
        done_intr_q <= 0;
        reg_con_q <= 0;
        reg_act_q <= 0;
        reg_wei_q <= 0;
        reg_out_q <= 0;
        reg_con_q2 <= 0;
        reg_act_q2 <= 0;
        reg_wei_q2 <= 0;
        reg_out_q2 <= 0;
    end else begin

        // Primary registers immediately get the write data
        start_q <= start_d;
        start_q_prv <= start_q;
        idle_q <= idle_d;
        ready_q <= ready_d;
        mem_switch_q <= mem_switch_d;
        mem_switch_q_prv <= mem_switch_q;
        mem_keep_A_q <= mem_keep_A_d;
        mem_keep_B_q <= mem_keep_B_d;
        mem_keep_C_q <= mem_keep_C_d;
        auto_restart_q <= auto_restart_d;
        done_q <= done_d;
        soft_rst_q <= soft_rst_d;
        soft_rst_q_prv <= soft_rst_q;
        status_q <= status_d;
        global_ien_q <= global_ien_d;
        done_ien_q <= done_ien_d;
        done_intr_q <= done_intr_d;
        reg_con_q <= reg_con_d;
        reg_act_q <= reg_act_d;
        reg_wei_q <= reg_wei_d;
        reg_out_q <= reg_out_d;

        // Secondary registers hold the previous data and are only updated on rising edge of start
        if (start_edge & ready_q) begin
            reg_con_q2 <= reg_con_q;
            reg_act_q2 <= reg_act_q;
            reg_wei_q2 <= reg_wei_q;
            reg_out_q2 <= reg_out_q;
        end
    end
end

assign reg_con_mux = reg_con_q2;
assign reg_act_mux = reg_act_q2;
assign reg_wei_mux = reg_wei_q2;
assign reg_out_mux = reg_out_q2;

// ---------------------------------------------------------------------------
// SRAM Double Buffering Control
// ---------------------------------------------------------------------------

// Memory switch edge detection
assign mem_switch_edge = mem_switch_q & (!mem_switch_q_prv);

// SRAM select signal is inverted every start edge or mem_switch edge, if enabled

// SRAMA
assign sram_select_d[0] =   ((!mem_keep_A_q) &
                            ((start_edge & ready_q) | mem_switch_edge))?  (!sram_select_q[0]) : sram_select_q[0];

// SRAMB
assign sram_select_d[1] =   ((!mem_keep_B_q) &
                            ((start_edge & ready_q) | mem_switch_edge))?  (!sram_select_q[1]) : sram_select_q[1];

// SRAMC
assign sram_select_d[2] =   ((!mem_keep_C_q) &
                            ((start_edge & ready_q) | mem_switch_edge))?  (!sram_select_q[2]) : sram_select_q[2];

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : sram_sel_reg
    if(~i_rstn) begin
        sram_select_q <= '0;
    end else begin
        sram_select_q <= sram_select_d;
    end
end

assign o_sram_select = sram_select_q;

// ---------------------------------------------------------------------------
// Address breakdown
// ---------------------------------------------------------------------------

always_comb begin
    
    // Index
    addressing_idx = i_address[SUB_ADR_W-1:IF_LSB_BITS];

    // If not selected, writes and reads are disabled
    if ((i_address & sauria_addr_pkg::SAURIA_MEM_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) begin
        wren = i_wren;
        rden = i_rden;
    end else begin
        wren = 1'b0;
        rden = 1'b0;
    end

end

// ---------------------------------------------------------------------------
// Counters
// ---------------------------------------------------------------------------

always_comb begin
    
    done_edge = done_d & (!done_q);

    cycle_cnt_d = cycle_cnt_q;
    stalls_cnt_d = stalls_cnt_q;
    count_enable_d = count_enable_q;

    // A start_edge will reset the counters and raise the count enable signal
    if (start_edge & ready_q) begin
        count_enable_d = 1;
        cycle_cnt_d = 0;
        stalls_cnt_d = 0;

    // A done_edge will disable counting but counters will retain their values
    end else if (done_edge) begin
        count_enable_d = 0;
    end

    // Counters logic
    if (count_enable_q) begin
        
        // Cycle counter unconditionally counts => Total number of cycles
        cycle_cnt_d = cycle_cnt_q + 1;

        // Stall counter only active when conditions for a hard (pipeline) or soft (pop) stall are met
        if ( (!i_pipeline_en) || (!i_pop_en) ) begin
            stalls_cnt_d = stalls_cnt_q + 1;
        end
    end
end

// Registers
always_ff @(posedge i_clk or negedge i_rstn) begin : cnt_reg
    if(~i_rstn) begin
        cycle_cnt_q <= 0;
        stalls_cnt_q <= 0;
        count_enable_q <= 0;
    end else begin
        cycle_cnt_q <= cycle_cnt_d;
        stalls_cnt_q <= stalls_cnt_d;
        count_enable_q <= count_enable_d;
    end
end

// ---------------------------------------------------------------------------
// Register Write Access
// ---------------------------------------------------------------------------

always_comb begin

    // Values maintained if unaddressed
    start_d = start_q;
    done_d = done_q;
    auto_restart_d = auto_restart_q;
    mem_switch_d = mem_switch_q;
    mem_keep_A_d = mem_keep_A_q;
    mem_keep_B_d = mem_keep_B_q;
    mem_keep_C_d = mem_keep_C_q;

    global_ien_d = global_ien_q;
    done_ien_d = done_ien_q;
    done_intr_d = done_intr_q;
    soft_rst_d = soft_rst_q;

    reg_con_d = reg_con_q;
    reg_act_d = reg_act_q;
    reg_wei_d = reg_wei_q;
    reg_out_d = reg_out_q;

    // Start is auto-deasserted
    if (start_q) begin
        start_d = 1'b0;
    end

    // Memory switch is auto-deasserted
    if (mem_switch_q) begin
        mem_switch_d = 1'b0;
    end

    // Soft reset is auto-deasserted
    if (soft_rst_q) begin
        soft_rst_d = 1'b0;
    end

    // Status values are also RD only
    status_d = '0;       // Unused positions tied to zero
    status_d[0] =       i_act_deadlock;
    status_d[1] =       i_wei_deadlock;
    status_d[2] =       i_feed_deadlock;
    status_d[7:3] =     i_ctx_status;
    status_d[12:8] =    i_feed_status;
    status_d[17:13] =   i_out_status;

    // Write only if Write Enable
    if (wren) begin

        // Write Mask => Individually control changes on each bit
        for (integer bb=0; bb<IF_W; bb++) begin
            if (i_wmask[bb]) begin

                // *************************************************
                // Control signals (Index = 0x0 [Addr = 0x000000])
                // *************************************************

                if      (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                        (i_address[SUB_ADR_W-1:0] == 8'h0)) begin

                    if (bb==0)      start_d         = i_data_in[bb];
                    if (bb==1)      done_d          = done_q & (~i_data_in[bb]);    // COW
                    if (bb==7)      auto_restart_d  = i_data_in[bb];
                    if (bb==16)     mem_switch_d    = i_data_in[bb];
                    if (bb==17)     mem_keep_A_d    = i_data_in[bb];
                    if (bb==18)     mem_keep_B_d    = i_data_in[bb];
                    if (bb==19)     mem_keep_C_d    = i_data_in[bb];
                    if (bb==23)     soft_rst_d      = i_data_in[bb];

                end

                // ********************************************************
                // Global Interrupt Enable (Index = 0x1 [Addr = 0x000004])
                // ********************************************************

                else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                        (i_address[SUB_ADR_W-1:0] == 8'h4)) begin

                    if (bb==0)      global_ien_d    = i_data_in[bb];

                end

                // ****************************************************
                // IP Interrupt Enable (Index = 0x2 [Addr = 0x000008])
                // ****************************************************

                else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                        (i_address[SUB_ADR_W-1:0] == 8'h8)) begin

                    if (bb==0)      done_ien_d      = i_data_in[bb];

                end

                // ****************************************************
                // IP Interrupt Status (Index = 0x3 [Addr = 0x00000C])
                // ****************************************************

                else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                        (i_address[SUB_ADR_W-1:0] == 8'hC)) begin

                    if (bb==0)      done_intr_d      = done_intr_q & (~i_data_in[bb]); // COW

                end

                // *********************************************
                // Control Config region (Offset = CON_OFFSET)
                // *********************************************

                else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_CON_OFFSET) begin
                    reg_con_d[addressing_idx][bb] = i_data_in[bb];
                end

                // ***********************************************
                // Activation config region (Offset = ACT_OFFSET)
                // ***********************************************

                else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_ACT_OFFSET) begin
                    reg_act_d[addressing_idx][bb] = i_data_in[bb];
                end

                // ********************************************
                // Weight config region (Offset = WEI_OFFSET)
                // ********************************************

                else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_WEI_OFFSET) begin
                    reg_wei_d[addressing_idx][bb] = i_data_in[bb];
                end

                // ********************************************
                // Output config region (Offset = OUT_OFFSET)
                // ********************************************

                else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_OUT_OFFSET) begin
                    reg_out_d[addressing_idx][bb] = i_data_in[bb];
                end
            end
        end
    end

    // Idle and ready are the same as HW done
    idle_d = i_done;
    ready_d = i_done;

    // Set Done and done_intr_d if HW done flag is raised
    if (idle_d && (!idle_q)) begin
        done_d = 1'b1;
        done_intr_d = 1'b1;
    end

end

// ---------------------------------------------------------------------------
// Register Read Access
// ---------------------------------------------------------------------------

always_comb begin

    // Output data defaults to "bad address 3"
    out_databuf_d = 32'h2BADADD2;

    // Only when rden we take the values out
    if (rden) begin

        // *************************************************
        // Control signals (Index = 0x0 [Addr = 0x000000])
        // *************************************************

        if      (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'h0)) begin

            out_databuf_d = '0;
            out_databuf_d[0] =  start_q;
            out_databuf_d[1] =  done_q;
            out_databuf_d[2] =  idle_q;
            out_databuf_d[3] =  ready_q;
            out_databuf_d[7] =  auto_restart_q;
            out_databuf_d[16] = mem_switch_q;
            out_databuf_d[17] = mem_keep_A_q;
            out_databuf_d[18] = mem_keep_B_q;
            out_databuf_d[19] = mem_keep_C_q;
            out_databuf_d[23] = soft_rst_q;
            out_databuf_d[31:24] = 8'hAC;
        end

        // ********************************************************
        // Global Interrupt Enable (Index = 0x1 [Addr = 0x000004])
        // ********************************************************

        else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'h4)) begin

            out_databuf_d = '0;
            out_databuf_d[0] = global_ien_q;
        end

        // ****************************************************
        // IP Interrupt Enable (Index = 0x2 [Addr = 0x000008])
        // ****************************************************

        else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'h8)) begin

            out_databuf_d = '0;
            out_databuf_d[0] = done_ien_q;
        end

        // ****************************************************
        // IP Interrupt Status (Index = 0x3 [Addr = 0x00000C])
        // ****************************************************

        else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'hC)) begin

            out_databuf_d = '0;
            out_databuf_d[0] = done_intr_q;
        end

        // *************************************************
        // Status flags (Index = 0x4 [Addr = 0x000010])
        // *************************************************

        else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'h10)) begin

            out_databuf_d = status_q;
        end

        // *************************************************
        // Cycle Counter (Index = 0x5 [Addr = 0x000014])
        // *************************************************

        else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'h14)) begin

            out_databuf_d = cycle_cnt_q;
        end

        // *************************************************
        // Stalls Counter (Index = 0x6 [Addr = 0x000018])
        // *************************************************

        else if (((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_REGS_OFFSET) &&
                (i_address[SUB_ADR_W-1:0] == 8'h18)) begin

            out_databuf_d = stalls_cnt_q;
        end

        // *********************************************
        // Control Config region (Offset = CON_OFFSET)
        // *********************************************

        else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_CON_OFFSET) begin
            if (addressing_idx<TOTAL_REGS_CON) begin
                out_databuf_d = reg_con_q[addressing_idx];
            end
        end

        // ***********************************************
        // Activation config region (Offset = ACT_OFFSET)
        // ***********************************************

        else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_ACT_OFFSET) begin
            if (addressing_idx<TOTAL_REGS_ACT) begin
                out_databuf_d = reg_act_q[addressing_idx];
            end
        end

        // ********************************************
        // Weight config region (Offset = WEI_OFFSET)
        // ********************************************

        else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_WEI_OFFSET) begin
            if (addressing_idx<TOTAL_REGS_WEI) begin
                out_databuf_d = reg_wei_q[addressing_idx];
            end
        end

        // ********************************************
        // Output config region (Offset = OUT_OFFSET)
        // ********************************************

        else if ((i_address & sauria_addr_pkg::SAURIA_REG_ADDR_MASK)==sauria_addr_pkg::CFG_OUT_OFFSET) begin
            if (addressing_idx<TOTAL_REGS_OUT) begin
                out_databuf_d = reg_out_q[addressing_idx];
            end
        end
    end
end

// ------------------------------------------------------------------------------------------
// Output signals mapping => Generated automatically with python (config_regs_gen.py)
// ------------------------------------------------------------------------------------------

always_comb begin

	// Start flag is high after a start posedge
	o_start = start_edge;

	// ***************************************************
	// Control config region
	// ***************************************************

    for (integer b=0; b<TOTAL_BITS_CON; b++) begin
        if (b<ACT_IDX_W) begin
            o_incntlim[b] =                             reg_con_mux[b/IF_W][b%IF_W];

        end else if (b<ACT_IDX_W + OUT_IDX_W) begin
            o_act_reps[b-ACT_IDX_W] =                   reg_con_mux[b/IF_W][b%IF_W];

        end else if (b<ACT_IDX_W + 2*OUT_IDX_W) begin
            o_wei_reps[b-(ACT_IDX_W + OUT_IDX_W)] =     reg_con_mux[b/IF_W][b%IF_W];

        end else if (b<ACT_IDX_W + 2*OUT_IDX_W + TH_W) begin
            o_thres[b-(ACT_IDX_W + 2*OUT_IDX_W)] =      reg_con_mux[b/IF_W][b%IF_W];

        end else if (b<ACT_IDX_W + 2*OUT_IDX_W + TH_W + 1) begin
            o_sram_deepsleep =                          reg_con_mux[b/IF_W][b%IF_W];

        end else begin
            o_sram_powergate =                          reg_con_mux[b/IF_W][b%IF_W];
        end
    end

	// ***************************************************
	// Activation config region
	// ***************************************************

    for (integer b=0; b<TOTAL_BITS_ACT; b++) begin
        if (b<ACT_IDX_W) begin
            o_xlim[b] = 				                reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<2*ACT_IDX_W) begin
            o_xstep[b-ACT_IDX_W] = 				        reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<3*ACT_IDX_W) begin
            o_ylim[b-(2*ACT_IDX_W)] = 				    reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<4*ACT_IDX_W) begin
            o_ystep[b-(3*ACT_IDX_W)] = 				    reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<5*ACT_IDX_W) begin
            o_chlim[b-(4*ACT_IDX_W)] = 				    reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<6*ACT_IDX_W) begin
            o_chstep[b-(5*ACT_IDX_W)] = 				reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<7*ACT_IDX_W) begin
            o_til_xlim[b-(6*ACT_IDX_W)] = 			    reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<8*ACT_IDX_W) begin
            o_til_xstep[b-(7*ACT_IDX_W)] = 				reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<9*ACT_IDX_W) begin
            o_til_ylim[b-(8*ACT_IDX_W)] = 				reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<10*ACT_IDX_W) begin
            o_til_ystep[b-(9*ACT_IDX_W)] = 				reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<10*ACT_IDX_W+DILP_W) begin
            Dil_pat_BE[b-(10*ACT_IDX_W)] =              reg_act_mux[b/IF_W][b%IF_W];

        end else if (b<10*ACT_IDX_W+DILP_W+Y) begin
            rows_active_BE[b-(10*ACT_IDX_W+DILP_W)] =   reg_act_mux[b/IF_W][b%IF_W];

        end else begin

            for (integer y=0; y < Y; y++) begin
                if ((b>=10*ACT_IDX_W+DILP_W+Y+PARAMS_W*y)&&(b<10*ACT_IDX_W+DILP_W+Y+PARAMS_W*(y+1))) begin
                    o_loc_woffs[y][b-(10*ACT_IDX_W+DILP_W+Y+PARAMS_W*y)] =    reg_act_mux[b/IF_W][b%IF_W];
                end
            end
        end
    end

	// ***************************************************
	// Weight config region
	// ***************************************************

    for (integer b=0; b<TOTAL_BITS_WEI; b++) begin
        if (b<WEI_IDX_W) begin
            o_wlim[b] =                                 reg_wei_mux[b/IF_W][b%IF_W];

        end else if (b<2*WEI_IDX_W) begin
            o_wstep[b-WEI_IDX_W] =                      reg_wei_mux[b/IF_W][b%IF_W];

        end else if (b<3*WEI_IDX_W) begin
            o_auxlim[b-(2*WEI_IDX_W)] =                  reg_wei_mux[b/IF_W][b%IF_W];

        end else if (b<4*WEI_IDX_W) begin
            o_auxstep[b-(3*WEI_IDX_W)] =                reg_wei_mux[b/IF_W][b%IF_W];

        end else if (b<5*WEI_IDX_W) begin
            o_til_klim[b-(4*WEI_IDX_W)] =               reg_wei_mux[b/IF_W][b%IF_W];

        end else if (b<6*WEI_IDX_W) begin
            o_til_kstep[b-(5*WEI_IDX_W)] =              reg_wei_mux[b/IF_W][b%IF_W];

        end else if (b<6*WEI_IDX_W + X) begin
            cols_active_BE[b-(6*WEI_IDX_W)] =           reg_wei_mux[b/IF_W][b%IF_W];

        end else begin
            o_waligned =                                reg_wei_mux[b/IF_W][b%IF_W];
        end     
    end

	// ***************************************************
	// Output config region
	// ***************************************************

    for (integer b=0; b<TOTAL_BITS_OUT; b++) begin
        if (b<OUT_IDX_W) begin
            o_ncontexts[b] =                            reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<2*OUT_IDX_W) begin
            o_cxlim[b-OUT_IDX_W] =                      reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<3*OUT_IDX_W) begin
            o_cxstep[b-(2*OUT_IDX_W)] =                 reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<4*OUT_IDX_W) begin
            o_cklim[b-(3*OUT_IDX_W)] =                  reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<5*OUT_IDX_W) begin
            o_ckstep[b-(4*OUT_IDX_W)] =                 reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<6*OUT_IDX_W) begin
            o_til_cylim[b-(5*OUT_IDX_W)] =              reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<7*OUT_IDX_W) begin
            o_til_cystep[b-(6*OUT_IDX_W)] =             reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<8*OUT_IDX_W) begin
            o_til_cklim[b-(7*OUT_IDX_W)] =              reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<9*OUT_IDX_W) begin
            o_til_ckstep[b-(8*OUT_IDX_W)] =             reg_out_mux[b/IF_W][b%IF_W];

        end else if (b<9*OUT_IDX_W + PARAMS_W) begin
            o_inactive_cols[b-(9*OUT_IDX_W)] =          reg_out_mux[b/IF_W][b%IF_W];

        end else begin
            o_preload_en =                              reg_out_mux[b/IF_W][b%IF_W];
        end
    end
end

// ---------------------------------------------------------------------------
// Output register
// ---------------------------------------------------------------------------

always_ff @(posedge i_clk or negedge i_rstn) begin : outbuff_reg
    if(~i_rstn) begin
        out_databuf_q <= 0;
    end else begin
        if (rden) begin
            out_databuf_q <= out_databuf_d;
        end
    end
end

assign o_data_out = out_databuf_q;

// ---------------------------------------------------------------------------
// DONE Interrupt - Taken from done flag from context_fsm
// ---------------------------------------------------------------------------

assign o_doneintr = done_intr_q && global_ien_q && done_ien_q;

// ---------------------------------------------------------------------------
// Soft-Reset
// ---------------------------------------------------------------------------

assign soft_rst_edge = soft_rst_q & (!soft_rst_q_prv);
assign o_soft_reset = soft_rst_edge;

endmodule 
