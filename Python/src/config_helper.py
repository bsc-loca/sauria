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

# -------------------------------------------------------------
# Utilities
# -------------------------------------------------------------

def bmask(bit_width):
    return ((2**bit_width)-1)

def set_bits(x, msb, lsb, val):
   mask = 0
   for i in range(msb-lsb+1):
      mask = (mask << 1) | 1
   return (x & ~(mask << lsb)) | ((val & mask) << lsb)

# -------------------------------------------------------------
# Parse SAURIA register configuration
# -------------------------------------------------------------

def parse_reg_config(ALL_SIGNALS, TOTAL_REGS, Y, IF_W, silent=True):
    
    regs = np.zeros((TOTAL_REGS), dtype=np.uint32)
    regs_idx = 0

    for r, region in enumerate(ALL_SIGNALS):
           
        current_idx = 0
        current_lsb_bit = 0
        current_msb_bit = 0
        
        for i, signal in enumerate(region):
                        
            # Dilation pattern is a "special" case => Occupies several registers itself
            if (r==1) and (i==10):
                
                if not silent:
                    print("\n{} mapped in:".format(signal[0]))
                    print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx, current_lsb_bit))
                
                accumulated_bits = 0
                
                for k in range(int(np.ceil((signal[1]+current_lsb_bit)/IF_W))):
                    
                    # LSBs from first register
                    if(k==0):
                        regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))<<current_lsb_bit)&0xFFFFFFFF)
                        
                        accumulated_bits += (IF_W-current_lsb_bit)
                        current_idx += 1
                        regs_idx += 1
                    
                    # MSBs from last register
                    elif(k==(int(np.ceil((signal[1]+current_lsb_bit)/IF_W))-1)):
                        regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))>>accumulated_bits)&0xFFFFFFFF)
                        
                        current_msb_bit = signal[1]-accumulated_bits-1

                        # Prep for next array position
                        if (current_msb_bit == (IF_W-1)):
                            current_lsb_bit = 0
                            current_idx += 1
                            regs_idx += 1
                        else:
                            current_lsb_bit = current_msb_bit + 1

                    # Other bits from intermediate registers
                    else:
                        regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))>>accumulated_bits)&0xFFFFFFFF)
                        
                        accumulated_bits += IF_W
                        current_idx += 1
                        regs_idx += 1
            
                if not silent: print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
            
            # Local woffs is another "special" case => Array of Y values spanning over several registers
            elif (r==1) and (i==12):
                
                # Loop through all array positions
                for y in range(Y):
                    
                    current_msb_bit = current_lsb_bit + signal[1]-1
                
                    # If we go to next register
                    if(current_msb_bit >= IF_W):
                        current_msb_bit = current_msb_bit - IF_W
                        regs[regs_idx] = regs[regs_idx] | (((signal[2][y]&bmask(signal[1]))<<current_lsb_bit)&0xFFFFFFFF)
                        regs[regs_idx+1] = regs[regs_idx+1] | ((signal[2][y]&bmask(signal[1]))>>(IF_W-current_lsb_bit))
                        
                        current_idx += 1
                        regs_idx += 1
                    
                        if not silent:
                            print("\n{} mapped in:".format(signal[0]))
                            print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx-1, current_lsb_bit))
                            print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
                    
                    # If contained in current register
                    else:
                        regs[regs_idx] = regs[regs_idx] | ((signal[2][y]&bmask(signal[1]))<<current_lsb_bit)
                    
                        if not silent:
                            print("\n{} mapped in:".format(signal[0]))
                            print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx, current_lsb_bit))
                            print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
    
                    # Prep for next array position
                    if (y<Y-1):
                        if (current_msb_bit == (IF_W-1)):
                            current_lsb_bit = 0
                            current_idx += 1
                            regs_idx += 1
                        else:
                            current_lsb_bit = current_msb_bit + 1
        
                # Final Prep for next array position
                if i==(len(region)-1):
                    current_lsb_bit = 0
                    current_idx += 1
                    regs_idx += 1
                else:
                    if (current_msb_bit == (IF_W-1)):
                        current_lsb_bit = 0
                        current_idx += 1
                        regs_idx += 1
                    else:
                        current_lsb_bit = current_msb_bit + 1
        
            # Otherwise we map procedurally
            else:
                        
                current_msb_bit = current_lsb_bit + signal[1]-1
                
                # If we go to next register
                if(current_msb_bit >= IF_W):
                    current_msb_bit = current_msb_bit - IF_W
                    regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))<<current_lsb_bit)&0xFFFFFFFF)
                    regs[regs_idx+1] = regs[regs_idx+1] | ((signal[2]&bmask(signal[1]))>>(IF_W-current_lsb_bit))
                    
                    current_idx += 1
                    regs_idx += 1
                
                    if not silent:
                        print("\n{} mapped in:".format(signal[0]))
                        print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx-1, current_lsb_bit))
                        print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
                
                # If contained in current register
                else:
                    regs[regs_idx] = regs[regs_idx] | ((signal[2]&bmask(signal[1]))<<current_lsb_bit)
    
                    if not silent:
                        print("\n{} mapped in:".format(signal[0]))
                        print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx, current_lsb_bit))
                        print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
    
    
                if i==(len(region)-1):
                    current_lsb_bit = 0
                    current_idx += 1
                    regs_idx += 1
                else:
                    if (current_msb_bit == (IF_W-1)):
                        current_lsb_bit = 0
                        current_idx += 1
                        regs_idx += 1
                    else:
                        current_lsb_bit = current_msb_bit + 1
                        
    return regs

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
    TH_W = HYPER['TH_W']
    DILP_W = HYPER['DILP_W']
    PARAMS_W = HYPER['PARAMS_W']
    
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
    
    region_regs = np.ceil(region_bits/HYPER['CFG_AXI_DATA_WIDTH'])
    TOTAL_REGS = int(region_regs.sum())
    
    # Prepare registe values    
    reg_allocation = parse_reg_config(ALL_SIGNALS, TOTAL_REGS, Y, HYPER['CFG_AXI_DATA_WIDTH'], silent=silent)

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
            
            address = offset + (i<<2) + HYPER['CORE_offset']
            regval = reg_allocation[regidx]
            
            register_config[regidx,0] = address
            register_config[regidx,1] = regval
            regidx+=1    

    return register_config, TOTAL_REGS

