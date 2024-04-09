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
#% IMPORTS
# --------------------------------------

import numpy as np
import torch
import sys
import os
import copy

sys.path.insert(1, './../')

from helpers import drac_sa_top_helper as dsth
import helpers.test_helper as th

def wr_transaction(idx, cfg_list, address, data_in):
    cfg_list[0][idx] =  address     # cfg_address
    cfg_list[1][idx] =  data_in     # cfg_data_in
    cfg_list[2][idx] =  1           # cfg_wren
    cfg_list[3][idx] =  0           # cfg_rden
    cfg_list[4][idx] =  0           # cfg_waitflag
    cfg_list[5][idx] =  0           # cfg_checkflag
    cfg_list[6][idx] =  0           # cfg_data_out
    return idx+1

def rd_transaction(idx, cfg_list, address, data_gold):
    cfg_list[0][idx] =  address     # cfg_address
    cfg_list[1][idx] =  0           # cfg_data_in
    cfg_list[2][idx] =  0           # cfg_wren
    cfg_list[3][idx] =  1           # cfg_rden
    cfg_list[4][idx] =  0           # cfg_waitflag
    cfg_list[5][idx] =  1           # cfg_checkflag
    cfg_list[6][idx] =  data_gold   # cfg_data_out
    return idx+1

