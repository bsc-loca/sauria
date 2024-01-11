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
import scipy.stats as stats
import os
import sys
import copy

from helpers import drac_sa_top_helper as dsth
sys.path.insert(1, './../')

# ----------------------------
# GLOBAL TEST OPTIONS DICT
# ----------------------------

TOPTS = {
    # Test type - One of the following options:
    # *******************************************
    #       * conv_validation :     100 small convolutions to validate all shapes and modes
    #       * bmk_small :           4 medium-sized convolutions with tiling
    #       * bmk_torture :         40 large convolutions with tiling
    #       * power_estimation :    1 small convolution with high PE utilization for power estimation
    "test_type" :           "conv_validation",

    # Additional options used for debugging
    # *******************************************
    "ones_test" :           False,      # Set all tensor elements to '1'
    "insert_deadbeef" :     True,       # Insert regognizable values (0xDEAD, 0xBEEF, 0xBEBE, 0x0FE0) for easy debugging
    "compute_macs" :        False,      # Compute cycle-accurate MAC results (SLOW)    
    
    # Random data generation options
    # *******************************************
    "gauss_scale" :         1.0,        # Scale used for gaussian data
    "pzero_A" :             0.0,        # Probability of 0s in Tensor A
    "pzero_B" :             0.0,        # Probability of 0s in Tensor B
    "pzero_C" :             0.0,        # Probability of 0s in Tensor C

    # Utility options
    # *******************************************
    "MainMem_smallregion_init" :   0x18000,     # Size used to initialize SMALL main memory structures
    "MainMem_bigregion_init"   :   0x80000      # Size used to initialize BIG main memory structures
}

# -----------------------------
# GLOBAL HARDWARE OPTIONS DICT
# -----------------------------

HOPTS = {
    # Address offsets
    # *******************************************
    "MainMemory_offset" :   0x0000_0000,     # Starting address of data in main memory
    "SAURIA_offset_DMA" :   0xD000_0000,     # SAURIA offset from the POV of DMA
    "CTRL_offset" :         0x4410_0000,     # SAURIA controller offset
    "CORE_offset" :         0x4420_0000,     # SAURIA core offset
    "DMA_offset" :          0x4430_0000,     # uDMA offset
    "CFG_CON_offset" :      0x0000_0200,     # Control registers offset
    "CFG_IFM_offset" :      0x0000_0400,     # IFmap Feeder registers offset
    "CFG_WEI_offset" :      0x0000_0600,     # Weight Fetcher registers offset
    "CFG_PSM_offset" :      0x0000_0800,     # Partial sums manager offset
    "MEMA_offset" :         0x0001_0000,     # MEM A access via AXI Lite
    "MEMB_offset" :         0x0002_0000,     # MEM B access via AXI Lite
    "MEMC_offset" :         0x0003_0000,     # MEM C access via AXI Lite
    
    # Memory Sizes
    # *******************************************
    "MEMA_W" :              128,
    "MEMB_W" :              256,
    "MEMC_W" :              128,
    "MEMA_DEPTH" :          2048,
    "MEMB_DEPTH" :          1024,
    "MEMC_DEPTH" :          2048,

    # Interface parameters
    # *******************************************
    "CFG_AXI_DATA_WIDTH" :  32,     # Configuration interface (AXI4-Lite)
    "CFG_AXI_ADDR_WIDTH" :  32,
    "DATA_AXI_DATA_WIDTH" : 128,    # Memory interface (AXI4)
    "DATA_AXI_ADDR_WIDTH" : 32,

    # Systolic Array HW parameters
    # *******************************************
    "X" :                   16,     # SA X size
    "Y" :                   8,      # SA Y size
    "DILP_W" :              64,     # Dilation parameter width
    "PARAMS_W" :            8,      # General parameters width
    "TH_W" :                2,      # Negligence threshold width
    "IFM_FIFO_POSITIONS" :  5,      # IFmap Feeder FIFO positions
    "WEI_FIFO_POSITIONS" :  4,      # Weight Fetcher FIFO positions
    "FIFO_FILL_CYCLES" :    1,      # FIFO filling cycles before computation starts
    
    # Arithmetic options
    # *******************************************
    "IA_W" :                16,     # IFmap bits
    "IB_W" :                16,     # Weight bits
    "OC_W" :                16,     # Partial sum bits
    "OP_TYPE" :             1,      # 0 for int, 1 for FP

    # FP configuration
    "IA_MANT" :             10,     # IFmap mantissa bits
    "IB_MANT" :             10,     # Weight mantissa bits
    "IC_MANT" :             10,     # Partial sum mantissa bits
    "rounding" :            "RNE",  # Rounding type

    # Approximate computing
    "approx_comp" :         False,  # If false, all options are ignored
    "mul_type" :            3,
    "M" :                   14,
    "add_type" :            4,
    "A" :                   16
}

# Dependent parameters
HOPTS['ADRA_W'] = int(np.ceil(np.log2(HOPTS['MEMA_DEPTH'])))
HOPTS['ADRB_W'] = int(np.ceil(np.log2(HOPTS['MEMB_DEPTH'])))
HOPTS['ADRC_W'] = int(np.ceil(np.log2(HOPTS['MEMC_DEPTH'])))

HOPTS['MEMA_N'] = int(HOPTS['MEMA_W']/HOPTS['IA_W'])
HOPTS['IFM_WOFS_W'] = int(np.ceil(np.log2(HOPTS['MEMA_N'])))
HOPTS['IFM_IDX_W'] = HOPTS['ADRA_W'] + HOPTS['IFM_WOFS_W'] + 1

HOPTS['MEMB_N'] = int(HOPTS['MEMB_W']/HOPTS['IB_W'])
HOPTS['WEI_WOFS_W'] = int(np.ceil(np.log2(HOPTS['MEMB_N'])))
HOPTS['WEI_IDX_W'] = HOPTS['ADRB_W'] + HOPTS['WEI_WOFS_W'] + 1

