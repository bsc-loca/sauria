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
from helpers import test_helper as th
from helpers import config_parser as cfg_p
from helpers import drac_sa_top_helper as dsth

# -------------------------------------------------------------
# Get SAURIA register values for a Convolution/GeMM
# -------------------------------------------------------------

def get_sauria_regs(CONV, HYPER, silent=True):

    # Retrieve convolution variables
    B_w = CONV['B_w']
    B_h = CONV['B_h']
    s = CONV['s']
    d = CONV['d']
    
    # For SAURIA configuration, these refer to the TILES! (we don't care about the big tensor shape)
    C_w = CONV['w_til']
    C_h = CONV['h_til']
    C_c = CONV['k_til']
    A_w = CONV['A_w_til']
    A_h = CONV['A_h_til']
    AB_c = CONV['c_til']

    B_w_eff = CONV['B_w_eff']
    B_h_eff = CONV['B_h_eff']
    N_cswitch = CONV['N_cswitch']
    
    Y_used = CONV['Y_used']
    X_used = CONV['X_used']
    preload_en = CONV['preload_en']
    Dil_pat = CONV['Dil_pat']
    rows_active = CONV['rows_active']
    cols_active = CONV['cols_active']
    lwoffs = CONV['lwoffs']
    thres = CONV['thres']
    
    X = HYPER['X']
    Y = HYPER['Y']
    SRAMA_N = HYPER['MEMA_N']
    SRAMB_N = HYPER['MEMB_N']
    SRAMC_N = HYPER['MEMC_N']
    
    SRAMC_N = HYPER['MEMC_N']
    ACT_IDX_W = HYPER['IFM_IDX_W']
    WEI_IDX_W = HYPER['WEI_IDX_W']
    OUT_IDX_W = HYPER['PSM_IDX_W']
    TH_W = th.HOPTS['TH_W']
    DILP_W = th.HOPTS['DILP_W']
    PARAMS_W = th.HOPTS['PARAMS_W']
    
    # -------------------------------
    # COMPUTE CONFIGURATION VALUES
    # -------------------------------

    # Aligned weights condition => feeder optimization   
    o_waligned = (C_c%SRAMB_N==0) and (X_used==SRAMB_N)
                    
    # Aligned activations condition => Only when 1x1 convolution and no dilation or strides is applied
    if (s==1) and (d==1) and (B_w==1) and (B_h==1) and (AB_c%SRAMA_N == 0) and (Y_used%SRAMA_N==0):
            o_xlim = Y_used
    else:
            o_xlim = (1 + (Y_used-1)*s) + B_w_eff + 1-(B_w_eff%2) + SRAMA_N
        
    # Prepare regions of signals
    CONTROL_SIGNALS = [
        ['o_incntlim',      ACT_IDX_W,      1*B_w*B_h*AB_c - 1],
        ['o_act_reps',      OUT_IDX_W,      int(np.ceil(C_c/X_used))],
        ['o_wei_reps',      OUT_IDX_W,      int(np.ceil(C_w/Y_used)*np.ceil(C_h/1))],
        ['o_thres',         TH_W,           thres]
    ]
    
    ACTIVATION_SIGNALS = [
        ['o_xlim',          ACT_IDX_W,      o_xlim],
        ['o_xstep',         ACT_IDX_W,      SRAMA_N],
        ['o_ylim',          ACT_IDX_W,      A_w*B_h_eff],
        ['o_ystep',         ACT_IDX_W,      A_w*d],
        ['o_chlim',         ACT_IDX_W,      A_w*A_h*AB_c],
        ['o_chstep',        ACT_IDX_W,      A_w*A_h],
        ['o_til_xlim',      ACT_IDX_W,      int(np.ceil(C_w/Y_used))*Y_used*s],
        ['o_til_xstep',     ACT_IDX_W,      Y_used*s],
        ['o_til_ylim',      ACT_IDX_W,      int(np.ceil(C_h/1))*A_w*1*s],
        ['o_til_ystep',     ACT_IDX_W,      A_w*1*s],
        ['o_Dil_pat',       DILP_W,         Dil_pat],
        ['o_rows_active',   Y,              rows_active],
        ['o_loc_woffs',     PARAMS_W,       lwoffs]
    ]
    
    WEIGHT_SIGNALS = [
        ['o_wlim',          WEI_IDX_W,      C_c*B_w*B_h*AB_c],
        ['o_wstep',         WEI_IDX_W,      C_c],
        ['o_klim',          WEI_IDX_W,      SRAMB_N+1 if (not o_waligned) else 1],
        ['o_kstep',         WEI_IDX_W,      SRAMB_N],
        ['o_til_klim',      WEI_IDX_W,      C_c],
        ['o_til_kstep',     WEI_IDX_W,      X_used],
        ['o_cols_active',   X,              cols_active],
        ['o_waligned',      1,              o_waligned],
    ]
    
    OUTPUT_SIGNALS = [
        ['o_ncontexts',     OUT_IDX_W,      N_cswitch],
        ['o_cxlim',         OUT_IDX_W,      Y_used + SRAMC_N],
        ['o_cxstep',        OUT_IDX_W,      SRAMC_N],
        ['o_cklim',         OUT_IDX_W,      C_w*C_h*X_used],
        ['o_ckstep',        OUT_IDX_W,      C_w*C_h],
        ['o_til_cylim',     OUT_IDX_W,      C_w*C_h],
        ['o_til_cystep',    OUT_IDX_W,      Y_used],
        ['o_til_cklim',     OUT_IDX_W,      C_w*C_h*C_c],
        ['o_til_ckstep',    OUT_IDX_W,      C_w*C_h*X_used],
        ['o_inactive_cols', PARAMS_W,       X-X_used],
        ['o_preload_en',    1,              preload_en]
    ]
    
    ALL_SIGNALS = [CONTROL_SIGNALS, ACTIVATION_SIGNALS, WEIGHT_SIGNALS, OUTPUT_SIGNALS]
    
    # Compute total bits per region
    region_bits = np.zeros((len(ALL_SIGNALS)), dtype=np.int)
    for r, region in enumerate(ALL_SIGNALS):
        for i, signal in enumerate(region):
            if (r==1) and (i==12):
                region_bits[r] += Y*signal[1]
            else:
                region_bits[r] += signal[1]
    
    region_regs = np.ceil(region_bits/th.HOPTS['CFG_AXI_DATA_WIDTH'])
    TOTAL_REGS = int(region_regs.sum())
    
    # Prepare registe values    
    reg_allocation = cfg_p.parse_reg_config(ALL_SIGNALS, TOTAL_REGS, Y, th.HOPTS['CFG_AXI_DATA_WIDTH'], silent=silent)

    # Pack everything into array with addresses 
    register_config = np.zeros((TOTAL_REGS,2), np.uint32)
    regidx = 0
    
    # Control Registers
    for r, nregs in enumerate(region_regs):
        for i in range(int(nregs)):
            
            if (r==0):      offset = HYPER['CFG_CON_offset']
            elif (r==1):    offset = HYPER['CFG_IFM_offset']
            elif (r==2):    offset = HYPER['CFG_WEI_offset']
            else:           offset = HYPER['CFG_PSM_offset']
            
            address = offset + (i<<2) + th.HOPTS['CORE_offset']
            regval = reg_allocation[regidx]
            
            register_config[regidx,0] = address
            register_config[regidx,1] = regval
            regidx+=1    

    return register_config

