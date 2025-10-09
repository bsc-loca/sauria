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
import copy
import sys

sys.path.insert(1, './../')
from src.approx_comp.fp import FP_Madd
import src.test_helper as th

# --------------------------------------------
# Custom matrix multiplication with extra options
# --------------------------------------------

def custom_matmul(Mat_A, Mat_B, preloads=[], exact=True, MANT_bits=10, N_bits=16, mul_type=0, M=0, add_type=0, A=0, rounding='RNE'):
    
    A_shape = Mat_A.shape
    B_shape = Mat_B.shape
    
    assert len(A_shape)==3, "Matrices must have 3 dimensions [reps, y, x]"
    assert A_shape[2]==B_shape[1], "Matrix dimensions must fit for GeMM"
    assert A_shape[0]==B_shape[0], "Number of batches must be the same"
    
    # Initialize final matrix
    Mat_C = np.zeros((A_shape[0], A_shape[1], B_shape[2]))
    
    if (len(preloads)>0):
        Mat_C = preloads
    
    # For each output matrix dimension
    for k in range(A_shape[0]):
        for j in range(A_shape[1]):
            for i in range(B_shape[2]):

                # Reduction dimension
                for t in range(A_shape[2]):
                    
                    # MAC
                    if exact:
                        Mat_C[k, j, i] += Mat_A[k, j, t] * Mat_B[k, t, i]
                    else:
                        # Zero gating => Quite important for efficiency!
                        if (Mat_A[k, j, t]!=0) and (Mat_B[k, t, i]!=0):
                            _, _, Mat_C[k, j, i] = FP_Madd(Mat_A[k, j, t], Mat_B[k, t, i], Mat_C[k, j, i], MANT_bits=MANT_bits, N_bits=N_bits, MulType=mul_type, m=M, AdderType=add_type, A=A, rounding=rounding)
    
    return Mat_C

# --------------------------------------------
# Accurate im2col performed by SAURIA
# --------------------------------------------

