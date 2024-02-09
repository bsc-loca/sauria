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

#include "verilated.h"
#include <verilated_vcd_c.h>
#include "Vsauria_tester.h"
#include <string>
#include <sstream>
#include <vector>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <memory>

using std::string;
using std::vector;

using namespace std;

//#define VERBOSE

uint64_t main_time = 0;
uint64_t max_time = 0;
uint64_t start_vcd_time = 0;
unsigned int exit_delay = 0;
unsigned int exit_code = 0;

// HELP PRINTS
void print_help(){

    std::cout << "SAURIA Verilator simulation flags: "<< std::endl << std::endl;

    std::cout << "conv_validation (default)"<< std::endl;
    std::cout << "\t Simulates 100 different single convolution workloads of different tensor shapes, kernel size, strides and dilation coefficient."<< std::endl << std::endl;

    std::cout << "bmk_small"<< std::endl;
    std::cout << "\t Simulates 4 different convolutions that do not fit in the SAURIA memories, with tiling."<< std::endl << std::endl;

    std::cout << "bmk_torture"<< std::endl;
    std::cout << "\t Simulates 40 different convolutions that do not fit in the SAURIA memories, with tiling."<< std::endl << std::endl;

    std::cout << "+max-cycles="<< std::endl;
    std::cout << "\tSets the maximum cycles of the simulation."<< std::endl << std::endl;

    std::cout << "+start_vcd_time="<< std::endl;
    std::cout << "\tSets the starting cycle of the vcd trace."<< std::endl << std::endl;

    std::cout << "+vcd"<< std::endl;
    std::cout << "\tEnables the vcd trace on the simulation. The default output file is verilated.vcd"<< std::endl << std::endl;
    
    std::cout << "+vcd_name="<< std::endl;
    std::cout << "\tSets the output file of the vcd trace"<< std::endl << std::endl;
}

// WRITE DATA TO CFG AXI
void cfg_req_write(Vsauria_tester* top, uint32_t address, uint32_t data) {
    top->cfg_bus_lite_aw_addr = address;
    top->cfg_bus_lite_aw_valid = 1;
    top->cfg_bus_lite_w_data = data;
    top->cfg_bus_lite_w_valid = 1;
}

// CHECK RESPONSE OF CFG AXI
int cfg_check_resp(Vsauria_tester* top, uint8_t status) {

    if (top->cfg_bus_lite_aw_ready && top->cfg_bus_lite_aw_valid) {
        top->cfg_bus_lite_aw_valid = 0;
        status = status | 0x1;
    }

    if (top->cfg_bus_lite_w_ready && top->cfg_bus_lite_w_valid) {
        top->cfg_bus_lite_w_valid = 0;
        status = status | 0x2;
    } 
    
    return status;
}