# ----------------------------
# Generate SAURIA controller config regs
# ----------------------------

def get_controller_regs(CONV, sauria_regs, N_REGS, dram_base_addresses, loop_order, silent=True):

    Bw = CONV['B_w']
    Bh = CONV['B_h']
    s = CONV['s']
    d = CONV['d']

    Cw = CONV['C_w']
    Ch = CONV['C_h']
    Ck = CONV['C_c']
    Aw = CONV['A_w']
    Ah = CONV['A_h']
    Ac = CONV['A_c']
    
    Cw_til = CONV['w_til']
    Ch_til = CONV['h_til']
    Ck_til = CONV['k_til']
    Aw_til = CONV['A_w_til']
    Ah_til = CONV['A_h_til']
    Ac_til = CONV['c_til']

    # WXfer_op -> always optimize weights shape for memory transfers
    WXfer_op = True

    tile_x_lim = int(Cw/Cw_til) - 1
    tile_y_lim = int(Ch/Ch_til) - 1
    tile_k_lim = int(Ck/Ck_til) - 1
    tile_c_lim = int(Ac/Ac_til) - 1
    
    tile_psums_x_step = Cw_til
    tile_psums_y_step = Ch_til*Cw
    tile_psums_k_step = Ck_til*Cw*Ch
    
    tile_ifmaps_x_step = s*Cw_til
    tile_ifmaps_y_step = s*Ch_til*Aw
    tile_ifmaps_c_step = Ac_til*Aw*Ah
    
    if WXfer_op:
        tile_weights_k_step = Ck_til*Bw*Bh*Ac
        tile_weights_c_step = Ck_til*Bw*Bh*Ac_til
        dma_weights_w_step = Ck_til     # Meaning is different!
        Ck_eq = True
    else:
        tile_weights_k_step = Ck_til
        tile_weights_c_step = Ac_til*Ck*Bw*Bh
        dma_weights_w_step = Ck
        Ck_eq = (Ck == Ck_til)

    dma_psums_y_step = Cw
    dma_psums_k_step = Ch*Cw
    
    if Aw == Aw_til and Ah == Ah_til:
       dma_ifmaps_y_lim = 0
       dma_ifmaps_c_lim = 0
       dma_ifmaps_ett = Ac_til*Aw*Ah
    elif Aw == Aw_til:
       dma_ifmaps_y_lim = 0
       dma_ifmaps_c_lim = Ac_til-1
       dma_ifmaps_ett = Ah_til*Aw
    else:
       dma_ifmaps_y_lim = Ah_til-1
       dma_ifmaps_c_lim = Ac_til-1
       dma_ifmaps_ett = Aw_til
    
    dma_ifmaps_y_step = Aw
    dma_ifmaps_c_step = Ah*Aw

    # Set 64-bit arguments to be passed to Picos
    args = [0]*(22 + N_REGS)

    args[0] = set_bits(args[0], 15, 0,  tile_x_lim)
    args[0] = set_bits(args[0], 31, 16, tile_y_lim)

    args[1] = set_bits(args[1], 15, 0,  tile_c_lim)
    args[1] = set_bits(args[1], 31, 16, tile_k_lim)

    args[2] = set_bits(args[2], 31, 0, tile_psums_x_step)
    args[3] = set_bits(args[3], 31, 0, tile_psums_y_step)
    args[4] = set_bits(args[4], 31, 0, tile_psums_k_step)
    args[5] = set_bits(args[5], 31, 0, tile_ifmaps_x_step)
    args[6] = set_bits(args[6], 31, 0, tile_ifmaps_y_step)
    args[7] = set_bits(args[7], 31, 0, tile_ifmaps_c_step)
    args[8] = set_bits(args[8], 31, 0, tile_weights_k_step)
    args[9] = set_bits(args[9], 31, 0, tile_weights_c_step)
    args[10] = set_bits(args[10], 31, 0, dma_ifmaps_y_lim)
    args[11] = set_bits(args[11], 31, 0, dma_ifmaps_c_lim)
    args[12] = set_bits(args[12], 31, 0, dma_psums_y_step)
    args[13] = set_bits(args[13], 31, 0, dma_psums_k_step)
    args[14] = set_bits(args[14], 31, 0, dma_ifmaps_y_step)
    args[15] = set_bits(args[15], 31, 0, dma_ifmaps_c_step)
    args[16] = set_bits(args[16], 31, 0, dma_weights_w_step)
    args[17] = set_bits(args[17], 31, 0, dma_ifmaps_ett)
    args[18] = set_bits(args[18], 31, 0, dram_base_addresses[0])
    args[19] = set_bits(args[19], 31, 0, dram_base_addresses[1])
    args[20] = set_bits(args[20], 31, 0, dram_base_addresses[2])

    args[21] = set_bits(args[21], 17, 16, loop_order)
    args[21] = set_bits(args[21], 18, 18, 0)              #stand alone
    args[21] = set_bits(args[21], 19, 19, 0)              #keep A
    args[21] = set_bits(args[21], 20, 20, 0)              #keep B
    args[21] = set_bits(args[21], 21, 21, 0)              #keep C
    args[21] = set_bits(args[21], 22, 22, 0)              #disable start
    args[21] = set_bits(args[21], 23, 23, Cw == Cw_til)
    args[21] = set_bits(args[21], 24, 24, Ch == Ch_til)
    args[21] = set_bits(args[21], 25, 25, Ck_eq)
    args[21] = set_bits(args[21], 31, 31, WXfer_op)
    
    # Set SAURIA regs, which are already packed and can span a variable number of regs
    sauria_acc_args = sauria_regs[:,1]
    
    args[22:] = sauria_acc_args

    return args

