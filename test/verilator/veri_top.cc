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

uint64_t main_time = 0;
uint64_t max_time = 10000;
uint64_t start_vcd_time = 0;
unsigned int exit_delay = 0;
unsigned int exit_code = 0;

// HELP PRINTS
void print_help(){

    std::cout << "SAURIA Verilator simulation flags: "<< std::endl << std::endl;

    std::cout << "+max-cycles="<< std::endl;
    std::cout << "\tSets the maximum cycles of the simulation."<< std::endl << std::endl;

    std::cout << "+start_vcd_time="<< std::endl;
    std::cout << "\tSets the starting cycle of the vcd trace."<< std::endl << std::endl;

    std::cout << "+vcd"<< std::endl;
    std::cout << "\tEnables the vcd trace on the simulation. The default output file is verilated.vcd"<< std::endl << std::endl;
    
    std::cout << "+vcd_name="<< std::endl;
    std::cout << "\tSets the output file of the vcd trace"<< std::endl << std::endl;

    std::cout << "+check_read_values"<< std::endl;
    std::cout << "\tChecks that values read from the config interface are equal to the golden ones from the stimuli."<< std::endl << std::endl;

    std::cout << "+debug"<< std::endl;
    std::cout << "\tPrint additional debug information."<< std::endl << std::endl;

}

// WRITE DATA TO CFG AXI
void cfg_req_write(Vsauria_tester* top, uint32_t address, uint32_t data) {
    top->cfg_bus_lite_aw_addr = address;
    top->cfg_bus_lite_aw_valid = 1;
    top->cfg_bus_lite_w_data = data;
    top->cfg_bus_lite_w_valid = 1;
}

// READ DATA FROM CFG AXI
void cfg_req_read(Vsauria_tester* top, uint32_t address) {
    top->cfg_bus_lite_ar_addr = address;
    top->cfg_bus_lite_ar_valid = 1;
    top->cfg_bus_lite_r_ready = 1;
}

