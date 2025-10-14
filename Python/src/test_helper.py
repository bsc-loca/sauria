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
import scipy.stats as stats

import os 
import subprocess

sys.path.insert(1, './../')
import src.config_helper as cfg
import src.data_helper as dh

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

def get_conv_limits(HOPTS):

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

# --------------------------------------
# Configuration & debug bus test
# --------------------------------------

def run_cfg_test(HOPTS, assert_no_error=False, test_dir="../../test"):

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

    cfg_list = [cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out]

    # Debug test
    # ----------------------------------

    idx = 0

    # READ SAURIA VERSION
    version_value = HOPTS['X'] + (HOPTS['Y']<<8) + ((HOPTS['IB_W']-1)<<16) + ((HOPTS['IA_W']-1)<<20) + ((HOPTS['OP_TYPE'])<<24)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS['CORE_offset']+0x1C,     version_value)

    # ACCESS CONTROLLER REGISTERS
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CTRL_offset"]+0x0,      0xC000_0000)
    idx+=5 # Wait
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CTRL_offset"]+0x10,     0xDEAD_BEEF)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CTRL_offset"]+0x48,     0xBEEF_DEAD)
    idx+=5 # Wait
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CTRL_offset"]+0x10,     0xDEAD_BEEF)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CTRL_offset"]+0x48,     0xBEEF_DEAD)
    idx+=50 # Wait

    # ACCESS ReDMA REGISTERS
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["DMA_offset"]+0x0,       0x2D00_0000)
    idx+=5 # Wait
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["DMA_offset"]+0x10,      0xDEAD_BEEF)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["DMA_offset"]+0x30,      0xBEEF_DEAD)
    idx+=5 # Wait
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["DMA_offset"]+0x10,      0xDEAD_BEEF)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["DMA_offset"]+0x30,      0xBEEF_DEAD)
    idx+=50 # Wait

    # ACCESS SAURIA REGISTERS
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+0x0,      0xAC00_000C)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_CON_offset"],    0xDEAD_C201)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_IFM_offset"],    0xDEAD_1F9A)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_WEI_offset"],    0xDEAD_3E16)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_PSM_offset"],    0xDEAD_FE59)
    idx+=5 # Wait
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_CON_offset"],    0xDEAD_C201)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_IFM_offset"],    0xDEAD_1F9A)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_WEI_offset"],    0xDEAD_3E16)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["CFG_PSM_offset"],    0xDEAD_FE59)
    idx+=50 # Wait

    # ACCESS SAURIA MEMORIES
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["MEMA_offset"]+0x10,     0xDEAD_9E91)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["MEMB_offset"]+0x50,     0xDEAD_9E92)
    idx = cfg.wr_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["MEMC_offset"]+0x90,     0xDEAD_9E93)
    idx+=10 # Wait
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["MEMA_offset"]+0x10,     0xDEAD_9E91)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["MEMB_offset"]+0x50,     0xDEAD_9E92)
    idx = cfg.rd_transaction(idx,cfg_list, HOPTS["CORE_offset"]+HOPTS["MEMC_offset"]+0x90,     0xDEAD_9E93)
    idx+=50 # Wait

    # ACCESS UNMAPPED REGIONS
    idx = cfg.wr_transaction(idx,cfg_list,   0x3333_3333,    0xDEEE_AAAD)    # Wrong high level mapping
    idx+=5 # Wait
    idx = cfg.rd_transaction(idx,cfg_list,   0x3333_3333,    0x0BAD_ADD2)    # Wrong high level mapping
    idx+=5 # Wait
    idx = cfg.wr_transaction(idx,cfg_list,   HOPTS["CTRL_offset"]+0xFF,       0xDEEE_AAAD)    # Unmapped regions
    idx = cfg.wr_transaction(idx,cfg_list,   HOPTS["DMA_offset"]+0x38,        0xDEEE_AAAD)    # Unmapped regions
    idx = cfg.wr_transaction(idx,cfg_list,   HOPTS["CORE_offset"]+0x30,       0xDEEE_AAAD)    # Unmapped regions
    idx = cfg.wr_transaction(idx,cfg_list,   HOPTS["CORE_offset"]+0x1000,     0xDEEE_AAAD)    # Unmapped regions
    idx = cfg.wr_transaction(idx,cfg_list,   HOPTS["CORE_offset"]+0xF_0000,   0xDEEE_AAAD)    # Unmapped regions
    idx+=5 # Wait
    idx = cfg.rd_transaction(idx,cfg_list,   HOPTS["CTRL_offset"]+0xFF,       0x1BAD_ADD2)    # Unmapped regions
    idx = cfg.rd_transaction(idx,cfg_list,   HOPTS["DMA_offset"]+0x38,        0x3BAD_ADD2)    # Unmapped regions
    idx = cfg.rd_transaction(idx,cfg_list,   HOPTS["CORE_offset"]+0x30,       0x2BAD_ADD2)    # Unmapped regions
    idx = cfg.rd_transaction(idx,cfg_list,   HOPTS["CORE_offset"]+0x1000,     0x2BAD_ADD2)    # Unmapped regions
    idx = cfg.rd_transaction(idx,cfg_list,   HOPTS["CORE_offset"]+0xF_0000,   0x4BAD_ADD2)    # Unmapped regions

    # Create & organize output matrices
    # ----------------------------------

    Input_Matrix = np.zeros((N_VECTORS, 7), dtype=np.uint64)
    
    DRAM_mem = np.zeros(1000, dtype=np.uint8)
    DRAM_mem_gold = np.zeros(1000, dtype=np.uint8)

    Input_Matrix[:,0] = dh.convert_to_intN(cfg_data_in, HOPTS['CFG_AXI_DATA_WIDTH'])
    Input_Matrix[:,1] = dh.convert_to_intN(cfg_address, HOPTS['CFG_AXI_ADDR_WIDTH'])
    Input_Matrix[:,2] = cfg_wren
    Input_Matrix[:,3] = cfg_rden
    Input_Matrix[:,4] = cfg_waitflag
    Input_Matrix[:,5] = cfg_data_out
    Input_Matrix[:,6] = cfg_checkflag

    # Save output matrices
    # ----------------------------------

    folder = "../../test/"

    # Save matrices
    np.savetxt(os.path.join(test_dir, "stimuli/GoldenStimuli.txt"), Input_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(os.path.join(test_dir, "stimuli/initial_dram.txt"), DRAM_mem, fmt='%01X', delimiter=' ')
    np.savetxt(os.path.join(test_dir, "stimuli/gold_dram.txt"), DRAM_mem_gold, fmt='%01X', delimiter=' ')
    
    # Generate and save (dummy) test config file
    testcfg_list = [1,1,1]
    np.savetxt(os.path.join(test_dir, "stimuli/tstcfg.txt"), np.array(testcfg_list), fmt='%01X', delimiter=' ')

    # Execute the simulation in Verilator
    cwd = os.getcwd()
    os.chdir(folder+"verilator")
    subprocess.call(["./Test-Sim","+check_read_values"])
    os.chdir(cwd)

    # Test outputs now look different, however, the last value is always the number of errors
    stats_outputs = np.loadtxt(os.path.join(test_dir, "outputs/test_stats.txt"), dtype=int)
    n_errors = stats_outputs[-1]

    if n_errors==0:
        print("TEST PASSED! :)")
    else:
        print("TEST FAILED! :(")
        if assert_no_error: assert n_errors==0, "FAILED - THERE WERE ERRORS IN THE TEST!"

# -----------------------------------
# TILEINFO FOR SINGLE TILE TESTS
# -----------------------------------

def get_single_tile_info(TESTS):
    TILEINFO = [
        TESTS[4],    # c_til = C_in
        TESTS[7],    # k_til = C_out
        TESTS[6],    # h_til = Ch
        TESTS[5],    # w_til = Cw
    ]
    return TILEINFO

# ------------------------------
# TEST GENERATION
# ------------------------------

def generate_tests(TOPTS, HOPTS):
    
    LIMITS = get_conv_limits(HOPTS)
    
    # Power test => Only two small convolutions
    if (TOPTS['test_type']=='power_estimation'):
        TESTS = gen_power_tests(HOPTS['X'], HOPTS['Y'])
        TILEINFO = get_single_tile_info(TESTS)
                
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
    
        TILEINFO = get_single_tile_info(TESTS)

    # Debug test (uses alternative flow, parameters ignored)
    elif (TOPTS['test_type']=='debug_test'):
        TESTS = [[1]]
        TILEINFO = [[1]]

    # Unrecognized test type (error)
    else:
        assert 0, 'Could not recognize test_type = "{}"'.format(TOPTS['test_type'])

    return TESTS, TILEINFO, LIMITS