def gen_test():

    # Max number of vectors
    N_VECTORS = 600

    # Create control words
    # ----------------------------------

    cfg_address = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_data_in = np.zeros((N_VECTORS), dtype=np.uint64)
    cfg_wren = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_rden = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_waitflag = np.zeros((N_VECTORS), dtype=np.uint32)
    
    cfg_checkflag = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_data_out = np.zeros((N_VECTORS), dtype=np.uint64)

    cfg = [cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out]

    # Debug test
    # ----------------------------------

    idx = 0

    # ACCESS CONTROLLER REGISTERS
    idx = rd_transaction(idx,cfg, th.HOPTS["CTRL_offset"]+0x0,      0xC000_0000)
    idx+=5 # Wait
    idx = wr_transaction(idx,cfg, th.HOPTS["CTRL_offset"]+0x10,     0xDEAD_BEEF)
    idx = wr_transaction(idx,cfg, th.HOPTS["CTRL_offset"]+0x48,     0xBEEF_DEAD)
    idx+=5 # Wait
    idx = rd_transaction(idx,cfg, th.HOPTS["CTRL_offset"]+0x10,     0xDEAD_BEEF)
    idx = rd_transaction(idx,cfg, th.HOPTS["CTRL_offset"]+0x48,     0xBEEF_DEAD)
    idx+=50 # Wait

    # ACCESS ReDMA REGISTERS
    idx = rd_transaction(idx,cfg, th.HOPTS["DMA_offset"]+0x0,       0x2D00_0000)
    idx+=5 # Wait
    idx = wr_transaction(idx,cfg, th.HOPTS["DMA_offset"]+0x10,      0xDEAD_BEEF)
    idx = wr_transaction(idx,cfg, th.HOPTS["DMA_offset"]+0x30,      0xBEEF_DEAD)
    idx+=5 # Wait
    idx = rd_transaction(idx,cfg, th.HOPTS["DMA_offset"]+0x10,      0xDEAD_BEEF)
    idx = rd_transaction(idx,cfg, th.HOPTS["DMA_offset"]+0x30,      0xBEEF_DEAD)
    idx+=50 # Wait

    # ACCESS SAURIA REGISTERS
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+0x0,      0xAC00_000C)
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_CON_offset"],    0xDEAD_C201)
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_IFM_offset"],    0xDEAD_1F9A)
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_WEI_offset"],    0xDEAD_3E16)
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_PSM_offset"],    0xDEAD_FE59)
    idx+=5 # Wait
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_CON_offset"],    0xDEAD_C201)
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_IFM_offset"],    0xDEAD_1F9A)
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_WEI_offset"],    0xDEAD_3E16)
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["CFG_PSM_offset"],    0xDEAD_FE59)
    idx+=50 # Wait

    # ACCESS SAURIA MEMORIES
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["MEMA_offset"]+0x10,     0xDEAD_9E91)
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["MEMB_offset"]+0x50,     0xDEAD_9E92)
    idx = wr_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["MEMC_offset"]+0x90,     0xDEAD_9E93)
    idx+=10 # Wait
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["MEMA_offset"]+0x10,     0xDEAD_9E91)
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["MEMB_offset"]+0x50,     0xDEAD_9E92)
    idx = rd_transaction(idx,cfg, th.HOPTS["CORE_offset"]+th.HOPTS["MEMC_offset"]+0x90,     0xDEAD_9E93)
    idx+=50 # Wait

    # ACCESS UNMAPPED REGIONS
    idx = wr_transaction(idx,cfg,   0x3333_3333,    0xDEEE_AAAD)    # Wrong high level mapping
    idx+=5 # Wait
    idx = rd_transaction(idx,cfg,   0x3333_3333,    0x0BAD_ADD2)    # Wrong high level mapping
    idx+=5 # Wait
    idx = wr_transaction(idx,cfg,   th.HOPTS["CTRL_offset"]+0xFF,       0xDEEE_AAAD)    # Unmapped regions
    idx = wr_transaction(idx,cfg,   th.HOPTS["DMA_offset"]+0x38,        0xDEEE_AAAD)    # Unmapped regions
    idx = wr_transaction(idx,cfg,   th.HOPTS["CORE_offset"]+0x30,       0xDEEE_AAAD)    # Unmapped regions
    idx = wr_transaction(idx,cfg,   th.HOPTS["CORE_offset"]+0x1000,     0xDEEE_AAAD)    # Unmapped regions
    idx = wr_transaction(idx,cfg,   th.HOPTS["CORE_offset"]+0xF_0000,   0xDEEE_AAAD)    # Unmapped regions
    idx+=5 # Wait
    idx = rd_transaction(idx,cfg,   th.HOPTS["CTRL_offset"]+0xFF,       0x1BAD_ADD2)    # Unmapped regions
    idx = rd_transaction(idx,cfg,   th.HOPTS["DMA_offset"]+0x38,        0x3BAD_ADD2)    # Unmapped regions
    idx = rd_transaction(idx,cfg,   th.HOPTS["CORE_offset"]+0x30,       0x2BAD_ADD2)    # Unmapped regions
    idx = rd_transaction(idx,cfg,   th.HOPTS["CORE_offset"]+0x1000,     0x2BAD_ADD2)    # Unmapped regions
    idx = rd_transaction(idx,cfg,   th.HOPTS["CORE_offset"]+0xF_0000,   0x4BAD_ADD2)    # Unmapped regions

    # Create & organize output matrices
    # ----------------------------------

    Input_Matrix = np.zeros((N_VECTORS, 5), dtype=np.uint64)
    Output_Matrix = np.zeros((N_VECTORS, 2), dtype=np.uint64)
    
    DRAM_mem = np.zeros(1000, dtype=np.uint8)
    DRAM_mem_gold = np.zeros(1000, dtype=np.uint8)

    Input_Matrix[:,0] = dsth.convert_to_intN(cfg_data_in, th.HOPTS['CFG_AXI_DATA_WIDTH'])
    Input_Matrix[:,1] = dsth.convert_to_intN(cfg_address, th.HOPTS['CFG_AXI_ADDR_WIDTH'])
    Input_Matrix[:,2] = cfg_wren
    Input_Matrix[:,3] = cfg_rden
    Input_Matrix[:,4] = cfg_waitflag

    Output_Matrix[:,0] = cfg_data_out
    Output_Matrix[:,1] = cfg_checkflag

    # Save output matrices
    # ----------------------------------

    # Select folder depending on the test
    folder = "../test/stimuli/debug_test/"

    # Save matrices
    np.savetxt(folder+"GoldenStimuli.txt", Input_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"GoldenOutputs.txt", Output_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"initial_dram.txt", DRAM_mem, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"gold_dram.txt", DRAM_mem_gold, fmt='%01X', delimiter=' ')
    
    # Generate and save test config file
    testcfg_list = []
    testcfg_list.insert(0, 1)
    testcfg_list.insert(0, 1)
    
    np.savetxt(folder+"tstcfg.txt", np.array(testcfg_list), fmt='%01X', delimiter=' ')