HOPTS['MEMC_N'] = int(HOPTS['MEMC_W']/HOPTS['OC_W'])
HOPTS['PSM_WOFS_W'] = int(np.ceil(np.log2(HOPTS['MEMC_N'])))
HOPTS['PSM_IDX_W'] = HOPTS['ADRC_W'] + HOPTS['PSM_WOFS_W'] + 1

HOPTS['HOST_N'] = int(HOPTS['DATA_AXI_DATA_WIDTH']/HOPTS['IA_W'])

HOPTS['MEMA_size'] = HOPTS['MEMA_DEPTH'] * HOPTS['MEMA_N']
HOPTS['MEMB_size'] = HOPTS['MEMB_DEPTH'] * HOPTS['MEMB_N']
HOPTS['MEMC_size'] = HOPTS['MEMC_DEPTH'] * HOPTS['MEMC_N']

HOPTS['MEMA_PART'] = int(np.ceil(HOPTS['MEMA_W']/64))
HOPTS['MEMB_PART'] = int(np.ceil(HOPTS['MEMB_W']/64))
HOPTS['MEMC_PART'] = int(np.ceil(HOPTS['MEMC_W']/64))
        
HOPTS['MAX_PART'] = 2   # Max 128b (for now)

HOPTS['MEMA_HOST_N'] = int(np.ceil(HOPTS['MEMA_W']/HOPTS['DATA_AXI_DATA_WIDTH']))
HOPTS['MEMB_HOST_N'] = int(np.ceil(HOPTS['MEMB_W']/HOPTS['DATA_AXI_DATA_WIDTH']))
HOPTS['MEMC_HOST_N'] = int(np.ceil(HOPTS['MEMC_W']/HOPTS['DATA_AXI_DATA_WIDTH']))
        
HOPTS['HOST_PART'] = int(np.ceil(HOPTS['DATA_AXI_DATA_WIDTH']/64))

HOPTS['MEMA_CFG_N'] = int(np.ceil(HOPTS['MEMA_W']/HOPTS['CFG_AXI_DATA_WIDTH']))
HOPTS['MEMB_CFG_N'] = int(np.ceil(HOPTS['MEMB_W']/HOPTS['CFG_AXI_DATA_WIDTH']))
HOPTS['MEMC_CFG_N'] = int(np.ceil(HOPTS['MEMC_W']/HOPTS['CFG_AXI_DATA_WIDTH']))    

HOPTS['intyp'] = np.float16 if (HOPTS['OP_TYPE']==1) else np.int64
        
# ---------------------------------------------------
# Void test array (for when we don't want fix tests)
# ---------------------------------------------------

def gen_void_tests():

    FIXTESTS = [[], [], [], [], [], [], [], [], [], [], []]

    return FIXTESTS

# -----------------------------------
# FIX SMALL CONVOLUTION TESTS
# -----------------------------------

def gen_small_fix_tests(X, Y, MEMC_size):

    Bw_list =           [3,     7,  10,   1,   1,    3,   3,  5,    1,   1,   3,  3,  3,  3,        1, 1, 1,        1,                 1,                1,                1,   1]
    Bh_list =           [3,     7,  10,   1,   1,    3,   3,  5,    1,   1,   3,  3,  3,  3,        1, 1, 1,        1,                 1,                1,                1,   1]
    d_list =            [1,     1,   1,   1,   1,    2,  18,  3,    1,   1,   1,  1,  1,  3,        1, 1, 1,        1,                 1,                1,                1,   1]
    s_list =            [1,     2,   5,   1,   1,    1,   1,  1,    1,   1,   1,  1,  1,  3,        1, 1, 1,        1,                 1,                1,                1,   1]
    c_list =            [16,    3,   3, 111, 111,    3,   8,  3 ,   3, 208,   3,  3,  3,  3,        1, 3, 1,        2,                 2,                2,                2,   4]
    
    Cw_list =           [3*Y, 2*Y, 2*Y,   1,   Y,    2*Y, Y, 2*Y, 3*Y, 2*Y, 3*Y,  Y,  2,  3,        1, 1, min(Y,4), 3,  int(MEMC_size/8),               1,                2,  2*Y]
    Ch_list =           [  2,   2,   2,   1,   1,    2,   1,   2,   2,   2,   2,  2,  2,  3,        1, 4, 4,        4,                 2,                2, int(MEMC_size/8),  5]
    Cc_list =           [3*X, 2*X, 2*X, 3*X, 3*X,  2*X,   X, 2*X, 3*X, 3*X, 3*X,  3,  X,  min(X,4), 1, 1, 3,        min(X,4),          1, int(MEMC_size/8),               1,  2*X]
    
    Xu_list =           [   X,  X,   X,   X,   X,    X,   X,   X,   X,   X,   X,  3,  X,  min(X,4), 1, 1, 3,        min(X,4),          1,                2,                1,   X]
    Yu_list =           [   Y,  Y,   Y,   1,   Y,    Y,   Y,   Y,   Y,   Y,   Y,  Y,  2,  3,        1, 1, min(Y,4), 3,                 2,                1,                2,   Y]
    preload_list =      [   1,  0,   1,   1,   1,    0,   1,   0,   1,   1,   1,  1,  1,  1,        1, 1, 1,        1,                 1,                1,                1,   1]
    
    FIXTESTS = [Bw_list, Bh_list, d_list, s_list, c_list, Cw_list, Ch_list, Cc_list, Xu_list, Yu_list, preload_list]

    return FIXTESTS

# ------------------------------
# POWER TESTS
# ------------------------------

