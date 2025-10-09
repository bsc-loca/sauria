"""
Copyright 2023 Barcelona Supercomputing Center (BSC)
SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

Licensed under the Solderpad Hardware License v 2.1 (the “License”);
you may not use this file except in compliance with the License, or,
at your option, the Apache License version 2.0.
You may obtain a copy of the License at

https://solderpad.org/licenses/SHL-2.1/

Unless required by applicable law or agreed to in writing, any work
distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.


Jordi Fornt <jfornt@bsc.es>
"""

import numpy as np
import sys
import os

sys.path.insert(1, './../')
import src.data_helper as dh
import src.config_helper as cfg

# ---------------------------------------
# STIMULI MANAGEMENT
# ---------------------------------------

def generate_test_files(DRAM_mem, DRAM_mem_gold, controller_regs, testcfg_list, N_tests, HOPTS):
    
    N_VECTORS = 50*N_tests
            
    # Fill config arrays
    # ----------------------------------
    cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out = cfg.generate_controller_cmds(controller_regs, N_VECTORS, HOPTS)

    # Create & organize output matrices
    # ----------------------------------
    
    Input_Matrix = np.zeros((N_VECTORS, 7), dtype=np.uint64)
    
    Input_Matrix[:,0] = dh.convert_to_intN(cfg_data_in, HOPTS['CFG_AXI_DATA_WIDTH'])
    Input_Matrix[:,1] = dh.convert_to_intN(cfg_address, HOPTS['CFG_AXI_ADDR_WIDTH'])
    Input_Matrix[:,2] = cfg_wren
    Input_Matrix[:,3] = cfg_rden
    Input_Matrix[:,4] = cfg_waitflag
    Input_Matrix[:,5] = cfg_data_out
    Input_Matrix[:,6] = cfg_checkflag
        
    # Save output matrices
    # ----------------------------------

    # Append string to add to file names (mark approximate values)
    app_str = "" if not HOPTS['approx_comp'] else "_approx"

    folder = "../../test/stimuli/"

    # Save matrices
    np.savetxt(folder+"GoldenStimuli"+app_str+".txt", Input_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"initial_dram"+app_str+".txt", DRAM_mem, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"gold_dram"+app_str+".txt", DRAM_mem_gold, fmt='%01X', delimiter=' ')
    
    # Generate and save test config file 
    np.savetxt(folder+"tstcfg"+app_str+".txt", np.array(testcfg_list), fmt='%01X', delimiter=' ')

    # Remove previous outputs to raise an error in case nothing is produced
    outfolder = "../../test/outputs/"

    # No error if files do not exist
    try:
        os.remove(outfolder+"test_results.txt")
    except OSError:
        pass
    try:
        os.remove(outfolder+"test_stats.txt")
    except OSError:
        pass

# ---------------------------------------
# OUTPUT FILE PARSING
# ---------------------------------------

def parse_test_outputs(HOPTS):

   # Read tensor outputs
    folder = "../../test/outputs/"
    raw_outputs = np.loadtxt(folder+"test_results.txt", dtype=str)

    # Transform strings into 8b integer values
    out_bytes = np.array([int(x,16) for x in raw_outputs[1:]])

    # Join bytes into words (values) - WARNING - We assume words are multiples of 8b!!!!
    N_bytes = int(np.ceil(HOPTS['OC_W']/8))
    out_values = np.zeros(int(out_bytes.size//N_bytes),dtype=np.int64)
    for i in range(N_bytes):
        out_values += (out_bytes[i::N_bytes] << 8*(i))

    # Read statistics outputs
    stats_outputs = np.loadtxt(folder+"test_stats.txt", dtype=int)
    stats_dict = {
        '1tile_SAURIA_cycles'   :   stats_outputs[0],
        '1tile_SAURIA_stalls'   :   stats_outputs[1],
        'sim_time'              :   stats_outputs[2]
    }

    n_test_errors = stats_outputs[3]

    return out_values, stats_dict, n_test_errors