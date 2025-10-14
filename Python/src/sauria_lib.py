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
import subprocess

sys.path.insert(1, './../')
import src.config_helper as cfg
import src.data_helper as dh
import src.file_helper as fh
import src.execution_model as ex
import src.test_helper as th

# ---import src.test_helper as th-----------------------------
# For compatibility with old functions (TODO: clean up and use same dicts everywhere!)
# --------------------------------

def get_sa_dict(HOPTS):
    
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

def get_conv_dict(tensor_shapes, TILING_DICT, HOPTS, preloads=0, d=1, s=1, p=0):
    
    B_w =           tensor_shapes[1][3]
    B_h =           tensor_shapes[1][2]
    d =             d
    s =             s
    c =             tensor_shapes[1][1]
    C_w =           tensor_shapes[2][2]
    C_h =           tensor_shapes[2][1]
    C_c =           tensor_shapes[2][0]
    X_used =        TILING_DICT['X_used']
    Y_used =        TILING_DICT['Y_used']
    preload_en =    preloads

    c_til =     TILING_DICT['tile_cin']
    k_til =     TILING_DICT['C_tile_shape'][0]
    h_til =     TILING_DICT['C_tile_shape'][1]
    w_til =     TILING_DICT['C_tile_shape'][2]

    # Derived constants
    # --------------------------------------------------------------------------
    
    AB_c = c

    # Internal tiles for SAURIA execution
    X_int_tiles = int(w_til//Y_used)
    Y_int_tiles = int(h_til)
    K_int_tiles = int(k_til//X_used)
    
    # Number of context switches
    N_cswitch = X_int_tiles*Y_int_tiles*K_int_tiles    
        
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
    
    # Size of A tiles
    C_w_eff_til = 1 + (w_til - 1)*s
    C_h_eff_til = 1 + (h_til - 1)*s
    
    A_w_til = C_w_eff_til + B_w_eff - 1
    A_h_til = C_h_eff_til + B_h_eff - 1
       
    # External tiles
    X_ext_tiles = int(C_w//w_til)
    Y_ext_tiles = int(C_h//h_til)
    C_ext_tiles = int(A_c//c_til)
    K_ext_tiles = int(C_c//k_til)
    N_total_tiles = X_ext_tiles*Y_ext_tiles*C_ext_tiles*K_ext_tiles

    # Memory size check
    # --------------------------------------------------------------------------

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
        
        "X_ext_tiles" : X_ext_tiles,
        "Y_ext_tiles" : Y_ext_tiles,
        "K_ext_tiles" : K_ext_tiles,
        "C_ext_tiles" : C_ext_tiles,
        "N_total_tiles" : N_total_tiles,

        "B_w_eff" : B_w_eff,
        "B_h_eff" : B_h_eff,
        
        "X_int_tiles" : X_int_tiles,
        "Y_int_tiles" : Y_int_tiles,
        "K_int_tiles" : K_int_tiles,
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

# ---------------------------------------------
# Full SAURIA Operation, including RTL simulation
# ---------------------------------------------

def Conv2d_SAURIA(A_tensor, B_tensor, C_preload, C_golden, CONV_DICT, HOPTS, generate_vcd=False, assert_no_errors = False, max_mem_size=0x800000, print_statistics=True, silent=True):

    DRAM_mem = np.zeros((max_mem_size), dtype=np.uint8)
    DRAM_mem_gold = np.zeros((max_mem_size), dtype=np.uint8)
                                        
    # Write values into simulated main memory
    offsets = dh.assign_dram_values(A_tensor, B_tensor, C_preload, C_golden, 0, DRAM_mem, DRAM_mem_gold, CONV_DICT, HOPTS)

    # Generate SAURIA config registers    
    sauria_regs, N_REGS = cfg.get_sauria_regs(CONV_DICT, HOPTS, silent=True)

    # Heuristically evaluate the loop order
    _,_,_,loop_order = ex.get_tiling_loops(CONV_DICT)
    
    # Get controller configuration for the hardware
    controller_args = cfg.get_controller_regs(CONV_DICT, sauria_regs, N_REGS, offsets, loop_order)

    # Save Test outputs
    fh.generate_test_files(DRAM_mem, DRAM_mem_gold, controller_args, [offsets[0],offsets[2],offsets[3]], 1, HOPTS)
    
    # Execute the simulation in Verilator
    cwd = os.getcwd()
    os.chdir("../../test/verilator")
    f1 = open("verilator_run.log","w")
    if generate_vcd:
        subprocess.call(["sh","./run_sauria_test.sh", "new.vcd"],stdout=f1)
    else:
        subprocess.call(["sh","./run_sauria_test.sh"],stdout=f1)
    os.chdir(cwd)

    # Retrieve the output values
    out_values, stats_dict, n_test_errors = fh.parse_test_outputs(HOPTS)
    out_values = out_values[:C_preload.size]

    # Transform integer into real values if needed
    if HOPTS['OP_TYPE'] == 1:
        out_values = dh.decode_FP_array(out_values, 10, 5)

    # Reshape into final form
    output_tensor = np.reshape(out_values, C_preload.shape)

    # SAURIA statistics & performance metrics
    # -----------------------------------------
    stats_dict['total_ops'] = 2*CONV_DICT['A_c']*CONV_DICT['B_w']*CONV_DICT['B_h']*CONV_DICT['C_w']*CONV_DICT['C_h']*CONV_DICT['C_c']
    stats_dict['tile_ops'] = 2*CONV_DICT['c_til']*CONV_DICT['B_w']*CONV_DICT['B_h']*CONV_DICT['w_til']*CONV_DICT['h_til']*CONV_DICT['k_til']

    # Virtual time runs at 10 GHz (0.1 ns), SAURIA runs at 500 MHz -> Division factor of 20
    # also, substract 120 units for the reset
    stats_dict['total_cycles'] = int((stats_dict['sim_time']-120)//20)

    # Throughput in ops/cycle
    stats_dict['ideal_throughput'] = HOPTS['X']*HOPTS['Y']*2
    stats_dict['total_throughput'] = stats_dict['total_ops']/stats_dict['total_cycles']
    stats_dict['tile_throughput'] = stats_dict['tile_ops']/stats_dict['1tile_SAURIA_cycles']

    # Compute utilization
    stats_dict['total_utilization'] = stats_dict['total_throughput']/stats_dict['ideal_throughput']
    stats_dict['tile_utilization'] = stats_dict['tile_throughput']/stats_dict['ideal_throughput']

    # Memory utilization
    stats_dict['total_MEMA_kB'] = (HOPTS['MEMA_size']*HOPTS['IA_W'])/(8*1024)
    stats_dict['total_MEMB_kB'] = (HOPTS['MEMB_size']*HOPTS['IB_W'])/(8*1024)
    stats_dict['total_MEMC_kB'] = (HOPTS['MEMC_size']*HOPTS['OC_W'])/(8*1024)

    stats_dict['used_MEMA_kB'] = (CONV_DICT['A_w_til']*CONV_DICT['A_h_til']*CONV_DICT['c_til']*HOPTS['IA_W'])/(8*1024)
    stats_dict['used_MEMB_kB'] = (CONV_DICT['c_til']*CONV_DICT['B_w']*CONV_DICT['B_h']*CONV_DICT['k_til']*HOPTS['IB_W'])/(8*1024)
    stats_dict['used_MEMC_kB'] = (CONV_DICT['w_til']*CONV_DICT['h_til']*CONV_DICT['k_til']*HOPTS['OC_W'])/(8*1024)

    stats_dict['MEMA_utilization'] = stats_dict['used_MEMA_kB']/stats_dict['total_MEMA_kB']
    stats_dict['MEMB_utilization'] = stats_dict['used_MEMB_kB']/stats_dict['total_MEMB_kB']
    stats_dict['MEMC_utilization'] = stats_dict['used_MEMC_kB']/stats_dict['total_MEMC_kB']

    # Total tiles & sources of inefficiency
    stats_dict['total_tiles'] = CONV_DICT['N_total_tiles']
    stats_dict['total_accel_only_cycles'] = stats_dict['1tile_SAURIA_cycles']*stats_dict['total_tiles']

    stats_dict['total_accel_stalls'] = stats_dict['1tile_SAURIA_stalls']*stats_dict['total_tiles']
    stats_dict['accel_waiting_cycles'] = stats_dict['total_cycles'] - stats_dict['total_accel_only_cycles']

    if not silent:
        if n_test_errors==0:
            print("\n              TEST PASSED\n")
        else:
            print("\n    TEST FAILED WITH {} ERRORS! :'(\n".format(n_test_errors))

        if print_statistics:
            print("****************************************")
            print("          SAURIA STATISTICS")
            print("****************************************")
            print("Total cycles:\t\t\t\t{}".format(stats_dict['total_cycles']))
            print("Total operations:\t\t\t{}".format(stats_dict['total_ops']))
            print("Average Throughput:\t\t\t{:.2f} OP/cycle ({:.2f} %)".format(stats_dict['total_throughput'], 100*stats_dict['total_utilization']))
            print("")
            print("Number of tiles:\t\t\t{}".format(stats_dict['total_tiles']))
            print("Core stall cycles:\t\t\t{} ({:.2f} %)".format(stats_dict['total_accel_stalls'], 100*stats_dict['total_accel_stalls']/stats_dict['total_cycles']))
            print("Memory/CGF stall cycles:\t\t{} ({:.2f} %)".format(stats_dict['accel_waiting_cycles'], 100*stats_dict['accel_waiting_cycles']/stats_dict['total_cycles']))
            print("")
            print("SAURIA memory capacity (A|B|C):\t\t{} | {} | {} [kB]".format(stats_dict['total_MEMA_kB'], stats_dict['total_MEMB_kB'], stats_dict['total_MEMC_kB']))
            print("Utilized memory:\t\t\t{} | {} | {} [kB] ({:.2f} | {:.2f} | {:.2f} [%])".format(stats_dict['used_MEMA_kB'], stats_dict['used_MEMB_kB'], stats_dict['used_MEMC_kB'], 100*stats_dict['MEMA_utilization'], 100*stats_dict['MEMB_utilization'], 100*stats_dict['MEMC_utilization']))

    if assert_no_errors: assert n_test_errors==0, "There were functional errors. Stopping."

    return output_tensor, stats_dict

# -------------------------------------------------------
# Full SAURIA test, including random tensor generation
# -------------------------------------------------------

def generate_and_run_test(tensor_shapes, tiling_dict, d, s, HOPTS, preload=True, compute_macs=False, generate_vcd=False, pzero_tensors=[0,0,0], insert_deadbeef=True, gauss_scale=1, ones_test=False, assert_no_errors=False, print_statistics=True, silent=True):

    # Get convolution configuration
    CONV_DICT = get_conv_dict(tensor_shapes, tiling_dict, HOPTS, d=d, s=s, preloads=preload)

    # Generate A, B, C random tensors
    A_tensor, B_tensor, C_preload = dh.generate_tensors(CONV_DICT, HOPTS, pzero=pzero_tensors, insert_deadbeef=insert_deadbeef)
    if not preload: C_preload[:]=0

    # Perform convolution with systolic array model
    C_golden, partial_macs, _ = ex.get_ideal_results(A_tensor, B_tensor, C_preload, CONV_DICT, HOPTS, get_sa_dict(HOPTS), compute_macs=compute_macs)
                 
    # Execute convolution
    SAURIA_outputs, SAURIA_stats = Conv2d_SAURIA(A_tensor, B_tensor, C_preload, C_golden, CONV_DICT, HOPTS, generate_vcd=generate_vcd, print_statistics=print_statistics, silent=silent)
           
    return SAURIA_outputs, SAURIA_stats, partial_macs