def gen_power_tests(X, Y):

    Bw_list =       [3,3]
    Bh_list =       [3,3]
    d_list =        [1,1]
    s_list =        [1,1]
    c_list =        [64,64]
    
    Cw_list =       [Y,Y]
    Ch_list =       [4,4]
    Cc_list =       [X,X]
    
    Xu_list =       [X,X]
    Yu_list =       [Y,Y]
    preload_list =  [1,1]

    FIXTESTS = [Bw_list, Bh_list, d_list, s_list, c_list, Cw_list, Ch_list, Cc_list, Xu_list, Yu_list, preload_list]
    
    return FIXTESTS

# ------------------------------
# LIMIT (CORNERS) TESTS
# ------------------------------

def gen_limit_tests(TEST_PARAMS_DEF, PARAMS_LIST, X, Y):

    for i in range(len(TEST_PARAMS_DEF)-3):
        
        Xu = 1
        Yu = 1
        Bw = 1
        Bh = 1
        
        if i==0: Bw = TEST_PARAMS_DEF[0][2]
    
        if i==1: Bh = TEST_PARAMS_DEF[1][2]
        
        if i==2:
            PARAMS_LIST[2].append(TEST_PARAMS_DEF[2][2])
            Bw = 2  # We need a kernel bigger than one to test this
        else:
            PARAMS_LIST[2].append(TEST_PARAMS_DEF[2][1])
        
        if i==3:
            PARAMS_LIST[3].append(TEST_PARAMS_DEF[3][2])
            Bw = 2  # We need a kernel bigger than one to test this
        else:
            PARAMS_LIST[3].append(TEST_PARAMS_DEF[3][1])
        
        if i==4: PARAMS_LIST[4].append(TEST_PARAMS_DEF[4][2])
        else: PARAMS_LIST[4].append(TEST_PARAMS_DEF[4][1])
        
        if i==5:
            PARAMS_LIST[5].append(TEST_PARAMS_DEF[5][2])
            for y in range(Y,0,-1):
                if(TEST_PARAMS_DEF[5][2]%y)==0:
                    Yu = y
                    break
        else:
            PARAMS_LIST[5].append(TEST_PARAMS_DEF[5][1])
        
        if i==6:
            PARAMS_LIST[6].append(TEST_PARAMS_DEF[6][2])
        else:
            PARAMS_LIST[6].append(TEST_PARAMS_DEF[6][1])
    
        if i==7:
            PARAMS_LIST[7].append(TEST_PARAMS_DEF[7][2])
            for x in range(X,0,-1):
                if(TEST_PARAMS_DEF[7][2]%x)==0:
                    Xu = x
                    break
        else:
            PARAMS_LIST[7].append(TEST_PARAMS_DEF[7][1])
        
        PARAMS_LIST[0].append(Bw)
        PARAMS_LIST[1].append(Bh)
        
        PARAMS_LIST[8].append(Xu)
        PARAMS_LIST[9].append(Yu)
        PARAMS_LIST[10].append(1)
        
# ------------------------------
# RANDOM TESTS
# ------------------------------

