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

sys.path.insert(1, './../')

def booth_multiplier(a, b, N_bits=16, m=16, approx=''):
    
    if (np.isscalar(a) or np.isscalar(b)):
        a = np.array([a])
        b = np.array([b])
    
    a_masked = a
    b_masked = b
    
    bit_groups = int(np.ceil(N_bits/2))     # Sure about the ceiling? - yah
    
    # MAKE GROUPINGS
    groups_array = np.zeros((a.shape[0], bit_groups), dtype=np.int)
    
    # Must handle numbers one by one, unfortunately
    for n in range(a.shape[0]):
    
        a_bin = np.binary_repr(a_masked[n], N_bits)
        a_bin = a_bin[::-1]     # Change endianness
    
        for i in range(bit_groups):
            
            if (i==0):
                groups_array[n,0] = int("0b" + a_bin[2*i:2*i+2][::-1] + "0", 2)
            else:
                groups_array[n,i] = int("0b" + a_bin[2*i-1:2*i+2][::-1], 2)
        
    # Generate control signals
    zero =  np.logical_or((groups_array == 0), (groups_array == 7))
    neg =   np.logical_and((groups_array >= 4), (groups_array != 7))
    two =   np.logical_or((groups_array == 3), (groups_array == 4))
        
    # ------------------------------
    # PARTIAL PRODUCTS GENERATION
    # ------------------------------
    
    mask_Nb = ((2**(N_bits+1))-1)
    neg_padding = ((1<<32)-1) - mask_Nb
    
    pproducts = np.zeros((a.shape[0], bit_groups), dtype=np.uint32)
    pproducts_aprox = np.zeros((a.shape[0], bit_groups), dtype=np.uint32)
    pproducts_final = np.zeros((a.shape[0], bit_groups), dtype=np.uint32)
    final_sum = np.zeros((a.shape), np.int32)
    
    # EXACT (we always need it)
    # ***************************
            
    for i in range(bit_groups):
        
        negmask =   neg[:,i] * mask_Nb
        zeromask =  (~zero[:,i]) * mask_Nb
        twomask =   two[:,i] * mask_Nb
        
        # Exact partial products
        pproducts[:,i] = ((((twomask ^ mask_Nb) & b_masked) | (twomask & (b_masked<<1))) ^ negmask) & zeromask
                
        # ONLY IF EXACT MULTIPLIER => Exact bit correction
        if (approx==''):
            
            pproducts_final[:,i] = pproducts[:,i]
            
            # Sign correction
            pproducts_final[:,i] = pproducts_final[:,i] + neg[:,i].astype(np.int)
            
        # Approx type M1
        # ******************
        elif(approx=='M1'):
    
            # Get approximation boundary and generate masks
            approx_boundary = m-2*i
            approx_boundary = approx_boundary * (approx_boundary>0) # Only positive values
            
            approx_mask = (2**approx_boundary)-1
            exact_mask = mask_Nb ^ approx_mask
                    
            # Approx partial products version
            pproducts_aprox[:,i] = (((negmask ^ mask_Nb) & b_masked) | (negmask & (b_masked ^ mask_Nb))) & zeromask
            
            # Combine approximate and exact parts
            pproducts_final[:,i] = (pproducts_aprox[:,i] & approx_mask) | (pproducts[:,i] & exact_mask)
            
            # Sign correction (aprox)
            pproducts_final[:,i] = pproducts_final[:,i] | (0x1 & neg[:,i])
            
        # Approx type M3
        # ******************
        elif(approx=='M3'):
            
            # Get approximation boundary and generate masks
            approx_boundary = m-2*i

            # Saturate at 0 and N_bits
            if (approx_boundary<0):
                approx_boundary = 0
            elif (approx_boundary>(N_bits+1)):
                approx_boundary = N_bits+1
            
            approx_mask = (2**approx_boundary)-1
            exact_mask = mask_Nb ^ approx_mask
                    
            # Approx partial products version => OR all bits in approx region and set others to zero
            pproducts_aprox[:,i] = (((b_masked & zeromask) & approx_mask)>0) << ((approx_boundary-1)*(approx_boundary>0))
            
            # Combine approximate and exact parts
            pproducts_final[:,i] = (pproducts_aprox[:,i] & approx_mask) | (pproducts[:,i] & exact_mask)
            
            # Sign correction (only in fully approx)
            if (approx_boundary == 0):
                pproducts_final[:,i] = pproducts_final[:,i] + neg[:,i].astype(np.int)
                
        # SIGN EXTENSION BEFORE ADDITION
        first_one = np.floor(np.log2(pproducts_final[:,i] + (pproducts_final[:,i]==0)))     # ==0 is contingency to avoid log(0)
        
        # If negative, we need to pad 1s until we reach int32 size
        if (first_one==N_bits):
            pproducts_final[:,i] = pproducts_final[:,i] | neg_padding
        
        # Final sum
        final_sum += (pproducts_final[:,i].astype(np.int32)) << (2*i)

    return final_sum
