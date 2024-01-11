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

# ----------------------------
# Set bits - helper function
# ----------------------------

def set_bits(x, msb, lsb, val):
   mask = 0
   for i in range(msb-lsb+1):
      mask = (mask << 1) | 1
   return (x & ~(mask << lsb)) | ((val & mask) << lsb)

# ----------------------------
# Generate PICOS regs
# ----------------------------

def get_controller_regs(CONV, HYPER, sauria_regs, dram_base_addresses, loop_order, silent=True):

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
    
    tile_weights_k_step = Ck_til
    tile_weights_c_step = Ac_til*Ck*Bw*Bh
    
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
    
    dma_weights_w_step = Ck

    # Set 64-bit arguments to be passed to Picos
    args = [0]*17
    args[0] = set_bits(args[0], 11, 0,  tile_x_lim)
    args[0] = set_bits(args[0], 23, 12, tile_y_lim)
    args[0] = set_bits(args[0], 35, 24, tile_c_lim)
    args[0] = set_bits(args[0], 47, 36, tile_k_lim)
    args[0] = set_bits(args[0], 59, 48, tile_psums_x_step)
    args[0] = set_bits(args[0], 63, 60, tile_psums_y_step)
    args[1] = set_bits(args[1], 19, 0,  tile_psums_y_step >> 4)
    args[1] = set_bits(args[1], 43, 20, tile_psums_k_step)
    args[1] = set_bits(args[1], 55, 44, tile_ifmaps_x_step)
    args[1] = set_bits(args[1], 63, 56, tile_ifmaps_y_step)
    args[2] = set_bits(args[2], 15, 0,  tile_ifmaps_y_step >> 8)
    args[2] = set_bits(args[2], 39, 16, tile_ifmaps_c_step)
    args[2] = set_bits(args[2], 51, 40, tile_weights_k_step)
    args[2] = set_bits(args[2], 63, 52, tile_weights_c_step)
    args[3] = set_bits(args[3], 11, 0,  tile_weights_c_step >> 12)
    args[3] = set_bits(args[3], 23, 12, dma_ifmaps_y_lim)
    args[3] = set_bits(args[3], 35, 24, dma_ifmaps_c_lim)
    args[3] = set_bits(args[3], 47, 36, dma_psums_y_step)
    args[3] = set_bits(args[3], 63, 48, dma_psums_k_step)
    args[4] = set_bits(args[4], 7,  0,  dma_psums_k_step >> 16)
    args[4] = set_bits(args[4], 19, 8,  dma_ifmaps_y_step)
    args[4] = set_bits(args[4], 43, 20, dma_ifmaps_c_step)
    args[4] = set_bits(args[4], 55, 44, dma_weights_w_step)
    args[4] = set_bits(args[4], 63, 56, dma_ifmaps_ett)
    args[5] = set_bits(args[5], 15, 0,  dma_ifmaps_ett >> 8)
    args[5] = set_bits(args[5], 47, 16, dram_base_addresses[0])
    args[5] = set_bits(args[5], 63, 48, dram_base_addresses[1])
    args[6] = set_bits(args[6], 15, 0,  dram_base_addresses[1] >> 16)
    args[6] = set_bits(args[6], 47, 16, dram_base_addresses[2])
    args[6] = set_bits(args[6], 49, 48, loop_order)
    args[6] = set_bits(args[6], 50, 50, 0)              #stand alone
    args[6] = set_bits(args[6], 51, 51, 0)              #keep A
    args[6] = set_bits(args[6], 52, 52, 0)              #keep B
    args[6] = set_bits(args[6], 53, 53, 0)              #keep C
    args[6] = set_bits(args[6], 54, 54, 0)              #disable start
    args[6] = set_bits(args[6], 55, 55, Cw == Cw_til)
    args[6] = set_bits(args[6], 56, 56, Ch == Ch_til)
    args[6] = set_bits(args[6], 57, 57, Ck == Ck_til)
    
    sauria_acc_args = sauria_regs[:,1]
    
    args[7] = (sauria_acc_args[1] << 32) | sauria_acc_args[0]
    args[8] = (sauria_acc_args[3] << 32) | sauria_acc_args[2]
    args[9] = (sauria_acc_args[5] << 32) | sauria_acc_args[4]
    args[10] = (sauria_acc_args[7] << 32) | sauria_acc_args[6]
    args[11] = (sauria_acc_args[9] << 32) | sauria_acc_args[8]
    args[12] = (sauria_acc_args[11] << 32) | sauria_acc_args[10]
    args[13] = (sauria_acc_args[13] << 32) | sauria_acc_args[12]
    args[14] = (sauria_acc_args[15] << 32) | sauria_acc_args[14]
    args[15] = (sauria_acc_args[17] << 32) | sauria_acc_args[16]
    args[16] = (sauria_acc_args[19] << 32) | sauria_acc_args[18]

    return args