def gen_random_tests(TEST_PARAMS_DEF, SRAM_SIZES, PARAMS_LIST, X, Y, DILP_W, PARAMS_W, N_tests, MAX_fraction=0.4, heuristic_BhCh=5e4, a=3, b=12, beta_vs_uniform=0.0):
    
    SRAMA_SIZE = SRAM_SIZES[0]
    SRAMB_SIZE = SRAM_SIZES[1]
    SRAMC_SIZE = SRAM_SIZES[2]
    
    SRAMA_SIZE_limit = SRAMA_SIZE*MAX_fraction
    SRAMB_SIZE_limit = SRAMB_SIZE*MAX_fraction
    SRAMC_SIZE_limit = SRAMC_SIZE*MAX_fraction
    
    t_offset = len(PARAMS_LIST[0])
    
    for t in range (N_tests):
        
        # Shuffle indexes -> All except Xu, Yu, preload_en => Fully determined at the end
        index_order = np.arange(len(PARAMS_LIST)-3)
        np.random.shuffle(index_order)
        
        # Choose Beta distribution vs Uniform wpb 'beta_vs_uniform' -> FOR SAMPLING
        beta = (np.random.random()>beta_vs_uniform)
        
        done_idx = []
        
        # For every parameter in random order
        for i in index_order:
            
            # Update constraints
            # ***********************
                
            # MEMORY SIZE - SRAMC
            Cw = PARAMS_LIST[5][t_offset+t] if 5 in done_idx else 1
            Ch = PARAMS_LIST[6][t_offset+t] if 6 in done_idx else 1
            Cc = PARAMS_LIST[7][t_offset+t] if 7 in done_idx else 1
            
            SRAMC_now = Cw*Ch*Cc
            
            # MEMORY SIZE - SRAMB
            Bw = PARAMS_LIST[0][t_offset+t] if 0 in done_idx else 1
            Bh = PARAMS_LIST[1][t_offset+t] if 1 in done_idx else 1
            ABc = PARAMS_LIST[4][t_offset+t] if 4 in done_idx else 1
            Bk = PARAMS_LIST[7][t_offset+t] if 7 in done_idx else 1
            
            SRAMB_now = Bw*Bh*ABc*Bk
            
            # MEMORY SIZE - SRAMA
            d = PARAMS_LIST[2][t_offset+t] if 2 in done_idx else 1
            s = PARAMS_LIST[3][t_offset+t] if 3 in done_idx else 1
                                    
            Aw = 1 + (Cw - 1)*s + 1 + (Bw - 1)*d - 1
            Ah = 1 + (Ch - 1)*s + 1 + (Bh - 1)*d - 1
                
            SRAMA_now = Aw*Ah*ABc
            
            # Get current allowable range
            # ************************************
            
            # B_w
            if   (i==0):
                A_limit = 1 + ((SRAMA_SIZE_limit/(Ah*ABc))-2-(Cw-1)*s)/d
                
                # Additional limit: full Bw_effective must be smaller than DILP_W
                Bw_limit = ((DILP_W-1)/(d))-1
                
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(A_limit), np.floor(SRAMB_SIZE_limit/SRAMB_now), np.floor(Bw_limit), TEST_PARAMS_DEF[i][2])]
            
            # B_h
            elif (i==1):
                A_limit = 1 + ((SRAMA_SIZE_limit/(Aw*ABc))-2-(Ch-1)*s)/d
                
                # Heuristic: reduce scale if Ch is larger than 1, otherwise tests are way too large
                if (Ch>1):
                    heuristic_lim = heuristic_BhCh/Ch
                else:
                    heuristic_lim = 1e9
                
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(A_limit), np.floor(SRAMB_SIZE_limit/SRAMB_now), np.floor(heuristic_lim), TEST_PARAMS_DEF[i][2])]
            
            # d
            elif (i==2):
                A_limit_roots = np.roots([(Bw*Bh-Bw-Bh+ABc), ABc*(s*(Bw*Ch+Bh*Cw-Bw-Bh-Cw-Ch+2) + 2*Bw+2*Bh-4), s*s*(Cw*Ch-Cw-Ch+ABc) + ABc*s*(2*Cw+2*Ch-4) + 4*ABc-SRAMA_SIZE_limit])
                
                # Discard complex results
                A_limit_roots = A_limit_roots*(np.imag(A_limit_roots)==0)
                
                # Take largest root and saturate small numbers to 1
                if len(A_limit_roots)>0:
                    A_limit = max(np.max(A_limit_roots), 1)
                else:
                    A_limit = 1
                
                # Additional limit: full Bw_effective must be smaller than DILP_W
                Bw_limit = (DILP_W-1)/(Bw-1) if (Bw>1) else (DILP_W-1)
                
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(A_limit), np.floor(Bw_limit), TEST_PARAMS_DEF[i][2])]
                
            # s
            elif (i==3):
                A_limit_roots = np.roots([(Cw*Ch-Cw-Ch+ABc), ABc*(d*(Cw*Bh+Ch*Bw-Cw-Ch-Bw-Bh+2) + 2*Cw+2*Ch-4), d*d*(Bw*Bh-Bw-Bh+ABc) + ABc*d*(2*Bw+2*Bh-4) + 4*ABc-SRAMA_SIZE_limit])

                # Discard complex results
                A_limit_roots = A_limit_roots*(np.imag(A_limit_roots)==0)
                
                # Take largest root and saturate small numbers to 1
                if len(A_limit_roots)>0:
                    A_limit = max(np.max(A_limit_roots), 1)
                else:
                    A_limit = 1
                
                # For additional limit we need to estimate the current Yused
                for y in range(Y,0,-1):
                    if(Cw%y)==0:
                        Yu = y
                        break
                
                # Additional limit: largest value must be smaller than 2**PARAMS_W - 1
                loc_woffs_limit = (2**PARAMS_W-1)/Yu
                
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(A_limit), np.floor(loc_woffs_limit), TEST_PARAMS_DEF[i][2])]

            # AB_c
            elif (i==4):
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(SRAMA_SIZE_limit/SRAMA_now), np.floor(SRAMB_SIZE_limit/SRAMB_now), TEST_PARAMS_DEF[i][2])]
           
            # C_w
            elif (i==5):
                A_limit = 1 + ((SRAMA_SIZE_limit/(Ah*ABc))-2-(Bw-1)*d)/s
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(A_limit), np.floor(SRAMC_SIZE_limit/SRAMC_now), TEST_PARAMS_DEF[i][2])]
            
            # C_h
            elif (i==6):
                A_limit = 1 + ((SRAMA_SIZE_limit/(Aw*ABc))-2-(Bh-1)*d)/s
                
                # Heuristic: reduce scale if Bh is larger than 1, otherwise tests are way too large
                if (Bh>1):
                    heuristic_lim = heuristic_BhCh/Bh
                else:
                    heuristic_lim = 1e9
                
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(A_limit), np.floor(SRAMC_SIZE_limit/SRAMC_now), np.floor(heuristic_lim), TEST_PARAMS_DEF[i][2])]
            
            # C_c
            elif (i==7):
                curr_range = [TEST_PARAMS_DEF[i][1], min(np.floor(SRAMC_SIZE_limit/SRAMC_now), np.floor(SRAMB_SIZE_limit/SRAMB_now), TEST_PARAMS_DEF[i][2])]
            
            # Limit right limit to min
            if (curr_range[1]<curr_range[0]) : curr_range[1] = curr_range[0]
            
            # Sample from distribution
            # *************************************************************
                        
            if (beta):                
                rand_sample = stats.beta.rvs(a,b)
            else:
                rand_sample = np.random.random()        # Continuous Uniform distribution

            # Scale to current range, quantize
            # *************************************************************

            param = int(np.round(rand_sample * (curr_range[1]-curr_range[0]) + curr_range[0]))  # Scale to range and quantize (round)
            
            PARAMS_LIST[i].append(param)
            done_idx.append(i)
    
        # Xused and Yused are fully determined by Cw and CC
        Cw = PARAMS_LIST[5][t_offset+t]
        Cc = PARAMS_LIST[7][t_offset+t]
    
        # Xused must be a multiple of Cc
        for x in range(X,0,-1):
            if(Cc%x)==0:
                Xu = x
                break
        
        # Yused must be a multiple of Cw
        for y in range(Y,0,-1):
            if(Cw%y)==0:
                Yu = y
                break
            
        PARAMS_LIST[8].append(Xu)
        PARAMS_LIST[9].append(Yu)
        PARAMS_LIST[10].append(int(np.random.random()>0.5))     # preload_en is just fully random
        
        # Final check
        Cw = PARAMS_LIST[5][t_offset+t]
        Ch = PARAMS_LIST[6][t_offset+t]
        Cc = PARAMS_LIST[7][t_offset+t]
        Bw = PARAMS_LIST[0][t_offset+t]
        Bh = PARAMS_LIST[1][t_offset+t]
        ABc = PARAMS_LIST[4][t_offset+t]
        Bk = PARAMS_LIST[7][t_offset+t]
        d = PARAMS_LIST[2][t_offset+t]
        s = PARAMS_LIST[3][t_offset+t]
                                
        Aw = 1 + (Cw - 1)*s + 1 + (Bw - 1)*d - 1
        Ah = 1 + (Ch - 1)*s + 1 + (Bh - 1)*d - 1
        
        N_As = Aw*Ah*ABc
        N_Bs = Bw*Bh*ABc*Cc
        N_Cs = Cw*Ch*Cc
        
        assert N_As <= SRAMA_SIZE, "Activations do not fit in Memory! {}/{} (Cw={}, Ch={}, Cc={}, ABc={}, Bw={}, Bh={}, d={}, s={})".format(N_As, SRAMA_SIZE, Cw, Ch, Cc, ABc, Bw, Bh, d, s)
        assert N_Bs <= SRAMB_SIZE, "Weights do not fit in Memory! {}/{} (Bw={}, Bh={}, ABc={}, Cc={})".format(N_Bs, SRAMB_SIZE, Bw, Bh, ABc, Cc)
        assert N_Cs <= SRAMC_SIZE, "Outputs do not fit in Memory! {}/{} (Cw={}, Ch={}, Cc={})".format(N_Cs, SRAMC_SIZE, Cw, Ch, Cc)