# -------------------------------------------------------------
# Flatten & encode A,B,C,C_out tensors
# -------------------------------------------------------------

def flatten_tensors(A_tensor, B_tensor, C_tensor, C_output, CONV, HYPER):
    
    # Normal convolution
    A_tensor_flat = A_tensor.flatten()
    C_tensor_flat = C_tensor.flatten()
    C_output_flat = C_output.flatten()
    
    # Weights tensor has the output channel dimension contiguous!
    B_tensor_flat = np.moveaxis(B_tensor, 0, -1).flatten()
                
    # If FP mode, encode values
    if (HYPER['OP_TYPE']==1):
        A_tensor_flat = dsth.convert_to_FP(A_tensor_flat, th.HOPTS['IA_MANT'], HYPER['IA_W'])
        B_tensor_flat = dsth.convert_to_FP(B_tensor_flat, th.HOPTS['IB_MANT'], HYPER['IB_W'])
        C_tensor_flat = dsth.convert_to_FP(C_tensor_flat, th.HOPTS['IC_MANT'], HYPER['OC_W'])
        C_output_flat = dsth.convert_to_FP(C_output_flat, th.HOPTS['IC_MANT'], HYPER['OC_W'])
        
    return A_tensor_flat, B_tensor_flat, C_tensor_flat, C_output_flat