// CHECK RESPONSE OF CFG AXI WRITES
int cfg_check_wresp(Vsauria_tester* top, uint8_t status) {

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

// CHECK RESPONSE OF CFG AXI READS
int cfg_check_rresp(Vsauria_tester* top, uint8_t status, uint32_t* data_buf) {

    if (top->cfg_bus_lite_ar_ready && top->cfg_bus_lite_ar_valid) {
        top->cfg_bus_lite_ar_valid = 0;
        status = status | 0x1;
    }

    if (top->cfg_bus_lite_r_ready && top->cfg_bus_lite_r_valid) {
        top->cfg_bus_lite_r_ready = 0;
        status = status | 0x2;

        // Write read data into buffer
        *data_buf = top->cfg_bus_lite_r_data;
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
    string stim_path = "../stimuli";
    string out_path = "../outputs";

    vector<string> args(argv + 1, argv + argc);
    vector<string>::iterator tail_args = args.end();

    bool done = 0;

    uint64_t cycle_counter = 0;
    uint64_t idx_cfg = 0;
    int dma_status = 3;
    int cfg_status = 3;
    bool read_in_progress = 0;
    bool debug = false;
    bool check_read_values = false;

    uint32_t cfg_data_in, cfg_addr;
    bool cfg_wren, cfg_rden, cfg_wait4sauria;
    bool check_flag = 0;
    bool lower_intr_flag = 0;
    uint32_t rd_databuf;
    uint32_t expected_rd;

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
        else if(it->find("+max-cycles=") == 0) {
            max_time = strtoul(it->substr(strlen("+max-cycles=")).c_str(), NULL, 10);
        }
        else if(it->find("+start_vcd_time=") == 0) {
            start_vcd_time = strtoul(it->substr(strlen("+start_vcd_time=")).c_str(), NULL, 10);
        }
        else if(it->find("+vcd_name=") == 0) {
            vcd_name = it->substr(strlen("+vcd_name="));
        }
        else if(it->find("+stim_path=") == 0) {
            stim_path = it->substr(strlen("+stim_path="));
        }
        else if(it->find("+out_path=") == 0) {
            out_path = it->substr(strlen("+out_path="));
        }
        else if(*it == "+check_read_values") {
            check_read_values = true;
        }
        else if(*it == "+debug") {
            debug = true;
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

    // Prepare VCD dump
    VerilatedVcdC* vcd = new VerilatedVcdC;
    if(vcd_enable) {
        Verilated::traceEverOn(true);
        top->trace(vcd, 99);
        vcd->open(vcd_name.c_str());
    }

    // Open stimuli/output files
    std::cout << "Reading stimuli from file..." << std::endl;
    string filename;

    // TEST PARAMETERS FILE
    // ----------------------------
    ifstream TestFile, cntFile0;
    filename = stim_path + "/tstcfg.txt";

    // Count number of lines in tstcfg.txt
    cntFile0.open(filename);
    if (!cntFile0.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    int N_LINES_TST = std::count(std::istreambuf_iterator<char>(cntFile0), 
                  std::istreambuf_iterator<char>(), '\n');

    cntFile0.close();

    if (debug)  std::cout<<"Test config file " << filename << " has "<< N_LINES_TST << " lines.\n";

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

    // CONTROL STIMULI FILE
    // ----------------------------
    ifstream StimFile, cntFile1;
    filename = stim_path + "/GoldenStimuli.txt";

    // Count number of lines in GoldenStimuli.txt
    cntFile1.open(filename);
    if (!cntFile1.is_open()) {
        cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    uint64_t N_LINES_STIM = std::count(std::istreambuf_iterator<char>(cntFile1), 
                  std::istreambuf_iterator<char>(), '\n');

    cntFile1.close();

    if (debug)  std::cout<<"Stimuli file " << filename << " has "<< N_LINES_STIM << " lines.\n";

    StimFile.open(filename);
    if (!StimFile.is_open()) {
        std::cout<<"Error opening file: "<< filename << " \n";
        return 1;
    }

    // Put stimuli values into arrays
    uint64_t* StimuliArray = (uint64_t*) malloc(N_LINES_STIM*7*sizeof(uint64_t));

    for (uint64_t r = 0; r < N_LINES_STIM; r++) //Outer loop for rows
    {
        for (uint64_t c = 0; c < 7; c++) //inner loop for columns
        {
            StimFile >> hex >> StimuliArray[7*r+c];
            //cout<<"M["<<r<<"]["<<c<<"]"<<" = "<<StimuliArray[7*r+c]<<std::endl;
        }
    }

    StimFile.close();

    std::cout << std::endl << "Starting test" << std::endl << std::endl;

    // Initialize control variables
    cfg_wait4sauria = false;
    lower_intr_flag = false;

    // Open file to log additional registers read from CFG interface
    ofstream statsFile;
    filename = out_path + "/test_stats.txt";
    statsFile.open(filename);

    //#####################################################################
    //########################## MAIN LOOP ################################
    //#####################################################################
    while (!Verilated::gotFinish() && (!done) && (idx_cfg < N_LINES_STIM)
        && (max_time == 0 || main_time < max_time)
        && (!exit_code || exit_delay > 1)  && (exit_delay != 1)) {
        
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
                        if (debug) std::cout << "[" << main_time << "] New test " << std::endl;
                    }

                // Lowering SAURIA interrupt flag
                } else if (lower_intr_flag) {

                    if (debug) std::cout << "[" << main_time << "] [CFG] Lowering SAURIA interrupt... " << (int)(top->ctrl_interrupt) << std::endl;
                    if (cfg_status==3) {
                        cfg_req_write(top, 0xC, 0xF);
                        cfg_status = 0;
                    } else {
                        cfg_status = cfg_check_wresp(top, cfg_status);

                        // Advance pointer only on success
                        if ((cfg_status==3) && (top->ctrl_interrupt==0)) {lower_intr_flag=0;}
                    }

                // Active condition
                } else {
                    
                    // GET STIMULI VALUES
                    cfg_data_in =   StimuliArray[7*idx_cfg+0];
                    cfg_addr =      StimuliArray[7*idx_cfg+1];
                    cfg_wren =      StimuliArray[7*idx_cfg+2];
                    cfg_rden =      StimuliArray[7*idx_cfg+3];

                    if (debug) std::cout << "[" << main_time << "] CFG idx " << idx_cfg << std::endl;

                    switch (StimuliArray[7*idx_cfg+4]) {
                        case 1:
                            cfg_wait4sauria = 1;
                            if (debug) std::cout << "[" << main_time << "] [CFG] Waiting 4 sauria..." << std::endl;
                            break;
                        case 2:
                            cfg_wait4sauria = 0;
                            if (debug) std::cout << "[" << main_time << "] [CFG] Waiting 4 other IF..." << std::endl;
                            break;
                        default:
                            cfg_wait4sauria = 0;
                            break;
                    }

                    expected_rd =   StimuliArray[7*idx_cfg+5];
                    check_flag =    StimuliArray[7*idx_cfg+6];

                    // WRITE
                    if (cfg_wren) {

                        // Write to CFG interface if previous transaction is done
                        if (cfg_status==3) {
                            cfg_req_write(top, cfg_addr, cfg_data_in);
                            cfg_status = 0;
                            // Debug test print
                            if (debug) std::cout << std::hex << std::uppercase << "Writing " << cfg_data_in << " into address " << cfg_addr << std::dec << std::endl;
                        } else {
                            cfg_status = cfg_check_wresp(top, cfg_status);

                            // Advance pointer only on success
                            if (cfg_status==3) {idx_cfg++;}
                        }

                    // READ
                    } else if (cfg_rden) {

                        // If a read is in progress, wait until it is complete (no concatenation for reads)
                        if (read_in_progress) {

                            cfg_status = cfg_check_rresp(top, cfg_status, &rd_databuf);
                            if (cfg_status==3) {
                                // Debug test print
                                if (debug) std::cout << std::hex << std::uppercase << "Read " << rd_databuf << " from address " << cfg_addr << std::dec << std::endl;
                                idx_cfg++;
                                read_in_progress = 0;

                                if (check_read_values && (expected_rd != rd_databuf)) {
                                    total_errors+=1;
                                    std::cout << "Error! Expected " << std::hex << expected_rd <<  " but got " << rd_databuf << std::dec << std::endl;
                                }

                                // Save read contents to statsFile
                                statsFile << rd_databuf << std::endl;
                            }

                        // If read not in progress, start it asap
                        } else {
                            // Start read from CFG interface if previous transaction is done
                            if (cfg_status==3) {
                                cfg_req_read(top, cfg_addr);
                                cfg_status = 0;
                                read_in_progress = 1;
                            } else {
                                cfg_status = cfg_check_wresp(top, cfg_status);

                                // Advance pointer only on success
                                if (cfg_status==3) {idx_cfg++;}
                            }
                        }

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

        // CHECK DATA AT THE END OF THE TEST
        if (check_flag){

            // Check data in main memory (in HW model)
            top->dram_startoffs =   TestcfgArray[0];
            top->dram_outoffs =     TestcfgArray[1];
            top->dram_endoffs =     TestcfgArray[2];
            top->check_flag = 1;
            check_flag = 0;

            // END OF TEST, Except debug_test
            if (!check_read_values){
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

    // Update final error tally
    total_errors+=(top->errors);

    // Save final time and number of errors to stats file
    statsFile << main_time << std::endl;
    statsFile << total_errors << std::endl;

    statsFile.close();

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