// MAIN BODY
int main(int argc, char** argv, char** env) {

    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Vsauria_tester* top = new Vsauria_tester{contextp};

    bool vcd_enable = false;
    string vcd_name = "verilated.vcd";

    int test_type = 2;      // 0=bmk_small ; 1=bmk_torture ; 2=conv_validation

    vector<string> args(argv + 1, argv + argc);
    vector<string>::iterator tail_args = args.end();

    bool done = 0;

    uint64_t cycle_counter = 0;
    uint64_t idx_cfg = 0;
    int dma_status = 3;
    int cfg_status = 3;

    unsigned int test_tiles, n_tests;
    unsigned int test_idx = 0;

    uint32_t cfg_data_in, cfg_addr;
    bool cfg_wren, cfg_rden, cfg_wait4sauria;
    bool check_flag;
    bool lower_intr_flag = 0;

    uint32_t total_errors = 0;

    // Handle Arguments
    for(vector<string>::iterator it = args.begin(); it != args.end(); ++it) {
        if((*it == "--help") or (*it == "--h") ) {
            print_help();
            exit(0);
        }
        else if(*it == "+vcd") {
            vcd_enable = true;
        }
        else if(*it == "bmk_small") {
            test_type = 0;
        }
        else if(*it == "bmk_torture") {
            test_type = 1;
        }
        else if(*it == "conv_validation") {
            test_type = 2;
        }
        else if(it->find("+max-cycles=") == 0) {
            max_time = strtoul(it->substr(strlen("+max-cycles=")).c_str(), NULL, 10);
        }
        else if(it->find("+start_vcd_time=") == 0) {
            start_vcd_time = strtoul(it->substr(strlen("+start_vcd_time=")).c_str(), NULL, 10);
        }
        else if(it->find("+vcd_name=") == 0) {
            vcd_name = it->substr(strlen("+vcd_name="));
        }
        else {
            if (it->find("+") == 0) {
                std::cerr << "Error: Unrecognized argument '" << *it << "'." << std::endl;
                print_help();
                exit(1);
            } else {
                tail_args = it;
            }
        }
    }

    std::cout << std::endl << "Initializing SAURIA test..." << std::endl << std::endl;

    #ifdef APPROXIMATE
        std::cout << "Using Approximate arithmetic." << std::endl;
    #else
        std::cout << "Using Exact arithmetic." << std::endl;
    #endif

    // Prepare VCD dump
    VerilatedVcdC* vcd = new VerilatedVcdC;
    if(vcd_enable) {
        Verilated::traceEverOn(true);
        top->trace(vcd, 99);
        vcd->open(vcd_name.c_str());
    }

    // Open stimuli/output files
    std::cout << "Reading stimuli from file..." << std::endl;
    string filename, stim_path;

    if (test_type==0) {
        stim_path.assign("../stimuli/bmk_small/");
        std::cout << "Executing bmk_small - 4 large convolutions." << std::endl;
    }
    else if (test_type==1) {
        stim_path.assign("../stimuli/bmk_torture/");
        std::cout << "Executing bmk_torture - 40 large convolutions." << std::endl;
        std::cout << "NOTE!: Currently experiencing some errors... Debugging coming soon." << std::endl;
    }
    else {
        stim_path.assign("../stimuli/conv_validation/");
        std::cout << "Executing conv_validation - 100 small convolutions." << std::endl << std::endl;
    }

    // Pass test type to sauria_tester
    top->file_opts = test_type;

    // TEST PARAMETERS FILE
    // ----------------------------
    ifstream TestFile, cntFile0;

    #ifdef APPROXIMATE
    filename = stim_path + "tstcfg_approx.txt";
    #else
    filename = stim_path + "tstcfg.txt";
    #endif

    cntFile0.open(filename);
    if (!cntFile0.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    int N_LINES_TST = std::count(std::istreambuf_iterator<char>(cntFile0), 
                  std::istreambuf_iterator<char>(), '\n');

    cntFile0.close();

    TestFile.open(filename);
    if (!TestFile.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    // Put stimuli values into arrays
    uint64_t TestcfgArray[N_LINES_TST];

    for (int r = 0; r < N_LINES_TST; r++)
    {
        TestFile >> hex >> TestcfgArray[r];
    }

    TestFile.close();

    // Get global and first values
    n_tests = TestcfgArray[0];
    test_tiles = TestcfgArray[2];

    // CONTROL STIMULI FILE
    // ----------------------------
    ifstream StimFile, cntFile1;

    #ifdef APPROXIMATE
    filename = stim_path + "GoldenStimuli_approx.txt";
    #else
    filename = stim_path + "GoldenStimuli.txt";
    #endif

    cntFile1.open(filename);
    if (!cntFile1.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    uint64_t N_LINES_STIM = std::count(std::istreambuf_iterator<char>(cntFile1), 
                  std::istreambuf_iterator<char>(), '\n');

    cntFile1.close();

    StimFile.open(filename);
    if (!StimFile.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    // Put stimuli values into arrays
    uint64_t* StimuliArray = (uint64_t*) malloc(N_LINES_STIM*5*sizeof(uint64_t));

    for (uint64_t r = 0; r < N_LINES_STIM; r++) //Outer loop for rows
    {
        for (uint64_t c = 0; c < 5; c++) //inner loop for columns
        {
            StimFile >> hex >> StimuliArray[5*r+c];
            //cout<<"M["<<r<<"]["<<c<<"]"<<" = "<<StimuliArray[5*r+c]<<std::endl;
        }
    }

    StimFile.close();

    // OUTPUT CHECK FILE
    // ----------------------------
    ifstream OutFile, cntFile2;

    #ifdef APPROXIMATE
    filename = stim_path + "GoldenOutputs_approx.txt";
    #else
    filename = stim_path + "GoldenOutputs.txt";
    #endif

    cntFile2.open(filename);
    if (!cntFile2.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    uint64_t N_LINES_OUT = std::count(std::istreambuf_iterator<char>(cntFile2), 
                  std::istreambuf_iterator<char>(), '\n');

    cntFile2.close();

    OutFile.open(filename);
    if (!OutFile.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    // Put stimuli values into arrays
    uint64_t* OutArray = (uint64_t*) malloc(N_LINES_OUT*2*sizeof(uint64_t));

    for (uint64_t r = 0; r < N_LINES_OUT; r++) //Outer loop for rows
    {
        for (uint64_t c = 0; c < 2; c++) //inner loop for columns
        {
            OutFile >> hex >> OutArray[2*r+c];
        }
    }

    OutFile.close();

    std::cout << std::endl << "Starting tests" << std::endl << std::endl;

    // Initialize control variables
    cfg_wait4sauria = false;
    lower_intr_flag = false;

    //#####################################################################
    //########################## MAIN LOOP ################################
    //#####################################################################
    while (!Verilated::gotFinish() && (!done) && (!exit_code || exit_delay > 1)
    && (max_time == 0 || main_time < max_time) && (exit_delay != 1)) {
        
        // RAISE RST
        if(main_time > 100) {
          top->rstn_sauria = 1;
          top->rstn_sys = 1;
        }

        // *******************
        // 2 ns clk (SAURIA) => ONLY INTERNAL TO THE ACCELERATOR
        // *******************

        // Rising Edge
        if((main_time % 20) == 0) {
          top->clk_sauria = 1;
        }

        // Falling Edge
        if((main_time % 20) == 10) {
          top->clk_sauria = 0;
        }

        // *******************
        // 1 ns clk (SYS) => USED FOR THE AXI SYSTEM
        // *******************

        // Rising Edge
        if((main_time % 10) == 0) {
            top->clk_sys = 1;

            // ACT AFTER RESET ONLY
            if(main_time > 120) {

                cycle_counter++;

                // ++++++++++++++++++++++++++++
                //     CONFIG AXI INTERFACE
                // ++++++++++++++++++++++++++++

                // Wait for SAURIA condition
                if (cfg_wait4sauria) {
                    if (top->ctrl_interrupt){
                        cfg_wait4sauria=0;
                        test_idx++;
                        #ifdef VERBOSE
                        std::cout << "[" << main_time << "] New test " << test_idx << std::endl;
                        #endif
                    }

                // Lowering SAURIA interrupt flag
                } else if (lower_intr_flag) {

                    #ifdef VERBOSE
                    std::cout << "[" << main_time << "] [CFG] Lowering SAURIA interrupt... " << (int)(top->ctrl_interrupt) << std::endl;
                    #endif

                    if (cfg_status==3) {
                        cfg_req_write(top, 0xC, 0xF);
                        cfg_status = 0;
                    } else {
                        cfg_status = cfg_check_resp(top, cfg_status);

                        // Advance pointer only on success
                        if ((cfg_status==3) && (top->ctrl_interrupt==0)) {lower_intr_flag=0;}
                    }

                // Active condition
                } else {
                    
                    // GET STIMULI VALUES
                    cfg_data_in =   StimuliArray[5*idx_cfg+0];
                    cfg_addr =      StimuliArray[5*idx_cfg+1];
                    cfg_wren =      StimuliArray[5*idx_cfg+2];
                    cfg_rden =      StimuliArray[5*idx_cfg+3];

                    #ifdef VERBOSE
                    std::cout << "[" << main_time << "] CFG idx " << idx_cfg << std::endl;
                    //std::cout << "Controller interrupt... " << (int)(top->ctrl_interrupt) << std::endl;
                    #endif

                    switch (StimuliArray[5*idx_cfg+4]) {
                        case 1:
                            cfg_wait4sauria = 1;
                            #ifdef VERBOSE
                            std::cout << "[" << main_time << "] [CFG] Waiting 4 sauria..." << std::endl;
                            #endif
                            break;
                        case 2:
                            cfg_wait4sauria = 0;
                            #ifdef VERBOSE
                            std::cout << "[" << main_time << "] [CFG] Waiting 4 other IF..." << std::endl;
                            #endif
                            break;
                        default:
                            cfg_wait4sauria = 0;
                            break;
                    }

                    check_flag = OutArray[2*idx_cfg+1];

                    // WRITE
                    if (cfg_wren) {

                         // Write to CFG interface if previous transaction is done
                        if (cfg_status==3) {
                            cfg_req_write(top, cfg_addr, cfg_data_in);
                            cfg_status = 0;
                        } else {
                            cfg_status = cfg_check_resp(top, cfg_status);

                            // Advance pointer only on success
                            if (cfg_status==3) {idx_cfg++;}
                        }

                    // READ => Not supported atm
                    } else if (cfg_rden) {
                        idx_cfg++;

                        // TO-DO

                    // OTHERS => Advance pointer
                    } else {
                        idx_cfg++;
                    }
                }
            }
            uint32_t aw_valid, aw_ready, w_valid, w_ready;
            aw_valid = top->cfg_bus_lite_aw_valid;
            aw_ready = top->cfg_bus_lite_aw_ready;
            w_valid = top->cfg_bus_lite_w_valid;
            w_ready = top->cfg_bus_lite_w_ready;
        }

        // Falling Edge
        if((main_time % 10) == 5) {
          top->clk_sys = 0;
        }

        // CHECK DATA WHEN NEEDED
        if (check_flag) {
            top->test_idx = (test_idx-1);       // idx-1 because we always test the previous (when we extract data)
            top->dram_startoffs = TestcfgArray[2+3*(test_idx-1)+1];
            top->dram_endoffs = TestcfgArray[2+3*(test_idx-1)+2];
            top->check_flag = 1;
            check_flag = 0;

            if ((top->errors)>0){
                std::cout << "[" << main_time << "] Test " << (test_idx-1) << " - \t failed with " << top->errors << " errors." << std::endl;
            } else {
                std::cout << "[" << main_time << "] Test " << (test_idx-1) << " - \t passed with 0 errors :)" << std::endl;
            }

            total_errors+=top->errors;

            // END OF TEST
            if (test_idx == n_tests) {
                done = 1;
            }

        } else {
            top->check_flag = 0;    
        }

        // Evaluate RTL model
        top->eval();

        if (vcd_enable && main_time == start_vcd_time) std::cout << "[" << main_time << "] Starting VCD dump." << std::endl;
        if (vcd_enable && main_time > start_vcd_time) vcd->dump(main_time);

        if(main_time < 140)
            main_time++;
        else
            main_time += 1;

        if((main_time % 10) == 0 && exit_delay > 1)
            exit_delay--;             // postponed delay to allow VCD recording
    
    }

    if (total_errors>0) {
        std::cout << std::endl << "[" << main_time << "] Benchmark failed with " << total_errors << " errors." << std::endl << "FAILED!" << std::endl;
        exit_code = 1;
    } else {
        std::cout << std::endl << "[" << main_time << "] Benchmark passed with no errors." << std::endl << "SUCCESS!" << std::endl;
    }

    top->final();
    if(vcd_enable) vcd->close();

    if (max_time != 0 && main_time >= max_time) {
        exit_code = 1;
        std::cerr << "[" << main_time << "] TIMEOUT - Arrived at max time." << std::endl;
    }

    delete top;
    delete contextp;

    return exit_code;
}
