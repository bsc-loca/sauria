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

# *********************************************
# IMPORTS
# *********************************************

import numpy as np
import torch
import matplotlib.pyplot as plt

import model.matmul_helper as mh

# ***********************************************
# alpha-beta-gamma test for array dimensioning
# ***********************************************

def abg_test(X, Y, fclk, C_c, C_w, C_h, AB_c, B_w, B_h, IA_W, IB_W, OC_W, plotfigs=True):
    
    BW_min_0_alpha =    (X*Y*IB_W*fclk)/(C_w*C_h)
    BW_min_0_beta =     (X*Y*IA_W*fclk)/(B_w*B_h*C_c)
    BW_min_0_gamma =    (X*Y*2*OC_W*fclk)/(B_w*B_h*AB_c)
    
    BW_alpha =  np.linspace(2*BW_min_0_alpha, 8*BW_min_0_alpha, 100)
    BW_beta =   np.linspace(2*BW_min_0_beta, 8*BW_min_0_beta, 100)
    BW_gamma =  np.linspace(2*BW_min_0_gamma, 8*BW_min_0_gamma, 100)
    
    alpha = (IA_W + 2*OC_W)/(B_w*B_h*((BW_alpha/(X*Y*fclk))-(IB_W/(C_w*C_h))))
    beta = (B_w*B_h*IB_W + 2*OC_W)/(B_w*B_h*((BW_beta/(X*Y*fclk))-(IA_W/(B_w*B_h*C_c))))
    gamma = (IA_W + B_w*B_h*IB_W)/(B_w*B_h*((BW_gamma/(X*Y*fclk))-(2*OC_W/(B_w*B_h*AB_c))))
    
    SRAMA_occ_alpha = alpha*(C_w+B_w)*(C_h+B_h)*(IA_W/8)
    SRAMB_occ_alpha = alpha*B_w*B_h*C_c*(IB_W/8)
    SRAMC_occ_alpha = alpha*C_w*C_h*(OC_W/8)

    SRAMA_occ_beta = beta*(np.sqrt(beta)+B_w)*(np.sqrt(beta)+B_h)*(IA_W/8)
    SRAMB_occ_beta = beta*B_w*B_h*C_c*(IB_W/8)
    SRAMC_occ_beta = C_c*beta*(OC_W/8)
    
    SRAMA_occ_gamma = AB_c*(np.sqrt(gamma)+B_w)*(np.sqrt(gamma)+B_h)*(IA_W/8)
    SRAMB_occ_gamma = AB_c*B_w*B_h*gamma*(IB_W/8)
    SRAMC_occ_gamma = gamma*gamma*(OC_W/8)
    
    if (plotfigs):
    
        fig, ax1 = plt.subplots()
        ax1.set_xlabel('Min Bandwidth (MB/s)')
        ax1.set_ylabel('Alpha', color='magenta')
        ax1.plot(BW_alpha/8e6, alpha, 'magenta')
        
        ax2 = ax1.twinx()  # instantiate a second axes that shares the same x-axis
        ax2.set_ylabel('SRAM Sizes (kB)', color='gray')  # we already handled the x-label with ax1
        ax2.plot(BW_alpha/8e6, SRAMA_occ_alpha/1024, color='r', linestyle='--', alpha=0.5)
        ax2.plot(BW_alpha/8e6, SRAMB_occ_alpha/1024, color='b', linestyle='--', alpha=0.5)
        ax2.plot(BW_alpha/8e6, SRAMC_occ_alpha/1024, color='g', linestyle='--', alpha=0.5)
        fig.tight_layout()  # otherwise the right y-label is slightly clipped

        ax1.annotate("X = {}, Y = {}".format(X,Y), xy=[0.6*ax1.get_xlim()[1], 0.9*ax1.get_ylim()[1]], fontsize=12)
        ax1.annotate("fclk = {} MHz".format(np.round(fclk/1e6, decimals=2)), xy=[0.6*ax1.get_xlim()[1], 0.85*ax1.get_ylim()[1]], fontsize=10)
        ax1.annotate("BW limit = {} MB/s".format(np.round((BW_min_0_alpha/8e6), decimals=2)), xy=[0.6*ax1.get_xlim()[1], 0.8*ax1.get_ylim()[1]], fontsize=10)
        
        fig, ax1 = plt.subplots()
        ax1.set_xlabel('Min Bandwidth (MB/s)')
        ax1.set_ylabel('Beta', color='magenta')
        ax1.plot(BW_beta/8e6, beta, 'magenta')
        
        ax2 = ax1.twinx()  # instantiate a second axes that shares the same x-axis
        ax2.set_ylabel('SRAM Sizes (kB)', color='gray')  # we already handled the x-label with ax1
        ax2.plot(BW_beta/8e6, SRAMA_occ_beta/1024, color='r', linestyle='--', alpha=0.5)
        ax2.plot(BW_beta/8e6, SRAMB_occ_beta/1024, color='b', linestyle='--', alpha=0.5)
        ax2.plot(BW_beta/8e6, SRAMC_occ_beta/1024, color='g', linestyle='--', alpha=0.5)
        fig.tight_layout()  # otherwise the right y-label is slightly clipped

        ax1.annotate("X = {}, Y = {}".format(X,Y), xy=[0.6*ax1.get_xlim()[1], 0.9*ax1.get_ylim()[1]], fontsize=12)
        ax1.annotate("fclk = {} MHz".format(np.round(fclk/1e6, decimals=2)), xy=[0.6*ax1.get_xlim()[1], 0.85*ax1.get_ylim()[1]], fontsize=10)
        ax1.annotate("BW limit = {} MB/s".format(np.round((BW_min_0_beta/8e6), decimals=2)), xy=[0.6*ax1.get_xlim()[1], 0.8*ax1.get_ylim()[1]], fontsize=10)
        
        fig, ax1 = plt.subplots()
        ax1.set_xlabel('Min Bandwidth (MB/s)')
        ax1.set_ylabel('Gamma', color='magenta')
        ax1.plot(BW_gamma/8e6, gamma, 'magenta')
        
        ax2 = ax1.twinx()  # instantiate a second axes that shares the same x-axis
        ax2.set_ylabel('SRAM Sizes (kB)', color='gray')  # we already handled the x-label with ax1
        ax2.plot(BW_gamma/8e6, SRAMA_occ_gamma/1024, color='r', linestyle='--', alpha=0.5)
        ax2.plot(BW_gamma/8e6, SRAMB_occ_gamma/1024, color='b', linestyle='--', alpha=0.5)
        ax2.plot(BW_gamma/8e6, SRAMC_occ_gamma/1024, color='g', linestyle='--', alpha=0.5)
        fig.tight_layout()  # otherwise the right y-label is slightly clipped
        
        ax1.annotate("X = {}, Y = {}".format(X,Y), xy=[0.6*ax1.get_xlim()[1], 0.9*ax1.get_ylim()[1]], fontsize=12)
        ax1.annotate("fclk = {} MHz".format(np.round(fclk/1e6, decimals=2)), xy=[0.6*ax1.get_xlim()[1], 0.85*ax1.get_ylim()[1]], fontsize=10)
        ax1.annotate("BW limit = {} MB/s".format(np.round((BW_min_0_gamma/8e6), decimals=2)), xy=[0.6*ax1.get_xlim()[1], 0.8*ax1.get_ylim()[1]], fontsize=10)
        
    return alpha, BW_alpha, beta, BW_beta, gamma, BW_gamma