# ----------------------------
# Write and read transactions via AXIL
# ----------------------------

def wr_transaction(idx, cfg_list, address, data_in):
    cfg_list[0][idx] =  address     # cfg_address
    cfg_list[1][idx] =  data_in     # cfg_data_in
    cfg_list[2][idx] =  1           # cfg_wren
    cfg_list[3][idx] =  0           # cfg_rden
    cfg_list[4][idx] =  0           # cfg_waitflag
    cfg_list[5][idx] =  0           # cfg_checkflag
    cfg_list[6][idx] =  0           # cfg_data_out
    return idx+1

def rd_transaction(idx, cfg_list, address, data_gold, check_golden=True):
    cfg_list[0][idx] =  address     # cfg_address
    cfg_list[1][idx] =  0           # cfg_data_in
    cfg_list[2][idx] =  0           # cfg_wren
    cfg_list[3][idx] =  1           # cfg_rden
    cfg_list[4][idx] =  0           # cfg_waitflag
    cfg_list[5][idx] =  check_golden# cfg_checkflag
    cfg_list[6][idx] =  data_gold   # cfg_data_out
    return idx+1

# ----------------------------
# AXIL transactions to configure the controller
# ----------------------------

def generate_controller_cmds(controller_regs, N_VECTORS, HOPTS):

    ctrl_regs_array = np.array(controller_regs, dtype=np.uint64).astype(np.int64)

    # Create control words
    cfg_address = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_data_in = np.zeros((N_VECTORS), dtype=np.uint64)
    cfg_wren = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_rden = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_waitflag = np.zeros((N_VECTORS), dtype=np.uint32)
    
    cfg_checkflag = np.zeros((N_VECTORS), dtype=np.uint32)
    cfg_data_out = np.zeros((N_VECTORS), dtype=np.uint64)

    cfg = [cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out]

    offs = HOPTS['CTRL_offset']
    idx=0

    # Enable interrupts initially
    idx = wr_transaction(idx,cfg, offs+0x8,3)

    # Write cfg registers
    for i, reg in enumerate(ctrl_regs_array):
        idx = wr_transaction(idx,cfg, offs+0x10+(i<<2),reg)

    # Start control FSM
    idx = wr_transaction(idx,cfg, offs+0x0,3)

    # Wait for completion
    cfg_waitflag[idx] =   1
    idx+=1

    # Lower interrupts
    idx = wr_transaction(idx,cfg, offs+0xC,3)

    # READ STATISTICS - Total cycle counter
    idx = rd_transaction(idx,cfg, HOPTS['CORE_offset']+0x14,0,check_golden=False)

    # READ STATISTICS - Stall cycle counter
    idx = rd_transaction(idx,cfg, HOPTS['CORE_offset']+0x18,0,check_golden=False)

    # Check flag -> Finishes test!
    cfg_checkflag[idx] =  1
    idx+=2

    return cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out
