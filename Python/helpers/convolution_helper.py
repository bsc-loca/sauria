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
import torch
import sys

from helpers import test_helper as th

sys.path.insert(1, './../')

import model.analytical_model as SA_model
import model.matmul_helper as mh

from model.approx.fp import FP_Madd

# --------------------------------------------
# Perform convolution / GeMM
# --------------------------------------------

def get_ideal_results(A_tensor, B_tensor, C_tensor, CONV, HYPER, SA_dict, compute_macs=False):

    # Put convolution parameters into SA dictionary
    SA_dict['AB_c'] =       CONV['AB_c']
    SA_dict['B_w'] =        CONV['B_w']
    SA_dict['B_h'] =        CONV['B_h']
    SA_dict['B_k'] =        CONV['C_c']
    SA_dict['d'] =          CONV['d']
    SA_dict['s'] =          CONV['s']
    SA_dict['X_used'] =     CONV['X_used']
    SA_dict['Y_used'] =     CONV['Y_used']
    SA_dict['C_w'] =        CONV['C_w']
    SA_dict['C_h'] =        CONV['C_h']
    SA_dict['C_c'] =        CONV['C_c']
    SA_dict['A_w'] =        CONV['A_w']
    SA_dict['A_h'] =        CONV['A_h'] 

    SA_dict['MANT_bits'] =      th.HOPTS['IA_MANT']
    SA_dict['approx_comp'] =    th.HOPTS['approx_comp']
    SA_dict['mul_type'] =       th.HOPTS['mul_type']
    SA_dict['M'] =              th.HOPTS['M']
    SA_dict['add_type'] =       th.HOPTS['add_type']
    SA_dict['A'] =              th.HOPTS['A']
    SA_dict['rounding'] =       th.HOPTS['rounding']
 
    # Tiling loops
    c_til_iter = int(CONV['AB_c']/ CONV['c_til'])
    k_til_iter = int(CONV['C_c']/CONV['k_til'])
    w_til_iter = int(CONV['C_w']/CONV['w_til'])
    h_til_iter = int(CONV['C_h']/CONV['h_til'])
    iter_list = [c_til_iter,k_til_iter,w_til_iter,h_til_iter]
    
    # Tensor tile shapes
    A_tile_shape = [CONV['c_til'], CONV['A_h_til'], CONV['A_w_til']]
    B_tile_shape = [CONV['c_til'], CONV['B_w']*CONV['B_h'], CONV['k_til']]
    C_tile_shape = [CONV['k_til'], CONV['h_til'], CONV['w_til']]
    
    # Decision on inner and outer loops (ACCELERATOR-LEVEL STATIONARITY)
    _, map_iter_list, id_list, loop_order = get_tiling_loops(A_tile_shape, B_tile_shape, C_tile_shape, iter_list, CONV)

    # ONLY FOR DEBUGGING - Replicate the exact compute order as the hardware (SLOW)
    if compute_macs:

        tensors = [A_tensor, B_tensor, C_tensor]
        C_output, partial_macs = cycle_accurate_convolution(CONV, HYPER, tensors, SA, map_iter_list, id_list)

    # If not debugging, compute the convolution as a single systolic array job
    else:
        partial_macs = [0,0,0]

        # Convolution => Do it with model mapping
        torch_A_tensor = torch.from_numpy(A_tensor.astype(np.float32))
        
        B_conv = torch.nn.Conv2d(CONV['AB_c'], CONV['C_c'], (CONV['B_h'], CONV['B_w']), stride=CONV['s'], dilation=CONV['d'])
        
        B_conv.weight = torch.nn.Parameter(torch.tensor(B_tensor.astype(np.float32)))
        B_conv.bias = torch.nn.Parameter(torch.zeros(B_conv.bias.shape))
        
        data_type = 'FP' if (HYPER['OP_TYPE']==1) else 'int'
        
        _, _, _, _, C_output, _, _, _ = SA_model.map_conv_to_MVM(SA_dict, random_tensors=False, A_tensor=torch_A_tensor, B_conv=B_conv, preloads=C_tensor, data_type=data_type, silent=True)
        
        C_output = C_output.astype(HYPER['intyp'])
                    
    return C_output, partial_macs, loop_order

# ------------------------------------------------------------
# Compute intermediate MAC values for debugging (takes time)
# ------------------------------------------------------------