# *********************************************
# SRAM Memory Allocation
# *********************************************

def get_A_dimensions(AB_c, B_w, B_h, C_w, C_h, C_c, d, s):

    # -----------------------------------------------------------------------------
    # Generate constrained tensor shapes (A, B)
    # ----------------------------------------------------------------------------- 

    # Effective Kernel size (dilation)
    B_w_eff = 1 + (B_w - 1)*d
    B_h_eff = 1 + (B_h - 1)*d

    # CONSTRAINED TENSOR SHAPES
    A_w = s*(C_w-1) + 1 + B_w_eff - (B_w_eff%2)
    A_h = s*(C_h-1) + 1 + B_h_eff - (B_h_eff%2)
    B_k = C_c
    
    return B_k, A_h, A_w, B_h_eff, B_w_eff

def allocate_SRAM(SRAM_size, SA_Param_dict, assertion=True, silent=False):
    """
    
      DOCSTRINGS TO-DO  
    
    Parameters
    ----------
    SRAM_size : TYPE
        DESCRIPTION.
    SA_Param_dict : TYPE
        DESCRIPTION.

    Returns
    -------
    None.

    """
    
    # Bytes to Bits
    SRAMA_bits = SRAM_size[0]*8
    SRAMB_bits = SRAM_size[1]*8  
    SRAMC_bits = SRAM_size[2]*8  

    # -----------------------------------------------------------------------------
    # Load constants from dict
    # -----------------------------------------------------------------------------     

    AB_c = SA_Param_dict['AB_c']
    
    B_w = SA_Param_dict['B_w']
    B_h = SA_Param_dict['B_h']
    
    C_w = SA_Param_dict['C_w']
    C_h = SA_Param_dict['C_h']
    C_c = SA_Param_dict['C_c']
    
    d = SA_Param_dict['d']
    s = SA_Param_dict['s']
    
    bits_Activations = SA_Param_dict['bits_Activations']
    bits_Weights = SA_Param_dict['bits_Weights']
    bits_Outputs = SA_Param_dict['bits_Outputs']

    # -----------------------------------------------------------------------------
    # Generate constrained tensor shapes (A, B)
    # ----------------------------------------------------------------------------- 

    B_k, A_h, A_w, B_h_eff, B_w_eff = get_A_dimensions(AB_c, B_w, B_h, C_w, C_h, C_c, d, s)

    SA_Param_dict['B_w_eff'] = B_w_eff
    SA_Param_dict['B_h_eff'] = B_h_eff
    
    SA_Param_dict['A_w'] = A_w
    SA_Param_dict['A_h'] = A_h
    SA_Param_dict['B_k'] = B_k

    # -----------------------------------------------------------------------------
    # Compute SRAM sizes
    # ----------------------------------------------------------------------------- 

    # Operand Elements
    A_elements = A_w*A_h*AB_c
    B_elements = B_w*B_h*AB_c*B_k
    C_elements = C_w*C_h*C_c
        
    # Operand size in memory
    assigned_SRAM_A = A_elements*bits_Activations
    assigned_SRAM_B = B_elements*bits_Weights
    assigned_SRAM_C = C_elements*bits_Outputs
    
    unassigned_SRAMA = SRAMA_bits - assigned_SRAM_A
    unassigned_SRAMB = SRAMB_bits - assigned_SRAM_B
    unassigned_SRAMC = SRAMC_bits - assigned_SRAM_C
    
    if (assertion):
        assert unassigned_SRAMA>=0, "Activation data does not fit in SRAM! {}KB/{}KB".format(assigned_SRAM_A/(8e3), SRAMA_bits/(8e3))
        assert unassigned_SRAMB>=0, "Weight data does not fit in SRAM! {}KB/{}KB".format(assigned_SRAM_B/(8e3), SRAMB_bits/(8e3))
        assert unassigned_SRAMC>=0, "Output data does not fit in SRAM! {}KB/{}KB".format(assigned_SRAM_C/(8e3), SRAMC_bits/(8e3))
    
    fits = (unassigned_SRAMA>=0) and (unassigned_SRAMB>=0) and (unassigned_SRAMC>=0)
    
    if not silent:
        if (fits):
            print("Activation data fits in SRAM:   {}KB/{}KB   [{}%]".format(assigned_SRAM_A/(8e3), SRAMA_bits/(8e3), 100*assigned_SRAM_A/SRAMA_bits))
            print("Weight data does fits in SRAM:   {}KB/{}KB   [{}%]".format(assigned_SRAM_B/(8e3), SRAMB_bits/(8e3), 100*assigned_SRAM_B/SRAMB_bits))
            print("Output data does fits in SRAM:   {}KB/{}KB   [{}%]".format(assigned_SRAM_C/(8e3), SRAMC_bits/(8e3), 100*assigned_SRAM_C/SRAMC_bits))

    return assigned_SRAM_A, assigned_SRAM_B, assigned_SRAM_C, unassigned_SRAMA, unassigned_SRAMB, unassigned_SRAMC, fits

# *********************************************
# Mapping algorithm, PE utilization and check
# *********************************************

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
        C_Mat_mvm = mh.custom_matmul(A_Mat_mvm, B_Mat_mvm, preloads=preloads_mvm, exact=False, MANT_bits=SA_Param_dict['MANT_bits'], N_bits=SA_Param_dict['ACT_IA_W'], mul_type=SA_Param_dict['mul_type'], M=SA_Param_dict['M'], add_type=SA_Param_dict['add_type'], A=SA_Param_dict['A'], rounding=SA_Param_dict['rounding'])
    
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

# ***********************
# ACTIVE PEs MODEL
# ***********************

