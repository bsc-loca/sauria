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

# --------------------------------------
#%% IMPORTS
# --------------------------------------

import numpy as np
import torch
import sys
import os
import copy

sys.path.insert(1, './../')

import helpers.test_helper as th
import helpers.data_gen_helper as dgh
import helpers.config_helper as cfg
import helpers.dma_controller_helper as ph
import helpers.convolution_helper as conv

# --------------------------------------
#%% TEST SCRIPT OPTIONS
# --------------------------------------

silent = True

if (th.TOPTS['test_type'] == 'bmk_torture'):
    N_CMDS_MAX =        10000000  # Max number of commands
else:
    N_CMDS_MAX =        200000

# RANDOM SEED
np.random.seed(117)

# --------------------------------------
#%% INITIALIZATIONS
# --------------------------------------

# Initialize data structures for debugging
tensors_list =  []
macs_list =     []
muls_list =     []
imats_list =    []
regs_list =     []
controller_args_list = []

testcfg_list = []

# --------------------------------------
#%% MAIN TEST LOOP
# --------------------------------------
   
# Prepare configuration dict for systolic array model
SA = th.get_sa_dict()

# Prepare tests
TESTS, TILEINFO, LIMITS = th.generate_tests()

# Initialize Main and Golden Main memories
if ((th.TOPTS['test_type']=='conv_validation') or 
    (th.TOPTS['test_type']=='power_estimation')):
    dram_region_len = th.TOPTS['MainMem_smallregion_init']
else:
    dram_region_len = th.TOPTS['MainMem_bigregion_init']

DRAM_mem = np.zeros((len(TESTS[0])*dram_region_len), dtype=np.uint8)
DRAM_mem_gold = np.zeros((len(TESTS[0])*dram_region_len), dtype=np.uint8)

# Initial main memory offset
mem_offset = th.HOPTS['MainMemory_offset']

# Recursive variables to initialize
prev_cpointers = [0,0]
prev_CONVs = [0,0]
til_iter = 0

# Loop over all tests to be performed
for iteration in range(len(TESTS[0])):
    
    # Get convolution configuration for current test
    CONV = th.get_conv_dict(iteration, TESTS, TILEINFO, check_mem_size=True)
    
    # Generate A, B, C random tensors
    A_tensor, B_tensor, C_tensor = dgh.generate_tensors(CONV, th.HOPTS)

    # Perform convolution with systolic array model
    C_output, partial_macs, loop_order = conv.get_ideal_results(A_tensor, B_tensor, C_tensor, CONV, th.HOPTS, SA, compute_macs=th.TOPTS['compute_macs'])
                                    
    # Write values into simulated main memory
    offsets = cfg.write_dram_values(A_tensor, B_tensor, C_tensor, C_output, mem_offset, DRAM_mem, DRAM_mem_gold, CONV, th.HOPTS)
            
    # Update testcfg list with current memory region
    th.testcfg_update(testcfg_list, offsets[0], offsets[3], CONV)

    # Generate SAURIA config registers    
    sauria_regs = cfg.get_sauria_regs(CONV, th.HOPTS, silent=silent)

    # Get controller configuration for the hardware
    controller_args = ph.get_controller_regs(CONV, th.HOPTS, sauria_regs, offsets, loop_order)
    controller_args_list.append(controller_args)
    
    # Prepare next test => Go to next DRAM region
    mem_offset += offsets[3]
                    
    # Append values to debug lists
    tensors_list.append([A_tensor, B_tensor, C_tensor, C_output])
    regs_list.append(sauria_regs)
    macs_list.append(partial_macs[0])
    muls_list.append(partial_macs[1])
    imats_list.append(partial_macs[2])

# Save Test outputs
th.generate_test_outputs(DRAM_mem, DRAM_mem_gold, controller_args_list, testcfg_list, len(TESTS[0]))

#%% To print in int

np.set_printoptions(formatter={})

#%% To print in hex

np.set_printoptions(formatter={'int':lambda x:hex(int(x))})

# %%
