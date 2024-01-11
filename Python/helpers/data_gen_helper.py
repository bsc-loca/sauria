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
import helpers.test_helper as th

import helpers.drac_sa_top_helper as dsth

# --------------------------------------------
# Generate random tensor with zome sparsity
# --------------------------------------------

def gen_random_tensor(shape, pzero, bit_width, FP=False, distribution='unif'):

    # Uniform distribution
    if (distribution=='unif'):
        start_values = (np.random.random(shape) - 0.5)
        
    # Gaussian distribution
    elif (distribution=='gauss'):
        start_values = np.random.normal(scale=th.TOPTS['gauss_scale'], size=shape)
        
    # Default: uniform
    else:
        start_values = np.random.random(shape)
    
    # Enforce zeros (sparsity)
    tensor = start_values * (np.random.random(shape)>pzero) 
    
    # Integer random values
    if not FP:
        tensor = np.round(tensor*((2<<(bit_width-1))-1)).astype(np.int32)
        
    # FP16 random values
    else:
        tensor = tensor.astype(np.float16)

    # ONES TEST - Overwrite everything and put '1's
    if th.TOPTS['ones_test']:
        tensor[:] = 1

    return tensor

# --------------------------------------------------------------
# Generate the three random tensors for a convolution (A,B,C)
# --------------------------------------------------------------

def generate_tensors(CONV, HYPER):
    
    # Retrieve tensor shapes
    B_w = CONV['B_w']
    B_h = CONV['B_h']
    C_w = CONV['C_w']
    C_h = CONV['C_h']
    C_c = CONV['C_c']
    A_w = CONV['A_w']
    A_h = CONV['A_h']
    A_c = CONV['A_c']
    
    # Random distribution
    distribution = 'gauss' if (HYPER['OP_TYPE']==1) else 'unif'
                   
    # Activations tensor
    A_tensor = gen_random_tensor([A_c,A_h,A_w], th.TOPTS['pzero_A'], HYPER['IA_W'], HYPER['OP_TYPE'], distribution)
            
    # Weights tensor
    B_tensor = gen_random_tensor([C_c,A_c,B_h,B_w], th.TOPTS['pzero_B'], HYPER['IB_W'], HYPER['OP_TYPE'], distribution)
    
    # Partial sums tensor
    C_tensor = gen_random_tensor([C_c,C_h,C_w], th.TOPTS['pzero_C'], HYPER['OC_W'], HYPER['OP_TYPE'], distribution)
            
    # FOR EASY DEBUGGING, PUT SOME RECOGNIZABLE VALUES
    if th.TOPTS['insert_deadbeef']:
        if (HYPER['OP_TYPE']==1):
                
            MANT_W = th.HOPTS['IC_MANT']
            EXP_W = HYPER['OC_W'] - th.HOPTS['IC_MANT'] - 1
            
            B_tensor[:,0,0,0] =         dsth.FP_to_val(0xbeef, MANT_W, EXP_W)
            B_tensor[:,-1,-1,-1] =      dsth.FP_to_val(0xbeef, MANT_W, EXP_W)
            
            C_tensor[0,:,0] =                                   dsth.FP_to_val(0xbeef, MANT_W, EXP_W)
            C_tensor[CONV['X_used']-1,:,:] =                    dsth.FP_to_val(0xdead, MANT_W, EXP_W)
            C_tensor[0,:,CONV['Y_used']-1] =                    dsth.FP_to_val(0xbebe, MANT_W, EXP_W)
            C_tensor[CONV['X_used']-1,:,CONV['Y_used']-1] =     dsth.FP_to_val(0xfe0, MANT_W, EXP_W)
            C_tensor[-1,:,-1] =                                 dsth.FP_to_val(0xfe0, MANT_W, EXP_W)            

        else:
            IB_MASK = ((2**HYPER['IB_W']) - 1)
            OC_MASK = ((2**HYPER['OC_W']) - 1)
            
            B_tensor[:,0,0,0] =         -1*((16657)&IB_MASK)     #0xBEEF
            B_tensor[:,-1,-1,-1] =      -1*((16657)&IB_MASK)     #0xBEEF
            
            C_tensor[0,:,0] =                                   0xBEEF & OC_MASK
            C_tensor[CONV['X_used']-1,:,:] =                    0xDEAD & OC_MASK
            C_tensor[0,:,CONV['Y_used']-1] =                    0xBEBE & OC_MASK
            C_tensor[CONV['X_used']-1,:,CONV['Y_used']-1] =     0x0FE0 & OC_MASK
            C_tensor[-1,:,-1] =                                 0x0FE0 & OC_MASK    
        
    # If preload enable is zero, all C values start at zero
    if CONV['preload_en'] == 0: C_tensor[:] = 0

    return A_tensor, B_tensor, C_tensor