def compute_MVM_cycles(N_inputs, X_underuse, Y_underuse, n_stalls, SA_Param_dict, silent=False):
    """
        
      DOCSTRINGS TO-DO  
    

    Parameters
    ----------
    N_inputs : TYPE
        DESCRIPTION.
    X_underuse : TYPE
        DESCRIPTION.
    Y_underuse : TYPE
        DESCRIPTION.
    SA_Param_dict : TYPE
        DESCRIPTION.
    silent : TYPE, optional
        DESCRIPTION. The default is False.

    Returns
    -------
    timeline_complete : TYPE
        DESCRIPTION.
    FLOPS : TYPE
        DESCRIPTION.
    ideal_FLOPS : TYPE
        DESCRIPTION.
    total_FLOP : TYPE
        DESCRIPTION.
    total_time : TYPE
        DESCRIPTION.

    """
    
    # -----------------------------------------------------------------------------
    # Load constants from dict
    # -----------------------------------------------------------------------------    

    array_type = SA_Param_dict['array_type']
    
    CLK_period = SA_Param_dict['CLK_period']
    scan_CLK_cycles = SA_Param_dict['scan_CLK_cycles']
    pipeline_CLK_cycles = SA_Param_dict['pipeline_CLK_cycles']
    
    size_Y = SA_Param_dict['size_Y']
    size_X = SA_Param_dict['size_X']
    
    replication_Y = SA_Param_dict['replication_Y']
    replication_X = SA_Param_dict['replication_X']

    pipeline_stages = SA_Param_dict['pipeline_stages']

    atm_C_c = SA_Param_dict['atm_C_c']
    atm_C_w = SA_Param_dict['atm_C_w']

    remaining_C_c = SA_Param_dict['X_used']
    remaining_C_w = SA_Param_dict['Y_used']

    # Constraints   
    cell_latency = 1 if array_type=='OS' else pipeline_stages
    
    # -----------------------------------------------------------------------------
    # Number of cycles per phase
    # -----------------------------------------------------------------------------
    
    # Initial scan (in or out)
    scan_overhead_cycles = scan_CLK_cycles*size_Y                                   # ASSUMPTION: scanning through the Y direction        
    
    # Propagation cyces (pipeline filling and emptying)
    prop_cycles = cell_latency*(size_X+size_Y-1)
    
    # Constant phase
    constant_thrpt_cycles = (N_inputs-cell_latency*(size_X+size_Y-1))+cell_latency
    constant_thrpt_cycles = 0 if (constant_thrpt_cycles<0) else constant_thrpt_cycles       # May be zero (or negative, which is effectively zero)
    
    # Total time
    total_comp_cycles = int(min(prop_cycles, N_inputs) + constant_thrpt_cycles + prop_cycles + cell_latency)
    
    # Increases and decreases in PEs
    delta_PEs = np.zeros((total_comp_cycles), dtype=int)
    
    # -----------------------------------------------------------------------------
    # Propagation phase (initial)
    # -----------------------------------------------------------------------------
    
    # Check for X axis underutilization
    if X_underuse[0]:
        size_X_effective = remaining_C_c
    else:
        size_X_effective = size_X
    
    # Check for Y axis underutilization
    if Y_underuse[0]:
        size_Y_effective = remaining_C_w
    else:
        size_Y_effective = size_Y  
    
    prop_cycles_effective = cell_latency*(size_X_effective+size_Y_effective-1)
    
    # Propagation loop
    t0 = 0
    tfin = int(prop_cycles_effective/cell_latency)+1
    
    for t in range(t0,tfin):
    
        # Increasing sum region
        if t<min(size_X_effective, size_Y_effective):
            delta_PEs[cell_latency*(t-t0)+(cell_latency-1)] += (t-t0)
            
        # Constant region
        elif t<max(size_X_effective, size_Y_effective):
            delta_PEs[cell_latency*(t-t0)+(cell_latency-1)] += min(size_X_effective, size_Y_effective)
        
        # Decreasing sum region
        else:
            delta_PEs[cell_latency*(t-t0)+(cell_latency-1)] += (min(size_X_effective, size_Y_effective)-((t-t0)-max(size_X_effective, size_Y_effective)))
    
    # -----------------------------------------------------------------------------
    # Constant throughput phase - Iterations with underutilization
    # -----------------------------------------------------------------------------
    
    if constant_thrpt_cycles>0:
    
        X_flag = False
        Y_flag = False
        
        X_update = False
        Y_update = False
               
        X_underuse_active = X_underuse[0]
        Y_underuse_active = Y_underuse[0]
        
        t0_X = 0
        t0_Y = 0
        tfin_X = 0
        tfin_Y = 0
        
        substry_X_effective = size_Y
        substrx_Y_effective = size_X
        
        # Must take into account that sometimes we start having substracted already
        if X_underuse_active:
            substrx_X_effective = atm_C_c-remaining_C_c
        else:
            substrx_X_effective = 0
        
        # Must take into account that sometimes we start having substracted already
        if Y_underuse_active:
            substry_Y_effective = atm_C_w-remaining_C_w
        else:
            substry_Y_effective = 0
        
        # Propagation loop
        for t in range(tfin,N_inputs):
                      
            # X axis check
            if (X_underuse[t] ^ X_underuse[t-1]):
                X_flag = True
                X_update = True
                X_underuse_active = X_underuse[t]
            else:
                X_flag = False
            
            # Y axis check
            if (Y_underuse[t] ^ Y_underuse[t-1]):
                Y_flag = True
                Y_update = True
                Y_underuse_active = Y_underuse[t]
            else:
                Y_flag = False
                
            # X axis setting
            if X_flag:
                t0_X = t+remaining_C_c
                substrx_X_effective = atm_C_c-remaining_C_c
                
                # If Y was already subtracting, must remove the intersection
                if (Y_underuse_active and not Y_flag):
                    substry_X_effective = size_Y - substry_Y_effective
                else:
                    substry_X_effective = size_Y
                            
                pol_X = -1*(int(X_underuse[t])-int(X_underuse[t-1]))
                
                prop_X_effective = cell_latency*(substrx_X_effective+substry_X_effective-1)
                tfin_X = t0_X + int(prop_X_effective/cell_latency)+1
            
            # Y axis setting
            if Y_flag:
                t0_Y = t+remaining_C_w
                substry_Y_effective = atm_C_w-remaining_C_w
                
                # If Y was already subtracting or X and Y will substract together, must remove the intersection
                if (X_underuse_active and not X_flag) or (X_underuse_active and Y_underuse_active):
                    substrx_Y_effective = size_X - substrx_X_effective
                else:
                    substrx_Y_effective = size_X
                    
                pol_Y = -1*(int(Y_underuse[t])-int(Y_underuse[t-1]))
                
                prop_Y_effective = cell_latency*(substrx_Y_effective+substry_Y_effective-1)
                tfin_Y = t0_Y + int(prop_Y_effective/cell_latency)+1
                        
            # Substract unused deltas -> Equivalent to the superposition of complementary propagation phases
            if X_update and t>=t0_X and t<tfin_X:
        
                # Increasing substr region
                if t<t0_X+min(substrx_X_effective, substry_X_effective):
                    delta_PEs[t0_X+cell_latency*(t-t0_X)+(cell_latency-1)] += pol_X*(t-t0_X)
                    
                # Constant substr region
                elif t<t0_X+max(substrx_X_effective, substry_X_effective):
                    delta_PEs[t0_X+cell_latency*(t-t0_X)+(cell_latency-1)] += pol_X*min(substrx_X_effective, substry_X_effective)
                
                # Decreasing substr region
                else:
                    delta_PEs[t0_X+cell_latency*(t-t0_X)+(cell_latency-1)] += pol_X*(min(substrx_X_effective, substry_X_effective)-(t-t0_X-max(substrx_X_effective, substry_X_effective)))

            elif t>=tfin_X:
                X_update = False
            
            # Substract unused deltas -> Equivalent to the superposition of complementary propagation phases
            if Y_update and t>=t0_Y and t<tfin_Y:
                    
                # Increasing substr region
                if t<t0_Y+min(substrx_Y_effective, substry_Y_effective):
                    delta_PEs[t0_Y+cell_latency*(t-t0_Y)+(cell_latency-1)] += pol_Y*(t-t0_Y)
                    
                # Constant substr region
                elif t<t0_Y+max(substrx_Y_effective, substry_Y_effective):
                    delta_PEs[t0_Y+cell_latency*(t-t0_Y)+(cell_latency-1)] += pol_Y*min(substrx_Y_effective, substry_Y_effective)
                
                # Decreasing substr region
                else:
                    delta_PEs[t0_Y+cell_latency*(t-t0_Y)+(cell_latency-1)] += pol_Y*(min(substrx_Y_effective, substry_Y_effective)-(t-t0_Y-max(substrx_Y_effective, substry_Y_effective)))
            
            elif t>=tfin_Y:
                Y_update = False    
    
    # -----------------------------------------------------------------------------
    # Propagation phase (final)
    # -----------------------------------------------------------------------------
    
    # Check for X axis underutilization
    if X_underuse[N_inputs-1]:
        size_X_effective = remaining_C_c
    else:
        size_X_effective = size_X
    
    # Check for Y axis underutilization
    if Y_underuse[N_inputs-1]:
        size_Y_effective = remaining_C_w
    else:
        size_Y_effective = size_Y  
    
    prop_cycles_effective = cell_latency*(size_X_effective+size_Y_effective-1)
    
    # Propagation loop
    t0 = N_inputs
    tfin = t0 + int(prop_cycles_effective/cell_latency)+1
    
    for t in range(t0,tfin):
    
        # Increasing substr region
        if t<t0+min(size_X_effective, size_Y_effective):
            delta_PEs[t0+cell_latency*(t-t0)+(cell_latency-1)] += -1*(t-t0)
            
        # Constant substr region
        elif t<t0+max(size_X_effective, size_Y_effective):
            delta_PEs[t0+cell_latency*(t-t0)+(cell_latency-1)] += -1*min(size_X_effective, size_Y_effective)
        
        # Decreasing substr region
        else:
            delta_PEs[t0+cell_latency*(t-t0)+(cell_latency-1)] += -1*(min(size_X_effective, size_Y_effective)-(t-t0-max(size_X_effective, size_Y_effective)))
    
    # -----------------------------------------------------------------------------
    # Accumulate deltas into actual values
    # -----------------------------------------------------------------------------
    
    active_PEs = np.zeros((total_comp_cycles), dtype=int)
    
    for t in range(1,total_comp_cycles-1):
        active_PEs[t] = active_PEs[t-1] + delta_PEs[t]
    
    # -----------------------------------------------------------------------------
    # Final arrays and metrics
    # -----------------------------------------------------------------------------
    
    # Replication just multiplies number of PEs
    active_PEs = active_PEs*replication_X*replication_Y
    
    # Active PEs taking into account pipeline cycles
    active_PEs_complete = np.zeros((pipeline_CLK_cycles*total_comp_cycles), dtype=int)
    
    for i in range(pipeline_CLK_cycles):
        active_PEs_complete[i::pipeline_CLK_cycles] = active_PEs
    
    # Total timeline taking into account computation and shift overhead
    timeline_complete = np.concatenate((np.zeros(scan_overhead_cycles, dtype=int),active_PEs_complete))
    
    # Total computations made
    total_PE_computations = np.sum(active_PEs)
    
    total_FLOP = total_PE_computations*2
    total_cycles = n_stalls + timeline_complete.size
    total_time = total_cycles * CLK_period
    
    FLOPS = total_FLOP/total_time
    ideal_FLOPS = (2*size_X*size_Y*replication_X*replication_Y)/(pipeline_CLK_cycles*CLK_period)
    
    # Print FLOPS results
    if not silent:
        print("\nTotal cycles:")
        print("{}".format(total_cycles))
        print("\nFeeding stalls:")
        print("{} ({:.3f}%)".format(n_stalls, 100*n_stalls/total_cycles))
        print("\nTotal time:")
        print("{} ns".format(total_time*1e9))
        print("\nTotal ops:")
        print("{}".format(total_PE_computations))
        print("\nThroughput:")
        print("{:.3f} GFLOPS".format(FLOPS/1e9))
        print("\nUtilization:")
        print("{:.3f}%".format(100*FLOPS/ideal_FLOPS))
    
    return timeline_complete, FLOPS, ideal_FLOPS, total_FLOP, total_cycles, total_time