def compute_partial_macs(A_Mats, B_Mats, C_tensor, CONV, HYPER):

    X_used = CONV['X_used']
    Y_used = CONV['Y_used']
    N_cswitch = CONV['N_cswitch']
    intyp = HYPER['intyp']

    N_values_per_ctx = CONV['B_w']*CONV['B_h']*CONV['AB_c']
            
    # Convolution => Need some mapping
    C_pre = np.zeros((N_cswitch, X_used, Y_used), dtype=intyp)
    
    til = 0
    for k in range(CONV['K_tiles']):
        for y in range(CONV['Y_tiles']):
            for x in range(CONV['X_tiles']):
                    
                C_pre[til] = C_tensor[X_used*k:X_used*(k+1), y, Y_used*x:Y_used*(x+1)]
                til += 1
                
    A_Mats = np.reshape(A_Mats[:,:Y_used], (N_cswitch, N_values_per_ctx, Y_used)).astype(intyp)
    B_Mats = np.reshape(B_Mats[:,:X_used], (N_cswitch, N_values_per_ctx, X_used)).astype(intyp)
        
    # Initialize arrays
    partial_ops = np.zeros((N_cswitch, N_values_per_ctx+1, X_used, Y_used), dtype=intyp)
    partial_muls = np.zeros((N_cswitch, N_values_per_ctx+1, X_used, Y_used), dtype=intyp)
    
    partial_ops[:,0] = C_pre
    
    idx = 0
    for ctx in range(N_cswitch):
        for idx in range(1,N_values_per_ctx+1):
            
            for y in range(Y_used):
                for x in range(X_used):
            
                    # Zero gating => Quite important for efficiency!
                    if (A_Mats[ctx, idx-1, y]!=0) and (B_Mats[ctx, idx-1, x]!=0):        
            
                        # Exact version
                        if not th.HOPTS['approx_comp']:
                            partial_muls[ctx, idx, x, y] = A_Mats[ctx, idx-1, y] * B_Mats[ctx, idx-1, x]
                            partial_ops[ctx, idx, x, y] = partial_ops[ctx, idx-1, x, y] + partial_muls[ctx, idx, x, y]

                        # Approx version
                        else:
                            _,_,partial_ops[ctx, idx, x, y] =   FP_Madd(A_Mats[ctx, idx-1, y], B_Mats[ctx, idx-1, x], partial_ops[ctx, idx-1, x, y], MANT_bits=th.HOPTS['IA_MANT'], N_bits=HYPER['IA_W'], MulType=th.HOPTS['mul_type'], m=th.HOPTS['M'], AdderType=th.HOPTS['add_type'], A=th.HOPTS['A'], rounding=th.HOPTS['rounding'])
                            #_,_,partial_muls[ctx, idx, x, y] =  FP_Madd(A_Mats[ctx, idx-1, y], B_Mats[ctx, idx-1, x], 0,                             MANT_bits=th.HOPTS['IA_MANT'], N_bits=HYPER['IA_W'], MulType=th.HOPTS['mul_type'], m=th.HOPTS['M'], AdderType=th.HOPTS['add_type'], A=th.HOPTS['A'], rounding=th.HOPTS['rounding'])

                    else:
                        partial_ops[ctx, idx, x, y] = partial_ops[ctx, idx-1, x, y]
                        partial_muls[ctx, idx, x, y] = 0

    return partial_ops, partial_muls, [A_Mats, B_Mats]

# ------------------------------------------------------
# Get tiling loops with Heuristic - Decides stationarity
# ------------------------------------------------------

def get_tiling_loops(A_tile_shape, B_tile_shape, C_tile_shape, iterations_list, CONV):
    
    c_til_iter = iterations_list[0]
    k_til_iter = iterations_list[1]
    w_til_iter = iterations_list[2]
    h_til_iter = iterations_list[3]
    
    b_factor = 1.5                                  # B weighs a bit more because it's kinda inconvenient due to its shape
    c_factor = 2 if (CONV['preload_en']) else 1     # C weighs double if preload_en (must read+write)
    
    # Compute weight of tensors in elements
    A_weight = A_tile_shape[0]*A_tile_shape[1]*A_tile_shape[2]
    B_weight = B_tile_shape[0]*B_tile_shape[1]*B_tile_shape[2]*b_factor
    C_weight = C_tile_shape[0]*C_tile_shape[1]*C_tile_shape[2]*c_factor
    
    # If there are not enough iterations to amortize keeping the value, set weight to zero
    if (k_til_iter==1):
        A_weight = 0
    if ((w_til_iter==1) and (h_til_iter==1)):
        B_weight = 0
    if (c_til_iter==1):
        C_weight = 0
        
    # Decide based on which tensor weighs the most
    decision = np.argmax([B_weight,C_weight,A_weight])
    
    # IF WE KEEP TENSOR B - Inner loop over w,h dims
    if (decision == 0):
        id_list = [2,3,1,0]    # w, h, k, c
        final_iter_list = [w_til_iter, h_til_iter, k_til_iter, c_til_iter]
        tensor_kept = [0,1,0]

    # IF WE KEEP TENSOR C - Inner loop over c dim
    elif(decision == 1):
        id_list = [0,2,3,1]    # c, w, h, k
        final_iter_list = [c_til_iter, w_til_iter, h_til_iter, k_til_iter]
        tensor_kept = [0,0,1]

    # IF WE KEEP TENSOR A - Inner loop over k dim
    elif(decision == 2):
        id_list = [1,2,3,0]    # k, w, h, c
        final_iter_list = [k_til_iter, w_til_iter, h_til_iter, c_til_iter]
        tensor_kept = [1,0,0]
        
    return tensor_kept, final_iter_list, id_list, decision