# -------------------------------------------
# EXTENSION OF RANDOM TESTS TO BIG TENSORS
# -------------------------------------------

def extend_random_tests(TESTS, TILEINFO, random_tests, max_tiles=10):
    
     N_random = len(random_tests[0])
     
     for i in range(N_random):
         
        Bw =        random_tests[0][i]
        Bh =        random_tests[1][i]
        d =         random_tests[2][i]
        s =         random_tests[3][i]
        c_til =     random_tests[4][i]
        w_til =     random_tests[5][i]
        h_til =     random_tests[6][i]
        k_til =     random_tests[7][i]
        Xu =        random_tests[8][i]
        Yu =        random_tests[9][i]
        preload =   random_tests[10][i]
         
        # Some values are maintained:
        TESTS[0].append(Bw)
        TESTS[1].append(Bh)
        TESTS[2].append(d)
        TESTS[3].append(s)
        
        TESTS[8].append(Xu)
        TESTS[9].append(Yu)
        TESTS[10].append(preload)
                
        # Some values are tile values:
        TILEINFO[0].append(c_til)  # c
        TILEINFO[1].append(k_til)  # k
        TILEINFO[2].append(h_til)  # h
        TILEINFO[3].append(w_til)  # w
        
        # Obtain max number of tiles to perform, at random:
        n_tiles = np.random.randint(low=1, high=max_tiles+1)
        
        # Obtain 4 numbers that multiplied will be smaller or equal to n_tiles
        rand_array = np.zeros((4), dtype=np.int)
        rand_array[0] = np.random.randint(low=1, high=max(2,np.ceil(n_tiles/2)))
        remaining_max = max(np.floor(n_tiles/rand_array[0]), 1)
        for i in range(3):
            rand_array[i+1] = np.random.randint(low=1, high=remaining_max+1)
            remaining_max = max(np.floor(remaining_max/rand_array[i+1]), 1)
            
        # Randomly shuffle vector elements
        np.random.shuffle(rand_array)

        AB_c =  c_til*rand_array[0]
        Cw =    w_til*rand_array[1]
        Ch =    h_til*rand_array[2]
        Cc =    k_til*rand_array[3]

        # Multiply the bigger shapes by the randomly generated integers
        TESTS[4].append(AB_c)   # c
        TESTS[5].append(Cw)     # w
        TESTS[6].append(Ch)     # h
        TESTS[7].append(Cc)     # k
        
# ------------------------------
# SMALL BENCHMARK TEST
# ------------------------------

def gen_small_bmk_tests(X, Y, MEMC_size):

    # Full convolution sizes
    Bw_list =       [3,    1,   7,   3]
    Bh_list =       [3,    1,   7,   3]
    d_list =        [1,    1,   1,   9]
    s_list =        [1,    1,   3,   1]
    c_list =        [64, 100,  16,  50]
    
    Cw_list =       [32,  64,   16,  8]
    Ch_list =       [16,   8,   8,   3]
    Cc_list =       [32,  32,   32,  32]
    
    Xu_list =       [X,    X,    X,  X]
    Yu_list =       [Y,    Y,    Y,  Y]
    preload_list =  [1,    1,    1,  1]

    # Tile sizes
    c_til_list =    [32, 100,   16,  25]
    k_til_list =    [32,  32,   16,  16]
    h_til_list =    [8,    4,    4,   3]
    w_til_list =    [32,  32,   16,   8]

    FIXTESTS = [Bw_list, Bh_list, d_list, s_list, c_list, Cw_list, Ch_list, Cc_list, Xu_list, Yu_list, preload_list]

    TILEINFO = [c_til_list, k_til_list, h_til_list, w_til_list]
    
    return FIXTESTS, TILEINFO

# -------------------------------------------
# BIG (TORTURE) BENCHMARK TEST - FIX TESTS
# -------------------------------------------