# ***********************
# Bandwidth Estimation
# ***********************

def estimate_BW(assigned_SRAM_A, assigned_SRAM_B, assigned_SRAM_C, total_time, SA_Param_dict, silent=False):
    """
        
      DOCSTRINGS TO-DO  
    

    Parameters
    ----------
    assigned_SRAM_A : TYPE
        DESCRIPTION.
    assigned_SRAM_B : TYPE
        DESCRIPTION.
    assigned_SRAM_C : TYPE
        DESCRIPTION.
    total_time : TYPE
        DESCRIPTION.
    SA_Param_dict : TYPE
        DESCRIPTION.
    silent : TYPE, optional
        DESCRIPTION. The default is False.

    Returns
    -------
    DRAM_BW : TYPE
        DESCRIPTION.
    DRAM_BW_activations : TYPE
        DESCRIPTION.
    DRAM_BW_weights : TYPE
        DESCRIPTION.
    DRAM_BW_outputs : TYPE
        DESCRIPTION.

    """
    
    CLK_period = SA_Param_dict['CLK_period']    

    total_SRAM_occupation = assigned_SRAM_A + assigned_SRAM_B + assigned_SRAM_C + (SA_Param_dict['preload_en']==1)*assigned_SRAM_C

    DRAM_BW = total_SRAM_occupation/total_time
    DRAM_BW_activations = assigned_SRAM_A/total_time
    DRAM_BW_weights = assigned_SRAM_B/total_time
    DRAM_BW_outputs = (assigned_SRAM_C + (SA_Param_dict['preload_en']==1)*assigned_SRAM_C)/total_time
    
    RealDRAM_time = total_SRAM_occupation/(SA_Param_dict['DRAM_BW']*8)
    
    # Print Bandwidth results
    if not silent:
        print("\nBandwidth needed for zero stalls:")
        print("Total DRAM BW = {:.3f} Bytes/cycle [{:.3f} MB/s]".format(DRAM_BW*CLK_period/8, DRAM_BW/(8e6)))
        print("DRAM IFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_activations*CLK_period/8))
        print("DRAM Filter BW = {:.3f} Bytes/cycle".format(DRAM_BW_weights*CLK_period/8))
        print("DRAM OFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_outputs*CLK_period/8))
        
        print("\nTotal time for one tile: {:.3f} us".format(total_time*1e6))
        print("Total DRAM transaction time for one tile: {:.3f} us".format(RealDRAM_time*1e6))

    return DRAM_BW, DRAM_BW_activations, DRAM_BW_weights, DRAM_BW_outputs

def quick_estimate_BW(SA_Param_dict, external=False, rep_part='A', ext_reps=1, silent=False):
    
    DRAM_BW_activations =   (SA_Param_dict['X_used']*SA_Param_dict['Y_used']/SA_Param_dict['CLK_period'])*(SA_Param_dict['bits_Activations']/(SA_Param_dict['B_w']*SA_Param_dict['B_h']*SA_Param_dict['C_c']))
    DRAM_BW_weights =       (SA_Param_dict['X_used']*SA_Param_dict['Y_used']/SA_Param_dict['CLK_period'])*(SA_Param_dict['bits_Weights']/(SA_Param_dict['C_w']*SA_Param_dict['C_h']))
    DRAM_BW_outputs =       (SA_Param_dict['X_used']*SA_Param_dict['Y_used']/SA_Param_dict['CLK_period'])*(((SA_Param_dict['preload_en']+1)*SA_Param_dict['bits_Outputs'])/(SA_Param_dict['B_w']*SA_Param_dict['B_h']*SA_Param_dict['AB_c']))

    DRAM_BW = DRAM_BW_activations + DRAM_BW_weights + DRAM_BW_outputs
    CLK_period = SA_Param_dict['CLK_period']    

    if external:
        
        DRAM_BW_activations_Ext = DRAM_BW_activations
        DRAM_BW_weights_Ext= DRAM_BW_weights
        DRAM_BW_outputs_Ext= DRAM_BW_outputs
        
        if rep_part=='A':
            DRAM_BW_activations_Ext = DRAM_BW_activations_Ext/ext_reps
        elif rep_part=='B':
            DRAM_BW_weights_Ext = DRAM_BW_weights_Ext/ext_reps
        else:
            DRAM_BW_outputs_Ext = DRAM_BW_outputs_Ext/ext_reps
        
        DRAM_BW_Ext = DRAM_BW_activations_Ext + DRAM_BW_weights_Ext + DRAM_BW_outputs_Ext

    # Print Bandwidth results
    if not silent:
        print("\nBandwidth needed for zero stalls:")
        print("Total DRAM BW = {:.3f} Bytes/cycle [{:.3f} MB/s]".format(DRAM_BW*CLK_period/8, DRAM_BW/(8e6)))
        print("DRAM IFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_activations*CLK_period/8))
        print("DRAM Filter BW = {:.3f} Bytes/cycle".format(DRAM_BW_weights*CLK_period/8))
        print("DRAM OFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_outputs*CLK_period/8))
        
        if external:
            print("\nBandwidth needed for zero stalls (EXTERNAL):")
            print("Total DRAM BW = {:.3f} Bytes/cycle [{:.3f} MB/s]".format(DRAM_BW_Ext*CLK_period/8, DRAM_BW_Ext/(8e6)))
            print("DRAM IFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_activations_Ext*CLK_period/8))
            print("DRAM Filter BW = {:.3f} Bytes/cycle".format(DRAM_BW_weights_Ext*CLK_period/8))
            print("DRAM OFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_outputs_Ext*CLK_period/8))
            
        
    return DRAM_BW, DRAM_BW_activations, DRAM_BW_weights, DRAM_BW_outputs

def estimate_BW_external(LAYERS, assigned_SRAM_A, assigned_SRAM_B, assigned_SRAM_C, total_time, SA_Param_dict, mem_held='auto', silent=False):
    """
        
      DOCSTRINGS TO-DO  
    

    Parameters
    ----------
    assigned_SRAM_A : TYPE
        DESCRIPTION.
    assigned_SRAM_B : TYPE
        DESCRIPTION.
    assigned_SRAM_C : TYPE
        DESCRIPTION.
    total_time : TYPE
        DESCRIPTION.
    SA_Param_dict : TYPE
        DESCRIPTION.
    silent : TYPE, optional
        DESCRIPTION. The default is False.

    Returns
    -------
    DRAM_BW : TYPE
        DESCRIPTION.
    DRAM_BW_activations : TYPE
        DESCRIPTION.
    DRAM_BW_weights : TYPE
        DESCRIPTION.
    DRAM_BW_outputs : TYPE
        DESCRIPTION.

    """
    
    CLK_period = SA_Param_dict['CLK_period']    

    # Extract layer parameters
    #[AB_c,     C_c,    Bw,     Bh,     C_w,    C_h,    s,      d]
    
    AB_c_ext =  LAYERS[0]
    C_c_ext =   LAYERS[1]

    C_w_ext =   LAYERS[4]
    C_h_ext =   LAYERS[5]
    
    iter_AB_c = np.ceil(AB_c_ext/SA_Param_dict['AB_c'])
    iter_C_c = np.ceil(C_c_ext/SA_Param_dict['C_c'])
    iter_C_w = np.ceil(C_w_ext/SA_Param_dict['C_w'])
    iter_C_h = np.ceil(C_h_ext/SA_Param_dict['C_h'])

    total_time_external = total_time*iter_AB_c*iter_C_c*iter_C_w*iter_C_h
    
    # Initial approximation copying all data all the time
    total_SRAMA = assigned_SRAM_A*iter_AB_c*iter_C_c*iter_C_w*iter_C_h
    total_SRAMB = assigned_SRAM_B*iter_AB_c*iter_C_c*iter_C_w*iter_C_h
    total_SRAMC = assigned_SRAM_C*iter_AB_c*iter_C_c*iter_C_w*iter_C_h
    
    #print(total_SRAMA, total_SRAMB)
    
    # Automatic detection of what should we hold, based on transaction size
    if mem_held == 'auto':
        if (total_SRAMA>total_SRAMB):
            if (total_SRAMC>total_SRAMA):
                mem_held = 'C'
            else:
                mem_held = 'A'
        else:
            if (total_SRAMC>total_SRAMB):
                mem_held = 'C'
            else:
                mem_held = 'B'
    
    #print(mem_held)
    
    # If SRAMA is maintaied, we do not have to move it while we are completing C_c
    if mem_held == 'A':
        total_SRAMA = assigned_SRAM_A*iter_AB_c*iter_C_w*iter_C_h
        
    # If SRAMB is maintained, we do not have to move it while we are completing Cw, Ch
    if mem_held == 'B':
        total_SRAMB = assigned_SRAM_B*iter_AB_c*iter_C_c
    
    # If SRAMC is maintained, we do not have to move it while we are completing ABc
    if mem_held == 'C':
        total_SRAMC = assigned_SRAM_C*iter_C_c*iter_C_w*iter_C_h
    
    DRAM_BW_activations = total_SRAMA/total_time_external
    DRAM_BW_weights = total_SRAMB/total_time_external
    DRAM_BW_outputs = (total_SRAMC + (SA_Param_dict['preload_en']==1)*total_SRAMC)/total_time_external
    
    DRAM_BW = DRAM_BW_activations + DRAM_BW_weights + DRAM_BW_outputs
    
    RealDRAM_time = (total_SRAMA+total_SRAMB+(total_SRAMC + (SA_Param_dict['preload_en']==1)*total_SRAMC))/(SA_Param_dict['DRAM_BW']*8)
    
    Final_time = max(RealDRAM_time, total_time_external)
    
    # Print Bandwidth results
    if not silent:
        print("\nBandwidth needed for zero stalls (EXTERNAL TILING):")
        print("Total DRAM BW = {:.3f} Bytes/cycle [{:.3f} MB/s]".format(DRAM_BW*CLK_period/8, DRAM_BW/(8e6)))
        print("DRAM IFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_activations*CLK_period/8))
        print("DRAM Filter BW = {:.3f} Bytes/cycle".format(DRAM_BW_weights*CLK_period/8))
        print("DRAM OFmap BW = {:.3f} Bytes/cycle".format(DRAM_BW_outputs*CLK_period/8))
        
        print("\nTotal tiling iterations: {}".format(iter_AB_c*iter_C_c*iter_C_w*iter_C_h))
        print("Total time for all tiles: {:.3f} ms".format(total_time_external*1e3))
        print("Total DRAM transaction time: {:.3f} ms".format(RealDRAM_time*1e3))
        
        if (RealDRAM_time>total_time_external):
            print("\nDRAM is the bottleneck.")
        else:
            print("\nArray is the bottleneck.")
        
        print("Total final time: {:.3f} ms".format(Final_time*1e3))

    return DRAM_BW, DRAM_BW_activations, DRAM_BW_weights, DRAM_BW_outputs, RealDRAM_time, total_time_external, Final_time

# *****************************
# Pipeline Stalls Estimation
# *****************************

def estimate_stalls(SA_Param_dict, silent=False):
    """
        
      DOCSTRINGS TO-DO  
    

    Parameters
    ----------
    assigned_SRAM_A : TYPE
        DESCRIPTION.
    assigned_SRAM_B : TYPE
        DESCRIPTION.
    assigned_SRAM_C : TYPE
        DESCRIPTION.
    total_time : TYPE
        DESCRIPTION.
    SA_Param_dict : TYPE
        DESCRIPTION.
    silent : TYPE, optional
        DESCRIPTION. The default is False.

    Returns
    -------
    DRAM_BW : TYPE
        DESCRIPTION.
    DRAM_BW_activations : TYPE
        DESCRIPTION.
    DRAM_BW_weights : TYPE
        DESCRIPTION.
    DRAM_BW_outputs : TYPE
        DESCRIPTION.

    """
    
    N_TIME_MAX = 5000000
    
    # Configuration constants
    # ---------------------------------------------------------------------------------------

    A_w = SA_Param_dict['A_w']
    A_h = SA_Param_dict['A_h']
    AB_c = SA_Param_dict['AB_c']
    
    B_w = SA_Param_dict['B_w']
    B_h = SA_Param_dict['B_h']

    d = SA_Param_dict['d']
    s = SA_Param_dict['s']

    B_w_eff = 1 + (B_w - 1)*d

    C_w = SA_Param_dict['C_w']
    C_h = SA_Param_dict['C_h']
    C_c = SA_Param_dict['C_c']
    
    size_Y = SA_Param_dict['size_Y']
    size_X = SA_Param_dict['size_X']
    
    atm_C_w = SA_Param_dict['atm_C_w']
    atm_C_h = SA_Param_dict['atm_C_h']
    
    atm_C_w_eff = 1 + (atm_C_w - 1)*s
    
    atm_A_c = SA_Param_dict['atm_A_c']
    atm_A_w = SA_Param_dict['atm_A_w']
    atm_A_h = SA_Param_dict['atm_A_h']

    ACT_IA_W = SA_Param_dict['ACT_IA_W']
    WEI_IB_W = SA_Param_dict['WEI_IB_W']
    ACT_SRAMA_W = SA_Param_dict['ACT_SRAMA_W']
    WEI_SRAMB_W = SA_Param_dict['WEI_SRAMB_W']
    ACT_WOFS_W = SA_Param_dict['ACT_WOFS_W']
    WEI_WOFS_W = SA_Param_dict['WEI_WOFS_W']
    
    ACT_FIFO_POSITIONS = SA_Param_dict['ACT_FIFO_POSITIONS']
    WEI_FIFO_POSITIONS = SA_Param_dict['WEI_FIFO_POSITIONS']
    FIFO_FILL_CYCLES = SA_Param_dict['FIFO_FILL_CYCLES']
    
    ACT_SRAMA_N = int(ACT_SRAMA_W/ACT_IA_W)
    WEI_SRAMB_N = int(WEI_SRAMB_W/WEI_IB_W)

    lwoffs = np.arange(size_Y)*s
        
    n_rows = SA_Param_dict['Y_used']
    n_cols = SA_Param_dict['X_used']
    
    # Row & column masks generation
    rows_active_str = '0b'
    rows_active_arr = np.zeros((size_Y), dtype=np.bool)
    cols_active_str = '0b'
    cols_active_arr = np.zeros((size_X), dtype=np.bool)
    
    for j in range(size_Y):
        if (j<n_rows):
            rows_active_str = rows_active_str + '1'
            rows_active_arr[j] = 1
        else:
            rows_active_str = rows_active_str + '0'
            
    for i in range(size_X):
        if (i<n_cols):
            cols_active_str = cols_active_str + '1'
            cols_active_arr[i] = 1
        else:
            cols_active_str = cols_active_str + '0'
            
    # ACTIVATIONS: Golden Model for SRAM Address generation
    # ---------------------------------------------------------------------------------------

    temp_addr_arr_act = np.zeros((N_TIME_MAX), dtype=np.int64)
    temp_delta_inputs_act = np.zeros((N_TIME_MAX, size_Y))
    temp_gwoffs_act = np.zeros((N_TIME_MAX))

    # Conditions for aligned memory operation (faster)
    if (s==1) and (d==1) and (B_w==1) and (B_h==1) and (AB_c%ACT_SRAMA_N == 0) and (n_rows%ACT_SRAMA_N==0):
        X_STEPS = int(np.ceil(atm_A_w/ACT_SRAMA_N))
    else:
        X_STEPS = int(np.ceil(atm_A_w/ACT_SRAMA_N)) + 1
    
    # Outer tiling coefficients
    x_id_itr_max = np.ceil(C_w/atm_C_w).astype(int)
    y_id_itr_max = np.ceil(C_h/atm_C_h).astype(int)
    
    k_id_itr_max = np.ceil(C_c/size_X).astype(int)

    # Index init
    aidx = 0

    # OUTER TILE -> (WEIGHTS - CHANNEL TILING)
    for k_id_itr in range(k_id_itr_max):
    
        # OUTER TILE (ACTIVATIONS - SPATIAL TILING)
        for y_id_itr in range(y_id_itr_max):
            for x_id_itr in range(x_id_itr_max):
                
                glob_index = A_w*atm_C_h*s*y_id_itr + atm_C_w*s*x_id_itr
                            
                # INNER (ATOMIC) TILE -> Managed by data manager
                for ch in range(atm_A_c):                    
                    for y in range(0, atm_A_h, d):              # Must take dilation into account!
                        for xstep in range(X_STEPS):            # X index as advancing through the addresses
                        
                            # Index counters
                            index = ACT_SRAMA_N*xstep + y*A_w + ch*A_w*A_h + glob_index
                            address = index>>ACT_WOFS_W
                            gwoffs = index & (2**ACT_WOFS_W-1)
                            
                            temp_addr_arr_act[aidx] = address
                            temp_gwoffs_act[aidx] = gwoffs
                                
                            # Local woffs of current feeder
                            if xstep==0:
                                woffs_init = lwoffs + gwoffs
    
                            x_index_i = lwoffs + ACT_SRAMA_N*xstep + x_id_itr*atm_C_w_eff
                            x_index_f = lwoffs + ACT_SRAMA_N*(xstep+1)-1 + x_id_itr*atm_C_w_eff
                                
                            # Current x boundaries
                            xi = x_index_i - woffs_init
                            xf = x_index_f - woffs_init
                        
                            # Region check for every feeder
                            for j in range(n_rows):
                                
                                # Look for the positions of the convolution kernel
                                for x in range(0, B_w_eff, d):
                                    
                                    x_interest  = x + x_id_itr*atm_C_w_eff + lwoffs
                                    
                                    # Can only take the things that are currently here :P
                                    if ((x_interest[j]>=xi[j]) and (x_interest[j]<=xf[j])):
                                        
                                        temp_delta_inputs_act[aidx,j] += 1                               
                            
                            # Advance time
                            aidx += 1

    # WEIGHTS: Golden Model for SRAM Address generation
    # ---------------------------------------------------------------------------------------

    temp_delta_inputs_wei = np.zeros((N_TIME_MAX, size_X))

    # Conditions for aligned memory operation (faster)
    if ((B_w*B_h*AB_c)%WEI_SRAMB_N == 0) and ((B_w*B_h*AB_c)>WEI_SRAMB_N):      # New restriction: at least 2*SRAMB_N
        W_STEPS = int(np.ceil((B_w*B_h*AB_c)/WEI_SRAMB_N))
    else:
        W_STEPS = int(np.ceil((B_w*B_h*AB_c)/WEI_SRAMB_N)) + 1

    # Index init
    bidx = 0

    # OUTER TILE -> (WEIGHTS - CHANNEL TILING)
    for k_id_itr in range(k_id_itr_max):
                  
        # OUTER TILE (ACTIVATIONS - SPATIAL TILING) => Affects nothing, weights are just repeated!
        for y_id_itr in range(y_id_itr_max):
            for x_id_itr in range(x_id_itr_max):        
    
                glob_index = k_id_itr*B_w*B_h*AB_c*n_cols
                            
                # INNER (ATOMIC) TILE -> Managed by data manager          
                for wstep in range(W_STEPS):            
                    for k in range(n_cols):
                        
                            # Index counters
                            index = WEI_SRAMB_N*wstep + k*B_w*B_h*AB_c + glob_index
                            address = index>>WEI_WOFS_W
                            gwoffs = index & (2**WEI_WOFS_W-1)
                            
                            # First word (special)
                            if wstep==0:
                                wi = gwoffs + (address<<WEI_WOFS_W)
                                wf = (address<<WEI_WOFS_W) + (WEI_SRAMB_N-1)
                            else:
                                wi = (address<<WEI_WOFS_W)
                                wf = (address<<WEI_WOFS_W) + (WEI_SRAMB_N-1)
                        
                            # Look for the positions of the convolution kernel
                            for w in range(0, B_w*B_h*AB_c):
                                
                                w_interest  = w + k*B_w*B_h*AB_c + k_id_itr*B_w*B_h*AB_c*n_cols
                                
                                # Can only take the things that are currently here :P
                                if ((w_interest>=wi) and (w_interest<=wf)):
                                    
                                    temp_delta_inputs_wei[bidx,k] += 1                               
                            
                            # Advance time
                            bidx += 1
       
    aidx_max = aidx - 1
    bidx_max = bidx - 1

    # ACTIVATIONS AND WEIGHTS: Golden Model for FIFO & push behavior
    # ---------------------------------------------------------------------------------------
    
    t = 0
    fo_lat = 0
    
    fifo_occupation_act = np.zeros((N_TIME_MAX, size_Y))
    pingpong_occupation_act = np.zeros((N_TIME_MAX, size_Y), dtype=np.uint64)
    pipeline_empty_check_act = np.ones((N_TIME_MAX))
    
    fifo_occupation_wei = np.zeros((N_TIME_MAX, size_X))
    pingpong_occupation_wei = np.zeros((N_TIME_MAX, size_X), dtype=np.uint64)
    pipeline_empty_check_wei = np.ones((N_TIME_MAX))
    
    pipeline_stalls = np.zeros((N_TIME_MAX))
    
    # Fifos start inactive
    active_fifo_idx = 0
    active_fifos = np.zeros((max(size_X,size_Y)))
    
    # Clear address index
    aidx = 0
    bidx = 0
    
    done = False
    
    tinnit = 0
    shift_started = False
    
    while (not done):     
        
        # Raise an error if a deadlock happens
        if((fifo_occupation_act[t+fo_lat-1, :n_rows]<=(1/ACT_SRAMA_N)).any() and (fifo_occupation_act[t+fo_lat-1, :n_rows]>(ACT_FIFO_POSITIONS-1)).any()) or ((fifo_occupation_wei[t+fo_lat-1, :n_cols]<=(1/WEI_SRAMB_N)).any() and (fifo_occupation_wei[t+fo_lat-1, :n_cols]>(WEI_FIFO_POSITIONS-1)).any()):
            print("ERROR: Deadlock situation")
            
            print(fifo_occupation_act[t+fo_lat-15:t+fo_lat-1, :n_rows])
            
            assert 0                                                                                                                                        
        
        # FIFO pop enable signals propagate at the beginning
        if ((fifo_occupation_act[t-2-(FIFO_FILL_CYCLES+1), :n_rows]>0).all()) and ((fifo_occupation_wei[t-2-(FIFO_FILL_CYCLES+1), :n_cols]>0).all()) and (active_fifo_idx<max(size_X,size_Y)):

            shift_started = True
            active_fifos[active_fifo_idx] = 1
            active_fifo_idx += 1

        if not shift_started:
            pipeline_stalls[t] = 1

        # Maintain previous states
        fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t-1+fo_lat]
        pingpong_occupation_act[t] = pingpong_occupation_act[t-1]
        
        fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t-1+fo_lat]
        pingpong_occupation_wei[t] = pingpong_occupation_wei[t-1]

        # [ACT] If ANY FIFO is full, we need to hold everything and wait until at least 1 position is "drained"
        if (np.ceil(fifo_occupation_act[t-1+fo_lat])>ACT_FIFO_POSITIONS-1).any():
            
            pingpong_occupation_act[t] = pingpong_occupation_act[t-1]
        
        # [ACT] FIFOs not full => Time to read next position
        else:

            # Maintain previous states
            fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t-1+fo_lat]
    
            # Add deltas to pingpong
            pingpong_occupation_act[t] = pingpong_occupation_act[t-1] + temp_delta_inputs_act[aidx]
            
            # Account for pushing of pingpong values
            for j in range(size_Y):
                if (pingpong_occupation_act[t,j]>=ACT_SRAMA_N):
                    
                    pingpong_occupation_act[t,j] = pingpong_occupation_act[t,j] % ACT_SRAMA_N
                    fifo_occupation_act[t+fo_lat,j] = fifo_occupation_act[t+fo_lat,j] + 1            
                    
            aidx += 1

        # [WEI] : 2 cycle delay at the beginning
        if (tinnit>1):
    
            # [WEI] If ANY FIFO is full, we need to hold everything and wait until at least 1 position is "drained"
            if (np.ceil(fifo_occupation_wei[t-1+fo_lat])>WEI_FIFO_POSITIONS-1).any():
                
                pingpong_occupation_wei[t] = pingpong_occupation_wei[t-1]

            # [WEI] FIFOs not full => Time to read next position
            else:
    
                # Maintain previous states
                fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t-1+fo_lat]
        
                # Add deltas to pingpong
                pingpong_occupation_wei[t] = pingpong_occupation_wei[t-1] + temp_delta_inputs_wei[bidx]
                
                # Account for pushing of pingpong values
                for i in range(size_X):
                    if (pingpong_occupation_wei[t,i]>=WEI_SRAMB_N):
                        
                        pingpong_occupation_wei[t,i] = pingpong_occupation_wei[t,i] % WEI_SRAMB_N
                        fifo_occupation_wei[t+fo_lat,i] = fifo_occupation_wei[t+fo_lat,i] + 1            
                        
                bidx += 1
                     
        # Every cycle, 1/SRAM_N positions are shifted into the array, IF fifo is not empty
        if (fifo_occupation_act[t+fo_lat-1, :n_rows]>(1/ACT_SRAMA_N)).all() and (fifo_occupation_wei[t+fo_lat-1, :n_cols]>(1/WEI_SRAMB_N)).all():
        #if (fifo_occupation_act[t+fo_lat-1]>(1/ACT_SRAMA_N)).all():
            
            fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t+fo_lat] - (1/ACT_SRAMA_N)*active_fifos[:size_Y]*rows_active_arr
            fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t+fo_lat] - (1/WEI_SRAMB_N)*active_fifos[:size_X]*cols_active_arr

        else:
            pipeline_stalls[t] = 1

        # Advance time
        t+=1
        tinnit+=1
        
        if (aidx>aidx_max) and (bidx>bidx_max):
            done = True
    
    # Final pipeline shifting
    fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t-1+fo_lat]
    pingpong_occupation_act[t] = pingpong_occupation_act[t-1]        

    fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t-1+fo_lat]
    pingpong_occupation_wei[t] = pingpong_occupation_wei[t-1]    

    # If ANY FIFO is full, we need to hold everything and wait until at least 1 position is "drained"
    while (np.ceil(fifo_occupation_act[t+fo_lat-1])>ACT_FIFO_POSITIONS-1).any() or (np.ceil(fifo_occupation_wei[t+fo_lat-1])>WEI_FIFO_POSITIONS-1).any():
        
        pingpong_occupation_act[t] = pingpong_occupation_act[t-1]
        pingpong_occupation_wei[t] = pingpong_occupation_wei[t-1]
        
        # Every cycle, 1/SRAM_N positions are shifted into the array and substracted
        fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t-1+fo_lat] - (1/ACT_SRAMA_N)*active_fifos[:size_Y]*rows_active_arr
        fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t-1+fo_lat] - (1/WEI_SRAMB_N)*active_fifos[:size_X]*cols_active_arr

        t+=1

    # Shifting of last pipeline values. Just accept this as true :)
    fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t-1+fo_lat] + 1*rows_active_arr
    pingpong_occupation_act[t] = pingpong_occupation_act[t-1]  

    fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t-1+fo_lat] + 1*cols_active_arr
    pingpong_occupation_wei[t] = pingpong_occupation_wei[t-1]  
    
    # Every cycle, 1/SRAM_N positions are shifted into the array, IF fifo is not empty
    if (fifo_occupation_act[t+fo_lat-1, :n_rows]>(1/ACT_SRAMA_N)).all() and (fifo_occupation_wei[t+fo_lat-1, :n_cols]>(1/WEI_SRAMB_N)).all():
        
        fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t+fo_lat] - (1/ACT_SRAMA_N)*active_fifos[:size_Y]*rows_active_arr
        fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t+fo_lat] - (1/WEI_SRAMB_N)*active_fifos[:size_X]*cols_active_arr

    else:
        pipeline_stalls[t] = 1

    t+= 1
    
    FIFO_done = False
    
    # Shift of remaining FIFO pipeline values
    while not FIFO_done:

        # FIFO pop enable signals may still need to propagate!
        if ((fifo_occupation_act[t-2-(FIFO_FILL_CYCLES+1), :n_rows]>0).all()) and ((fifo_occupation_wei[t-2-(FIFO_FILL_CYCLES+1), :n_cols]>0).all()) and (active_fifo_idx<max(size_X,size_Y)):

            shift_started = True
            active_fifos[active_fifo_idx] = 1
            active_fifo_idx += 1        

        # Check at the beginning in order to do 1 extra cycle (latency)
        if (fifo_occupation_act[t+fo_lat-1]<=0).all() and (fifo_occupation_wei[t+fo_lat-1]<=0).all():
            FIFO_done = True

        # Important to have pipeline_en to 1 during this period!
        pipeline_empty_check_act[t+6] = 0
        pipeline_empty_check_wei[t+6] = 0
            
        fifo_occupation_act[t+fo_lat] = fifo_occupation_act[t+fo_lat-1] - (1/ACT_SRAMA_N)*active_fifos[:size_Y]*rows_active_arr
        fifo_occupation_wei[t+fo_lat] = fifo_occupation_wei[t+fo_lat-1] - (1/WEI_SRAMB_N)*active_fifos[:size_X]*cols_active_arr
                
        t+= 1
        
    # Maintain enable until pipeline is completed
    for _ in range((max(size_X,size_Y)-1)):
        t+=1

    t+= 10           # Rest cycles at the end

    # Crop to final time
    fifo_occupation_act = fifo_occupation_act[:t]
    fifo_occupation_wei = fifo_occupation_wei[:t]
    pingpong_occupation_act = pingpong_occupation_act[:t]
    pingpong_occupation_wei = pingpong_occupation_wei[:t]
    pipeline_stalls = pipeline_stalls[:t]

    # Number of stall cycles
    n_stalls = pipeline_stalls.sum()

    return fifo_occupation_act, fifo_occupation_wei, pingpong_occupation_act, pingpong_occupation_wei, pipeline_stalls, n_stalls