# ------------------------------------------------------
# Map tiling variables
# ------------------------------------------------------

def map_tiling_vars(i,j,k,m,id_list):
    
    ids = np.array(id_list)
    arr = np.array([i,j,k,m])
        
    c = arr[np.where(ids==0)][0]
    k = arr[np.where(ids==1)][0]
    w = arr[np.where(ids==2)][0]
    h = arr[np.where(ids==3)][0]
    
    return c,k,w,h

# ------------------------------------------------------------
# Cycle-accurate convolution for HW debugging
# ------------------------------------------------------------

def cycle_accurate_convolution(CONV, HYPER, tensors, SA, map_iter_list, id_list, silent=True):

    # Retrieve convolution variables
    B_w = CONV['B_w']
    B_h = CONV['B_h']
    C_w = CONV['C_w']
    C_h = CONV['C_h']
    C_c = CONV['C_c']
    A_w = CONV['A_w']
    A_h = CONV['A_h']
    AB_c = CONV['AB_c']
    s =    CONV['s']
    
    c_til = CONV['c_til']
    k_til = CONV['k_til']
    h_til = CONV['h_til']
    w_til = CONV['w_til']
    A_h_til = CONV['A_h_til']
    A_w_til = CONV['A_w_til']
                         
    # Partial macs list
    partial_macs = []
    A_Mats = []
    B_Mats = []
    macs = []
    muls = []
    
    C_tensor_full = copy.deepcopy(tensors[2])
                    
    # TILING LOOPS
    for m in range(map_iter_list[3]):
        for l in range(map_iter_list[2]):
            for j in range(map_iter_list[1]):               
                for i in range(map_iter_list[0]):
                    
                    c,k,w,h = map_tiling_vars(i,j,l,m,id_list)
                    
                    # Set tile parameters in a copy of CONV, which will be passed to the functions...
                    CONV_temp = copy.deepcopy(CONV)
                    CONV_temp['C_w'] = w_til
                    CONV_temp['C_h'] = h_til
                    CONV_temp['C_c'] = k_til
                    CONV_temp['A_w'] = A_w_til
                    CONV_temp['A_h'] = A_h_til
                    CONV_temp['AB_c'] = c_til
                    
                    # Get tiles (convolution)
                    A_tile = tensors[0][c*c_til:(c+1)*c_til, h*s*h_til:h*s*h_til+int(A_h_til), w*s*w_til:w*s*w_til+int(A_w_til)]
                    B_tile = tensors[1][k*k_til:(k+1)*k_til, c*c_til:(c+1)*c_til, :, :]
                    
                    # C is special because we aggregate the results from previous tiles
                    C_tile = C_tensor_full[k*k_til:(k+1)*k_til, h*h_til:(h+1)*h_til, w*w_til:(w+1)*w_til]
                                            
                    # Get matrices for the current tile
                    A_Mats_tile, B_Mats_tile, C_output_tile = conv.get_ideal_results(A_tile, B_tile, C_tile, CONV_temp, HYPER, SA, compute_macs=False)
    
                    # Compute partial macs from the matrices
                    macs_tile, muls_tile, imats_tile = conv.compute_partial_macs(A_Mats_tile, B_Mats_tile, C_tile, CONV_temp, HYPER)

                    # Aggregate results (convolution)
                    C_tensor_full[k*k_til:(k+1)*k_til, h*h_til:(h+1)*h_til, w*w_til:(w+1)*w_til] = C_output_tile
                        
                    A_Mats.append(imats_tile[0])    
                    B_Mats.append(imats_tile[1]) 
                    macs.append(macs_tile)
                    muls.append(muls_tile)
    
    # Pack partial macs into list
    macs = np.array(macs)
    muls = np.array(muls)
    A_Mats = np.array(A_Mats)
    B_Mats = np.array(B_Mats)
    
    partial_macs = [macs, muls, [A_Mats, B_Mats]]

    return C_tensor_full, partial_macs, loop_order