def gen_torture_bmk_fix_tests(X, Y, MEMC_size):

    # Full convolution sizes
    Bw_list =       [3,    1,   7,   3,   1,   5,    1,   3]
    Bh_list =       [3,    1,   7,   3,   1,   5,    1,   3]
    d_list =        [1,    1,   1,   9,   1,   6,    1,   3]
    s_list =        [1,    1,   3,   1,   1,   3,    1,   3]
    c_list =        [64, 111,  16,  64,  10,  16,  300,   3]
    
    Cw_list =       [64,  64,   32, 64,   3,  10,    2,   9]  
    Ch_list =       [ 4,   8,    4,  4,   2,   3,    2,   9]
    Cc_list =       [64,  64,   32, 32,   4,   5,    2,   9]
    
    Xu_list =       [X,    X,    X,  X,   1,   5,    1,   3]
    Yu_list =       [Y,    Y,    Y,  Y,   1,   5,    1,   3]
    preload_list =  [1,    1,    1,  1,   1,   1,    1,   3]

    # Tile sizes
    c_til_list =    [32, 111,   16, 16,   1,  16,    1,   3]
    k_til_list =    [32,  32,   16, 32,   1,   5,    1,   3]
    h_til_list =    [2,    4,    2,  2,   1,   1,    1,   3]
    w_til_list =    [32,  32,   16, 16,   1,   5,    1,   3]

    FIXTESTS = [Bw_list, Bh_list, d_list, s_list, c_list, Cw_list, Ch_list, Cc_list, Xu_list, Yu_list, preload_list]

    TILEINFO = [c_til_list, k_til_list, h_til_list, w_til_list]
    
    return FIXTESTS, TILEINFO

# ----------------------------------------------
# Get current Convolution Test limits
# ----------------------------------------------

def get_conv_limits():

    TEST_PARAMS_list = [
        ['Bw',      1,      64],
        ['Bh',      1,      min(HOPTS['MEMB_size'], HOPTS['MEMA_size'])],
        ['d',       1,      63],
        ['s',       1,      63],
        ['c',       1,      min(HOPTS['MEMB_size'], HOPTS['MEMA_size'])],
        ['Cw',      1,      HOPTS['MEMC_size']],
        ['Ch',      1,      HOPTS['MEMC_size']],
        ['Cc',      1,      min(HOPTS['MEMB_size'], HOPTS['MEMC_size'])],
        ['Xu',      1,      HOPTS['X']],
        ['Yu',      1,      HOPTS['Y']],
        ['preload', 0,      1],
    ]

    return TEST_PARAMS_list

# ------------------------------
# TEST GENERATION
# ------------------------------

def generate_tests():
    
    TILEINFO = []
    LIMITS = get_conv_limits()
    
    # Power test => Only two small convolutions
    if (TOPTS['test_type']=='power_estimation'):
        TESTS = gen_power_tests(HOPTS['X'], HOPTS['Y'])
                
    # Small benchmark test
    elif (TOPTS['test_type']=='bmk_small'):
        TESTS, TILEINFO = gen_small_bmk_tests(HOPTS['X'], HOPTS['Y'], HOPTS['MEMC_size'])
        
    # Big (torture) benchmark test
    elif (TOPTS['test_type']=='bmk_torture'):    
        
        # Fix tests
        TESTS, TILEINFO = gen_torture_bmk_fix_tests(HOPTS['X'], HOPTS['Y'], HOPTS['MEMC_size'])
            
        # Randomly generated tests with heuristic
        temp_TESTS = gen_void_tests()
        sram_sizes = [HOPTS['MEMA_size'], HOPTS['MEMB_size'], HOPTS['MEMC_size']]
        gen_random_tests(LIMITS, sram_sizes, temp_TESTS, HOPTS['X'], HOPTS['Y'], HOPTS['DILP_W'], HOPTS['PARAMS_W'], 32)
        
        # Extend random tests to several tiles
        extend_random_tests(TESTS, TILEINFO, temp_TESTS, 10)
    
    # Small convolutions validation
    elif (TOPTS['test_type']=='conv_validation'):    
                
        # Fix tests
        TESTS = gen_small_fix_tests(HOPTS['X'], HOPTS['Y'], HOPTS['MEMC_size'])
        
        # Limit/corner tests
        gen_limit_tests(LIMITS, TESTS, HOPTS['X'], HOPTS['Y'])
        
        # Randomly generated tests with heuristic
        sram_sizes = [HOPTS['MEMA_size'], HOPTS['MEMB_size'], HOPTS['MEMC_size']]
        gen_random_tests(LIMITS, sram_sizes, TESTS, HOPTS['X'], HOPTS['Y'], HOPTS['DILP_W'], HOPTS['PARAMS_W'], 70)
    
    # Unrecognized test type (error)
    else:
        assert 0, 'Could not recognize test_type = "{}"'.format(TOPTS['test_type'])

    return TESTS, TILEINFO, LIMITS

# --------------------------------
# Get systolic array dict
# --------------------------------

def get_sa_dict():
    
    SA_Param_dict = {
    
        'array_type' : 'OS'                 , # 'WS' or 'OS
        'OS_buff_K' : 1                     , # Number of internal buffers (K)
        
        'size_Y' : HOPTS['Y']                        , # Y size of the array
        'size_X' : HOPTS['X']                        , # X size of the array (irrelevant in this case)
    
        'ACT_IA_W' : HOPTS['IA_W'],
        'WEI_IB_W' : HOPTS['IB_W'],
        'ACT_SRAMA_W' : HOPTS['MEMA_W'],
        'WEI_SRAMB_W' : HOPTS['MEMB_W'],
        'ACT_WOFS_W' : HOPTS['IFM_WOFS_W'],
        'WEI_WOFS_W' : HOPTS['WEI_WOFS_W'],
        'ACY_FIFO_POSITIONS' : HOPTS['IFM_FIFO_POSITIONS'],
        'WEI_FIFO_POSITIONS' : HOPTS['WEI_FIFO_POSITIONS'],
        'FIFO_FILL_CYCLES' : HOPTS['FIFO_FILL_CYCLES'],
    
        'name' : "SA Parameter Dictionary"
    }
    
    return SA_Param_dict

