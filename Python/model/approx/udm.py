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

def mul_2x2(a,b,approx_type=0):
    
    and00 = (a&0x1) & (b&0x1)
    and01 = (a&0x1) & ((b>>1)&0x1)
    and10 = ((a>>1)&0x1) & (b&0x1)
    and11 = ((a>>1)&0x1) & ((b>>1)&0x1)
    
    # Exact
    if approx_type==0:
        andX = and01 & and10
        prod = and00 + ((and01 ^ and10)<<1) + ((and11 ^ andX)<<2) + ((and11 & andX)<<3)
        
    # UDM model
    else:
        prod = and00 + ((and01 | and10)<<1) + (and11<<2)
        
    return prod

def mul_NxN(a,b,N,approx_type=0):

    N_lower = int(N/2)
    
    # Inputs decomposition
    mask = ((1<<N_lower)-1)
    
    AL = a & mask
    BL = b & mask
    AH = (a >> N_lower) & mask
    BH = (b >> N_lower) & mask
    
    # Instantiation of lower level
    if N_lower==2:
        result_LxL = mul_2x2(AL, BL, approx_type>0)
        result_LxH = mul_2x2(AL, BH, approx_type>0)
        result_HxL = mul_2x2(AH, BL, approx_type>0)
        result_HxH = mul_2x2(AH, BH, approx_type>1)
        
    else:
        result_LxL = mul_NxN(AL, BL, N_lower, approx_type)
        result_LxH = mul_NxN(AL, BH, N_lower, approx_type)
        result_HxL = mul_NxN(AH, BL, N_lower, approx_type)
        result_HxH = mul_NxN(AH, BH, N_lower, 2*(approx_type==2))
        
    # Partial sums
    psum1 = (result_LxH & mask) + (result_HxL & mask) + (result_LxL>>N_lower)
    psum2 = (result_HxH & mask) + (result_LxH>>N_lower) + (result_HxL>>N_lower) + (psum1>>N_lower)
    psum3 = (result_HxH>>N_lower) + (psum2>>N_lower)
    
    # Final result
    prod = (result_LxL & mask) + ((psum1 & mask)<<N_lower) + ((psum2 & mask)<<(2*N_lower)) + ((psum3 & mask)<<(3*N_lower))

    return prod

def udm_multiplier(a, b, N_bits=16, approx='', signed=True):
    
    N_bits_wallace = 1<<(int(np.ceil(np.log2(N_bits))))
    
    if signed:
        out_sign = (a*b)<0
        a = np.abs(a)
        b = np.abs(b)
    
    # Types of approximate structure
    if approx=='partial':
        approx_type = 1
    elif approx=='inexact':
        approx_type = 2
    else:
        approx_type = 0
    
    # Tree recursive instantiation
    result = mul_NxN(a,b, N_bits_wallace, approx_type=approx_type)
        
    if signed and out_sign:
        result = -1*result
    
    return result
    