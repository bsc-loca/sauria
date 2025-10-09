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

def array_multiplier(a, b, N_bits=16, hbl=3, vbl=3, corr_loc=0, signed=True):
    
    if signed:
        out_sign = (a*b)<0
        a = np.abs(a)
        b = np.abs(b)
    
    a_bin = np.binary_repr(a, N_bits)
    a_bin = a_bin[::-1]     # Change endianness for convenience
    
    a_bits = np.zeros(N_bits, dtype=np.int)
    for i in range(N_bits):
        a_bits[i] = int("0b" + a_bin[i], 2)
    
    # Approximate version => Breaking the array multiplier
    a_bits[:hbl] = 0
    
    partial_sum = 0
        
    # Array of CSAs (for speed modelled as bitwise operations)
    for i in range(N_bits):
        
        v_boundary = vbl-i
        v_boundary = v_boundary * (v_boundary>0) # Only positive values
        
        # Mask to discard lower bits of b
        approx_mask = ((1<<N_bits)-1) - ((1<<v_boundary)-1)
        
        a_extended = a_bits[i] * ((1<<N_bits)-1)
        
        # Partial product is the AND of the relevant parts
        pprod  = a_extended & (b&approx_mask)
        
        # To correct for discarded bits we summarize discarded bits (in both directions?)
        if v_boundary>0:
            
            if i>((1-corr_loc)*vbl):
                discarded_v = (b&(1<<(v_boundary-1)))>0
                discarded_v = discarded_v << (v_boundary-1)
            else:
                discarded_v = 0
            
            # if (i%2==0):
            #     discarded_v = 0
            
        else:
            discarded_v = 0
                            
        # print("")
        
        REAL_PPROD = (a_extended & b)<<i    
        
        # print("v_boundary: ", v_boundary) 
        # print("allowed bits: ", bin(approx_mask)) 
        # print("REAL pprod\t", bin(REAL_PPROD))        
               
        # print("pprod\t\t", bin(pprod))
        
        # Add correction to pprod and shift
        pprod = (pprod | discarded_v)<<i
        
        # print("corr\t\t", bin(discarded_v))
        # print("corr pprod\t", bin(pprod))
        
        partial_sum += pprod
    
    if signed and out_sign:
        partial_sum = -1*partial_sum
    
    # print("Actual:", a*b)
    # print("Obtained:", partial_sum)
    # print("Diff: ", a*b-partial_sum)
    
    return partial_sum