def map_conv_to_MVM(SA_Param_dict, random_tensors=True, A_tensor=[], B_conv=[], preloads=[], data_type='FP', silent=False):
    """
    
    TO-DO

    Parameters
    ----------
    SA_Param_dict : TYPE
        DESCRIPTION.

    Returns
    -------
    N_inputs : TYPE
        DESCRIPTION.
    X_underuse : TYPE
        DESCRIPTION.
    Y_underuse : TYPE
        DESCRIPTION.
    tensor_C_mvm : TYPE
        DESCRIPTION.
    tensor_C : TYPE
        DESCRIPTION.

    """
    
    # -----------------------------------------------------------------------------
    # Load constants from dict
    # ----------------------------------------------------------------------------- 
    
    A_w = SA_Param_dict['A_w']
    A_h = SA_Param_dict['A_h']
    AB_c = SA_Param_dict['AB_c']
    
    B_w = SA_Param_dict['B_w']
    B_h = SA_Param_dict['B_h']
    B_k = SA_Param_dict['B_k']

    d = SA_Param_dict['d']
    s = SA_Param_dict['s']

    B_w_eff = 1 + (B_w - 1)*d
    B_h_eff = 1 + (B_h - 1)*d

    C_w = SA_Param_dict['C_w']
    C_h = SA_Param_dict['C_h']
    C_c = SA_Param_dict['C_c']
    
    size_Y = SA_Param_dict['size_Y']
    size_X = SA_Param_dict['size_X']
    
    OS_buff_K = SA_Param_dict['OS_buff_K']
    
    # -----------------------------------------------------------------------------
    # ATOMIC TENSOR PRIMITIVES
    # ----------------------------------------------------------------------------- 
    
    atm_C_c = size_X        # Iterable (Architectural)
    atm_C_w = size_Y        # Iterable (Architectural)
    atm_C_h = OS_buff_K     # Iterable
    
    atm_A_c = AB_c                                  # Reductible
    atm_A_w = s*size_Y + B_w_eff - (B_w_eff%2)      # Iterable (Architectural)
    atm_A_h = OS_buff_K*B_h_eff                     # Iterable
    
    atm_B_k = size_X    # Iterable (Architectural)
    atm_B_c = AB_c      # Reductible
    atm_B_w = B_w       # Reductible 
    atm_B_h = B_h       # Reductible
    
    # Write tensor primitives to param dict
    SA_Param_dict['atm_C_c'] = atm_C_c
    SA_Param_dict['atm_C_w'] = atm_C_w
    SA_Param_dict['atm_C_h'] = atm_C_h
    
    SA_Param_dict['atm_A_c'] = atm_A_c
    SA_Param_dict['atm_A_w'] = atm_A_w
    SA_Param_dict['atm_A_h'] = atm_A_h
    
    SA_Param_dict['atm_B_k'] = atm_B_k
    SA_Param_dict['atm_B_c'] = atm_B_c
    SA_Param_dict['atm_B_w'] = atm_B_w
    SA_Param_dict['atm_B_h'] = atm_B_h

    X_used = SA_Param_dict['X_used']
    Y_used = SA_Param_dict['Y_used']

    # -----------------------------------------------------------------------------
    # Number of iterations and number of MVM inputs
    # ----------------------------------------------------------------------------- 

    # Number of iterations (for Iterable dimensions)
    n_iter_z = np.ceil(C_c/X_used)
    n_iter_y = np.ceil(C_h/atm_C_h)
    n_iter_x = np.ceil(C_w/Y_used)
    
    N_iter = n_iter_z*n_iter_y*n_iter_x
    N_iter = N_iter.astype(int)
    
    # Input vectors per iteration (Reductible dimensions)
    N_inputs_per_it = atm_C_h*B_w*B_h*AB_c
    
    # Total input vectors
    N_inputs = N_inputs_per_it*N_iter
    N_inputs = N_inputs.astype(int)
        
    # Utilization: Architectural Iterable dimensions
    remaining_C_c = X_used
    remaining_C_w = Y_used
    
    ucoef_C_c = C_c/(n_iter_z*atm_C_c)
    ucoef_C_w = C_w/(n_iter_x*atm_C_w)
    
    # --------------------------------------------------------------------------------
    # ACTUAL MAPPING + UTILIZATION + CHECK
    # --------------------------------------------------------------------------------

    # Define pytorch values
    if random_tensors:
        tensor_A_torch = torch.randn(AB_c, A_h, A_w, dtype=torch.float32) * 100
        m = torch.nn.Conv2d(AB_c, B_k, (B_h, B_w), stride=s, dilation=d)
    else:
        tensor_A_torch = A_tensor
        m = B_conv
        
    m.weight.requires_grad = False
    
    #TEST
    # tensor_A_torch = torch.tensor(np.ones((AB_c, A_h, A_w), dtype=np.float32))
    # m.weight = torch.nn.Parameter(torch.tensor(np.ones((B_k, AB_c, B_h, B_w), dtype=np.float32)))
    # m.weight.requires_grad = False
    
    tensor_A = np.array(tensor_A_torch).astype(np.float32)
    tensor_B = np.array(m.weight).astype(np.float32)
    
    A_Mat = np.zeros((N_inputs, size_Y)).astype(np.float32)
    B_Mat = np.zeros((N_inputs, size_X)).astype(np.float32)
    
    X_underuse = np.zeros((N_inputs)).astype(bool)
    Y_underuse = np.zeros((N_inputs)).astype(bool)
    
    x_id_itr_max = np.ceil(C_w/Y_used).astype(int)
    y_id_itr_max = np.ceil(C_h/atm_C_h).astype(int)
    z_id_itr_max = np.ceil(C_c/X_used).astype(int)
    
    input_idx = 0
    
    # External loops
    for z_id_itr in range(z_id_itr_max):
        for y_id_itr in range(y_id_itr_max):
            for x_id_itr in range(x_id_itr_max):
                                        
                # Weight kernel loops (Reductible)
                for kz in range(atm_B_c):
                    for ky in range(atm_B_h):        
                        for kx in range(atm_B_w):
                            
                            # Atomic ofmap result loops (Architectural)
                            for ofmap_y_idx in range(atm_C_h):
                                
                                # Dimensions above are sequential, below are concurrent
                                
                                for ofmap_z_idx in range(atm_C_c):
                                    
                                    # Underutilization: unused columns set to zero
                                    if (ucoef_C_c<1) and (ofmap_z_idx>remaining_C_c-1):
                                        B_Mat[input_idx, ofmap_z_idx] = 0
                                        X_underuse[input_idx] = 1
                                        
                                    # Otherwise, normal assignment
                                    else:
                                        B_Mat[input_idx, ofmap_z_idx] = tensor_B[X_used*z_id_itr+ofmap_z_idx, kz, ky, kx]
    
    
                                for ofmap_x_idx in range(atm_C_w):
    
                                    # Underutilization: unused columns set to zero
                                    if (ucoef_C_w<1) and (ofmap_x_idx>remaining_C_w-1):                                
                                        A_Mat[input_idx, ofmap_x_idx] = 0
                                        Y_underuse[input_idx] = 1
                                        
                                    # Otherwise, normal assignment 
                                    else:
                                        A_Mat[input_idx, ofmap_x_idx] = tensor_A[kz, atm_C_h*(s*y_id_itr)+(d*ky)+(s*ofmap_y_idx), Y_used*(s*x_id_itr)+(d*kx)+(s*ofmap_x_idx)]
    
                                # New input vector
                                input_idx += 1
                                
                                #if input_idx>515:
                                #    print(z_id_itr, y_id_itr, x_id_itr, kz, ky, kx, ofmap_y_idx)
    
    assert input_idx == N_inputs, "There was a mapping issue, number of input vectors does not match"

    # -----------------------------------------------------------------------------
    # Check mapping: compare random results between MVM and Pytorch
    # ----------------------------------------------------------------------------- 

    # Convolution results with torch
    tensor_A_torch = torch.reshape(tensor_A_torch, (1, tensor_A.shape[0], tensor_A.shape[1], tensor_A.shape[2]))
    tensor_C_torch = m(tensor_A_torch)
    
    tensor_C = np.array(tensor_C_torch.detach())
    tensor_C = tensor_C.reshape((C_c, C_h, C_w))
    
    preloads_mvm = np.zeros((N_iter, size_Y, size_X ))
    
    # Add Cinit after the convolution
    if (len(preloads)>0):
        tensor_C = tensor_C + preloads
    
        # Reshape preloads properly
        for z in range(C_c):
            for y in range(C_h):
                for x in range(C_w):
                    
                    z_mvm_idx = int(z%X_used)
                    x_mvm_idx = int(x%Y_used)
                    
                    vector_idx = int((z//X_used)*y_id_itr_max*x_id_itr_max + y*x_id_itr_max + x//Y_used)
        
                    preloads_mvm[vector_idx , x_mvm_idx, z_mvm_idx] = preloads[z,y,x]
        
    # Split the batches in order to compute the MVM
    A_Mat_mvm = np.swapaxes(np.reshape(A_Mat, (N_iter, N_inputs_per_it, size_Y)), 1,2)
    B_Mat_mvm = np.reshape(B_Mat, (N_iter, N_inputs_per_it, size_X))
    
    # Typecast when we operate with integer values
    if (data_type=='int'):
        A_Mat_mvm = A_Mat_mvm.astype(np.int64)
        B_Mat_mvm = B_Mat_mvm.astype(np.int64)
    
    # MVM results
    if not SA_Param_dict['approx_comp']:
        C_Mat_mvm = np.matmul(A_Mat_mvm, B_Mat_mvm) + preloads_mvm
    else:
        C_Mat_mvm = custom_matmul(A_Mat_mvm, B_Mat_mvm, preloads=preloads_mvm, exact=False, MANT_bits=SA_Param_dict['MANT_bits'], N_bits=SA_Param_dict['ACT_IA_W'], mul_type=SA_Param_dict['mul_type'], M=SA_Param_dict['M'], add_type=SA_Param_dict['add_type'], A=SA_Param_dict['A'], rounding=SA_Param_dict['rounding'])
    
    # Reshape results properly
    tensor_C_mvm = np.zeros(tensor_C.shape)
    
    for z in range(C_c):
        for y in range(C_h):
            for x in range(C_w):
                
                z_mvm_idx = int(z%X_used)
                x_mvm_idx = int(x%Y_used)
                
                vector_idx = int((z//X_used)*y_id_itr_max*x_id_itr_max + y*x_id_itr_max + x//Y_used)
    
                tensor_C_mvm[z,y,x] = C_Mat_mvm[vector_idx , x_mvm_idx, z_mvm_idx]
        
    # Check MVM results only if exact computation
    if not SA_Param_dict['approx_comp']:
        
        # Typically there is some +-0.1 error due to Pytorch numerical precision!
        err = np.abs(tensor_C - tensor_C_mvm)
        
        l2_norm_scaled = np.linalg.norm(tensor_C_mvm.flatten())/np.size(tensor_C_mvm.flatten())
        
        # print(tensor_A)
        # print(tensor_C[:4, :4, :4])
        # print("------------------")
        # print(tensor_C_mvm[:4, :4, :4])
        # print(l2_norm_scaled/1000)
        # print(np.max(err))
        #print(tensor_A)
        #print(tensor_B)
        #print(A_Mat_mvm)
        #print(B_Mat_mvm)
        
        tol = max(1.2, l2_norm_scaled/100)
        
        if np.any(err>=(tol)):
            print("Pytorch results:")
            print(tensor_C[:4, :4, :4])
            print("------------------")
            print("MVM results:")
            print(tensor_C_mvm[:4, :4, :4])
            print("------------------")
            print("L2 Norm scaled:")
            print(l2_norm_scaled/100)
            print("Max error:")
            print(np.max(err))
        
        assert np.all(err<(tol)), "Result check did not match numerically! tol={}; max err={}".format(tol, np.max(err))

    if not silent:
        print("\nTotal iterations:")
        print("{}".format(N_iter))
        print("\nTotal number of MVM input vectors:")
        print("{}".format(N_inputs))

    return N_inputs, N_iter, X_underuse, Y_underuse, tensor_C_mvm, tensor_C, A_Mat, B_Mat

# ------------------------------------------------------------
# Accurate computation of partial MACs exactly like SAURIA
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
                        if not HYPER['approx_comp']:
                            partial_muls[ctx, idx, x, y] = A_Mats[ctx, idx-1, y] * B_Mats[ctx, idx-1, x]
                            partial_ops[ctx, idx, x, y] = partial_ops[ctx, idx-1, x, y] + partial_muls[ctx, idx, x, y]

                        # Approx version
                        else:
                            _,_,partial_ops[ctx, idx, x, y] =   FP_Madd(A_Mats[ctx, idx-1, y], B_Mats[ctx, idx-1, x], partial_ops[ctx, idx-1, x, y], MANT_bits=HYPER['IA_MANT'], N_bits=HYPER['IA_W'], MulType=HYPER['mul_type'], m=HYPER['M'], AdderType=HYPER['add_type'], A=HYPER['A'], rounding=HYPER['rounding'])
                            #_,_,partial_muls[ctx, idx, x, y] =  FP_Madd(A_Mats[ctx, idx-1, y], B_Mats[ctx, idx-1, x], 0,                             MANT_bits=HYPER['IA_MANT'], N_bits=HYPER['IA_W'], MulType=HYPER['mul_type'], m=HYPER['M'], AdderType=HYPER['add_type'], A=HYPER['A'], rounding=HYPER['rounding'])

                    else:
                        partial_ops[ctx, idx, x, y] = partial_ops[ctx, idx-1, x, y]
                        partial_muls[ctx, idx, x, y] = 0

    return partial_ops, partial_muls, [A_Mats, B_Mats]

# ------------------------------------------------------
# Get tiling loops with Heuristic - Decides stationarity
# ------------------------------------------------------

def get_tiling_loops(CONV):
    
    A_tile_shape = [CONV['c_til'],CONV['A_h_til'],CONV['A_w_til']]
    B_tile_shape = [CONV['k_til'],CONV['c_til'],CONV['B_h'],CONV['B_w']]
    C_tile_shape = [CONV['k_til'],CONV['w_til'],CONV['h_til']]

    c_til_iter = int(CONV['AB_c']/ CONV['c_til'])
    k_til_iter = int(CONV['C_c']/CONV['k_til'])
    w_til_iter = int(CONV['C_w']/CONV['w_til'])
    h_til_iter = int(CONV['C_h']/CONV['h_til'])
    
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
                    A_Mats_tile, B_Mats_tile, C_output_tile = get_ideal_results(A_tile, B_tile, C_tile, CONV_temp, HYPER, SA, compute_macs=False)
    
                    # Compute partial macs from the matrices
                    macs_tile, muls_tile, imats_tile = compute_partial_macs(A_Mats_tile, B_Mats_tile, C_tile, CONV_temp, HYPER)

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

    return C_tensor_full, partial_macs

# --------------------------------------------
# Top function to perform convolution / GeMM with the model
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

    SA_dict['MANT_bits'] =      HYPER['IA_MANT']
    SA_dict['approx_comp'] =    HYPER['approx_comp']
    SA_dict['mul_type'] =       HYPER['mul_type']
    SA_dict['M'] =              HYPER['M']
    SA_dict['add_type'] =       HYPER['add_type']
    SA_dict['A'] =              HYPER['A']
    SA_dict['rounding'] =       HYPER['rounding']
 
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
    _, map_iter_list, id_list, loop_order = get_tiling_loops(CONV)

    # ONLY FOR DEBUGGING - Replicate the exact compute order as the hardware (SLOW)
    if compute_macs:

        tensors = [A_tensor, B_tensor, C_tensor]
        C_output, partial_macs = cycle_accurate_convolution(CONV, HYPER, tensors, th.get_sa_dict(HYPER), map_iter_list, id_list)

    # If not debugging, compute the convolution as a single systolic array job
    else:
        partial_macs = [0,0,0]

        # Convolution => Do it with model mapping
        torch_A_tensor = torch.from_numpy(A_tensor.astype(np.float32))
        
        B_conv = torch.nn.Conv2d(CONV['AB_c'], CONV['C_c'], (CONV['B_h'], CONV['B_w']), stride=CONV['s'], dilation=CONV['d'])
        
        B_conv.weight = torch.nn.Parameter(torch.tensor(B_tensor.astype(np.float32)))
        B_conv.bias = torch.nn.Parameter(torch.zeros(B_conv.bias.shape))
        
        data_type = 'FP' if (HYPER['OP_TYPE']==1) else 'int'
        
        _, _, _, _, C_output, _, _, _ = map_conv_to_MVM(SA_dict, random_tensors=False, A_tensor=torch_A_tensor, B_conv=B_conv, preloads=C_tensor, data_type=data_type, silent=True)
        
        C_output = C_output.astype(HYPER['intyp'])
                    
    return C_output, partial_macs, loop_order