# ------------------------------
# GET CURRENT CONVOLUTION DICT
# ------------------------------

def get_conv_dict(idx, TESTS, TILEINFO=[], check_mem_size=True, silent=False):
    
    B_w =           TESTS[0][idx]
    B_h =           TESTS[1][idx]
    d =             TESTS[2][idx]
    s =             TESTS[3][idx]
    c =             TESTS[4][idx]
    C_w =           TESTS[5][idx]
    C_h =           TESTS[6][idx]
    C_c =           TESTS[7][idx]
    X_used =        TESTS[8][idx]
    Y_used =        TESTS[9][idx]
    preload_en =    TESTS[10][idx]

    AB_c = c
   
    if (TOPTS['test_type'] in ['bmk_small','bmk_torture']):
        c_til =     TILEINFO[0][idx]
        k_til =     TILEINFO[1][idx]
        h_til =     TILEINFO[2][idx]
        w_til =     TILEINFO[3][idx]
    else:
        c_til =     c
        k_til =     C_c
        h_til =     C_h
        w_til =     C_w
   
    if not silent:
        print("Test number {}".format(idx+1))
        print("Bw={}, Bh={}, AB_c={}, C_w={}, C_h={}, C_c={}, s={}, d={}, Xu={}, Yu={}".format(B_w, B_h, AB_c, C_w, C_h, C_c, s, d, X_used, Y_used))
        print("------------------------------------------------------------")
        
    # Derived constants
    # --------------------------------------------------------------------------
    
    # Internal tiles for SAURIA execution
    X_tiles = int(w_til//Y_used)
    Y_tiles = int(h_til)
    K_tiles = int(k_til//X_used)
    
    # Number of context switches
    N_cswitch = X_tiles*Y_tiles*K_tiles    
        
    # Effective kernel size (receptive field)
    B_w_eff = 1 + (B_w - 1)*d
    B_h_eff = 1 + (B_h - 1)*d
    
    # Effective output size - How much the output center pixels over the Activations
    C_w_eff = 1 + (C_w - 1)*s
    C_h_eff = 1 + (C_h - 1)*s
    
    # Activation size - Effective output size bounded by the effective kernel size
    A_w = C_w_eff + B_w_eff - 1
    A_h = C_h_eff + B_h_eff - 1
    A_c = AB_c
        
    if (TOPTS['test_type'] in ['bmk_small','bmk_torture']):
        C_w_eff_til = 1 + (w_til - 1)*s
        C_h_eff_til = 1 + (h_til - 1)*s
        
        A_w_til = C_w_eff_til + B_w_eff - 1
        A_h_til = C_h_eff_til + B_h_eff - 1
    else:
        A_w_til = A_w
        A_h_til = A_h
    
    # Memory size check
    # --------------------------------------------------------------------------
    
    if (check_mem_size):
    
        if not (TOPTS['test_type'] in ['bmk_small','bmk_torture']):
            N_As = A_w*A_h*AB_c
            N_Bs = B_w*B_h*AB_c*C_c
            N_Cs = C_w*C_h*C_c
        
        else:
            N_As = A_w_til*A_h_til*c_til
            N_Bs = B_w*B_h*c_til*k_til
            N_Cs = w_til*h_til*k_til
            
        assert N_As <= HOPTS['MEMA_size'], "Activations do not fit in Memory! {}/{}".format(N_As, HOPTS['MEMA_size'])
        assert N_Bs <= HOPTS['MEMB_size'], "Weights do not fit in Memory! {}/{}".format(N_Bs, HOPTS['MEMB_size'])
        assert N_Cs <= HOPTS['MEMC_size'], "Outputs do not fit in Memory! {}/{}".format(N_Cs, HOPTS['MEMC_size'])
    
    # Derived config parameters
    # ---------------------------------------------------------------------------------------
    
    # Threshold fix to zero (for now...)
    thres = 0
        
    # Dilation pattern generation
    Dil_str = '0b'
    for i in range(HOPTS['DILP_W']):
        
        if (i%d == 0) and (i//d < B_w):
            Dil_str = Dil_str + '1'
        else:
            Dil_str = Dil_str + '0'

    Dil_pat = int(Dil_str, 2)
    
    # Row & column masks generation
    rows_active_str = '0b'
    rows_active_arr = np.zeros(HOPTS['Y'], dtype=np.bool)
    cols_active_str = '0b'
    cols_active_arr = np.zeros(HOPTS['X'], dtype=np.bool)
    
    for j in range(HOPTS['Y']):
        if (j<Y_used):
            rows_active_str = rows_active_str + '1'
            rows_active_arr[j] = 1
        else:
            rows_active_str = rows_active_str + '0'
            
    for i in range(HOPTS['X']):
        if (i<X_used):
            cols_active_str = cols_active_str + '1'
            cols_active_arr[i] = 1
        else:
            cols_active_str = cols_active_str + '0'
    
    rows_active = int(rows_active_str, 2)
    cols_active = int(cols_active_str, 2)
    
    # Local woffs
    lwoffs = rows_active_arr*np.arange(HOPTS['Y'])*s
    
    CONV = {
        "B_w" : B_w,
        "B_h" : B_h,
        "C_w" : C_w,
        "C_h" : C_h,
        "C_c" : C_c,
        "A_w" : A_w,
        "A_h" : A_h,
        "A_c" : A_c,
        "AB_c" : AB_c,
        "d" : d,
        "s" : s,
        
        "w_til" : w_til,
        "h_til" : h_til,
        "c_til" : c_til,
        "k_til" : k_til,
        "A_w_til" : A_w_til,
        "A_h_til" : A_h_til,
        
        "B_w_eff" : B_w_eff,
        "B_h_eff" : B_h_eff,
        
        "X_tiles" : X_tiles,
        "Y_tiles" : Y_tiles,
        "K_tiles" : K_tiles,
        "N_cswitch" : N_cswitch,
        
        "X_used" : X_used,
        "Y_used" : Y_used,
        "preload_en" : preload_en,
        
        "Dil_pat" : Dil_pat,
        "rows_active" : rows_active,
        "cols_active" : cols_active,
        "lwoffs" : lwoffs,
        "thres" : thres
        }
    
    return CONV

# ------------------------------
# UPDATE TESTCFG
# ------------------------------

def testcfg_update(testcfg_list, dram_offset, dram_region_len, CONV):

    c_til_iter = int(CONV['AB_c']/CONV['c_til'])
    k_til_iter = int(CONV['C_c']/CONV['k_til'])
    w_til_iter = int(CONV['C_w']/CONV['w_til'])
    h_til_iter = int(CONV['C_h']/CONV['h_til'])
    
    total_iter = c_til_iter*k_til_iter*w_til_iter*h_til_iter
    
    testcfg_list.append(total_iter)
    testcfg_list.append(dram_offset)
    testcfg_list.append(dram_offset+dram_region_len-1)

# ------------------------------
# GENERATE OUTPUT FILES
# ------------------------------

def generate_test_outputs(DRAM_mem, DRAM_mem_gold, controller_regs, testcfg_list, N_tests):
    
    N_VECTORS = 50*N_tests
            
    # Fill config arrays
    # ----------------------------------
    cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out = generate_controller_cmds(controller_regs, N_VECTORS)

    # Create & organize output matrices
    # ----------------------------------
    
    Input_Matrix = np.zeros((N_VECTORS, 5), dtype=np.uint64)
    Output_Matrix = np.zeros((N_VECTORS, 2), dtype=np.uint64)
    
    Input_Matrix[:,0] = dsth.convert_to_intN(cfg_data_in, HOPTS['CFG_AXI_DATA_WIDTH'])
    Input_Matrix[:,1] = dsth.convert_to_intN(cfg_address, HOPTS['CFG_AXI_ADDR_WIDTH'])
    Input_Matrix[:,2] = cfg_wren
    Input_Matrix[:,3] = cfg_rden
    Input_Matrix[:,4] = cfg_waitflag

    Output_Matrix[:,0] = cfg_data_out
    Output_Matrix[:,1] = cfg_checkflag
        
    # Save output matrices
    # ----------------------------------

    # Append string to add to file names (mark approximate values)
    app_str = "" if not HOPTS['approx_comp'] else "_approx"

    # Select folder depending on the test
    if (TOPTS['test_type'] == 'bmk_small'):
        folder = "../test/stimuli/bmk_small/"
    elif (TOPTS['test_type'] == 'bmk_torture'):
        folder = "../test/stimuli/bmk_torture/"
    else:
        folder = "../test/stimuli/conv_validation/"

    # Save matrices
    np.savetxt(folder+"GoldenStimuli"+app_str+".txt", Input_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"GoldenOutputs"+app_str+".txt", Output_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"initial_dram"+app_str+".txt", DRAM_mem, fmt='%01X', delimiter=' ')
    np.savetxt(folder+"gold_dram"+app_str+".txt", DRAM_mem_gold, fmt='%01X', delimiter=' ')
    
    # Generate and save test config file
    N_total = np.sum(testcfg_list[::3])
    testcfg_list.insert(0,N_total)
    testcfg_list.insert(0, N_tests)
    
    np.savetxt(folder+"tstcfg"+app_str+".txt", np.array(testcfg_list), fmt='%01X', delimiter=' ')

def generate_controller_cmds(controller_regs, N_VECTORS):

    picos_regs_array = np.array(controller_regs, dtype=np.uint64).astype(np.int64)

    # Split 64-bit picos regs into 32-bit DMA controller config words
    dmactrl_regs_array = np.zeros([picos_regs_array.shape[0],2*picos_regs_array.shape[1]], np.int64)

    dmactrl_regs_array[:,0::2] = picos_regs_array & 0xFFFFFFFF
    dmactrl_regs_array[:,1::2] = (picos_regs_array >> 32) & 0xFFFFFFFF

    # Create control words
    cfg_address = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_data_in = np.zeros((N_VECTORS), dtype=np.uint64)
    cfg_wren = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_rden = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_waitflag = np.zeros((N_VECTORS), dtype=np.uint32)
    
    cfg_checkflag = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_data_out = np.zeros((N_VECTORS), dtype=np.uint64)

    offs = HOPTS['CTRL_offset']

    idx=0

    # Enable interrupts initially
    cfg_address[idx] =    0x8
    cfg_data_in[idx] =    3
    cfg_wren[idx] =       1
    idx+=1

    for test_regs in dmactrl_regs_array:
        # Write cfg registers
        for i, reg in enumerate(test_regs):
            cfg_address[idx] =    offs+0x10+(i<<2)
            cfg_data_in[idx] =    reg
            cfg_wren[idx] =       1
            idx+=1

        # Start control FSM
        cfg_address[idx] =    0x0
        cfg_data_in[idx] =    3
        cfg_wren[idx] =       1
        idx+=1

        # Wait for completion
        cfg_waitflag[idx] =   1
        idx+=1

        # Lower interrupts
        cfg_address[idx] =    0xC
        cfg_data_in[idx] =    3
        cfg_wren[idx] =       1
        idx+=1

        # Check flag
        cfg_checkflag[idx] =  1
        idx+=2


    return cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out