# ------------------------------------------------------
# Pack array values of any bitwidth as contiguous bytes
# ------------------------------------------------------

def pack_as_bytes(MEM, data_array, start_bit_index, bit_width):

    # Initialize bit index
    bit_idx = start_bit_index

    for el in data_array.astype(int):
        
        start_bit = bit_idx
        end_bit = bit_idx + bit_width - 1

        start_byte = int(np.floor(start_bit/8))
        end_byte = int(np.floor(end_bit/8))

        written_bits = 0
        remaining_bits = bit_width
        for b_pos in range(start_byte, end_byte+1):

            mem_offs = bit_idx % 8
            curr_bits = min(min(bit_width, 8 - mem_offs), remaining_bits)
            elm_offs = written_bits

            MEM[b_pos] = MEM[b_pos] | (((el >> elm_offs) << mem_offs) & 0xFF)

            bit_idx += curr_bits
            written_bits += curr_bits
            remaining_bits -= curr_bits

    return bit_idx

# ------------------------------------------------------
# Writes the tensors into a DRAM memory region
# ------------------------------------------------------

def write_dram_values(A_tensor, B_tensor, C_tensor, C_output, dram_offset, DRAM_mem, DRAM_mem_gold, CONV, HYPER):
    
    # Get flat & encoded tensors
    A_tensor_flat, B_tensor_flat, C_tensor_flat, C_output_flat = flatten_tensors(A_tensor, B_tensor, C_tensor, C_output, CONV, HYPER)

    A_bit_width = HYPER['IA_W']
    B_bit_width = HYPER['IB_W']
    C_bit_width = HYPER['OC_W']

    # Initialize bit index
    bit_idx = 8*dram_offset

    # Write inputs
    A_tensor_offset = int(np.floor(bit_idx/8))
    _ =         pack_as_bytes(DRAM_mem,         A_tensor_flat, bit_idx, A_bit_width)
    bit_idx =   pack_as_bytes(DRAM_mem_gold,    A_tensor_flat, bit_idx, A_bit_width)    # Gold has a copy of the inputs

    # Force new region to start on a NEW BYTE
    bit_idx = 8*int(np.ceil(bit_idx/8))

    # Write weights
    B_tensor_offset = int(np.floor(bit_idx/8)) 
    _ =         pack_as_bytes(DRAM_mem,         B_tensor_flat, bit_idx, B_bit_width)
    bit_idx =   pack_as_bytes(DRAM_mem_gold,    B_tensor_flat, bit_idx, B_bit_width)    # Gold has a copy of the weights

    # Force new region to start on a NEW BYTE
    bit_idx = 8*int(np.ceil(bit_idx/8))

    # Write preloads and results
    C_tensor_offset = int(np.floor(bit_idx/8)) 
    _ =         pack_as_bytes(DRAM_mem,         C_tensor_flat, bit_idx, C_bit_width)    # PRELOADS
    bit_idx =   pack_as_bytes(DRAM_mem_gold,    C_output_flat, bit_idx, C_bit_width)    # RESULTS

    # Total number of bytes
    region_len = int(np.ceil(bit_idx/8)) - dram_offset

    return [A_tensor_offset, B_tensor_offset, C_tensor_offset, region_len]
