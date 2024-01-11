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
import scipy.stats as stats

# ################################################################
# UTILITY FUNCTIONS
# ################################################################

def convert_to_intN(i_array, N):

    o_array = np.zeros(i_array.shape, dtype=np.uint64)    

    for i, val in enumerate(i_array):
        o_array[i] = int(np.binary_repr(val, width=N), 2)
    
    return o_array

def val_to_FP(val, MANT_BITS, E_BITS, e_bias, expanded=False):
    
    # Sign is easy
    s = int(val<0)
    
    # Zero is its own special case
    if (val == 0):
        packed_result = 0
        m = 0
        s = 0
        e = 0
        
    else:
        
        # Find exponent
        e = int(np.floor(np.log2(abs(val))))
        
        div = abs(val) / (2**e)

        # Apply bias to exponent
        e = int(e + e_bias)
        
        # Negative exponent means small number overflow => Saturate to zero
        if (e<0):
            e = 0
            s = 0
            m = 0
        
        # Exponent too large means large number overflow => Saturate to max value
        elif(e>((2**E_BITS)-2)):
            e = (2**E_BITS)-2
            m = (2**MANT_BITS)-1
            
        # Otherwise proceed normally
        else:
            
            # Loop to find mantissa
            approx = (div-1)
            bit_str = '0b'
            
            for j in range(MANT_BITS):
                
                approx = approx*2
                
                if approx<1:
                    bit_str = bit_str + '0'
                else:
                    approx = approx-1
                    bit_str = bit_str + '1'
                    
            # Extra bit for rounding
            round_bit = ((approx*2)>=1)
            
            m = int(bit_str, 2)
            
            # Round to nearest
            m+=round_bit
            
            # If rounding created a mantissa overflow, increment exponent
            if (m>=2**MANT_BITS):
                e += 1
                m -= 2**MANT_BITS
                
        packed_result = (s<<(MANT_BITS+E_BITS)) + (e<<MANT_BITS) + m

    if (expanded):
        return np.array([s, e, m])
    
    else:
        return packed_result

def convert_to_FP(i_array, MANT_BITS, TOTAL_BITS, expanded=False):
      
    E_BITS = TOTAL_BITS - MANT_BITS - 1
    e_bias = 2**(E_BITS-1) - 1
    
    if expanded:
        o_array = np.zeros(i_array.shape+(3,), dtype=np.uint64)    
    else:
        o_array = np.zeros(i_array.shape, dtype=np.uint64)    

    for i, val in enumerate(i_array):
        o_array[i] = val_to_FP(val, MANT_BITS, E_BITS, e_bias, expanded=expanded)
        
    return o_array

def FP_to_val(val, MANT_BITS, E_BITS):
    
    TOTAL_BITS = MANT_BITS + E_BITS + 1
    
    bias = (2**(E_BITS-1))-1
    
    sign = (int(val)>>(TOTAL_BITS-1))
    exp = ((int(val)>>MANT_BITS) & (2**E_BITS-1)) - bias
    mant = val & (2**MANT_BITS-1)
        
    real = ((-1)**sign) * (2**exp) * (1+(mant/(2**MANT_BITS)))
    
    #print(sign, exp, mant)
    
    return real

def convert_to_val(i_array, MANT_BITS, E_BITS):
    
    o_array = np.zeros(i_array.shape)  
    
    for i, val in enumerate(i_array):
        o_array[i] = FP_to_val(val, MANT_BITS, E_BITS)

    return o_array

# ################################################################
# DATA PACKING FUNCTIONS
# ################################################################

def ACT_pack_data_words(elm_array, IA_W, SRAMA_N, SRAMA_PART):
    
    IA_MASK = ((2**IA_W) - 1)

    out_words = np.zeros((SRAMA_PART), dtype=np.uint64)
    
    elm_array_ext = np.zeros((SRAMA_N), dtype=np.int64)
    elm_array_ext[:elm_array.size] = elm_array
    
    s = 0
    p = SRAMA_PART-1
    
    for i in range(elm_array_ext.size):
        
        el = elm_array_ext[i]
        
        # Word overflow
        if (s>=64):
            s = s-64
            p -= 1
                    
        #Split in 2 words if needed
        if (s+IA_W)>64:
            out_words[p] += ((el & IA_MASK) << s).astype(np.uint64)
            out_words[p-1] += ((el & IA_MASK) >> (64-s)).astype(np.uint64)
        else:
            out_words[p] += ((el & IA_MASK) << s).astype(np.uint64)
            
        s += IA_W
                            
    return out_words

def WEI_pack_data_words(elm_array, IB_W, SRAMB_N, SRAMB_PART):

    IB_MASK = ((2**IB_W) - 1)

    out_words = np.zeros((SRAMB_PART), dtype=np.uint64)
    
    elm_array_ext = np.zeros((SRAMB_N), dtype=np.int64)
    elm_array_ext[:elm_array.size] = elm_array
    
    s = 0
    p = SRAMB_PART-1
    
    for i in range(elm_array_ext.size):
        
        el = elm_array_ext[i]
        
        # Word overflow
        if (s>=64):
            s = s-64
            p -= 1
                    
        #Split in 2 words if needed
        if (s+IB_W)>64:
            out_words[p] += ((el & IB_MASK) << s).astype(np.uint64)
            out_words[p-1] += ((el & IB_MASK) >> (64-s)).astype(np.uint64)
        else:
            out_words[p] += ((el & IB_MASK) << s).astype(np.uint64)
            
        s += IB_W
        
    return out_words

def OUT_pack_data_words(elm_array, OC_W, SRAMC_N, SRAMC_PART):

    OC_MASK = ((2**OC_W) - 1)
    
    out_words = np.zeros((SRAMC_PART), dtype=np.uint64)
    
    elm_array_ext = np.zeros((SRAMC_N), dtype=np.int64)
    elm_array_ext[:elm_array.size] = elm_array
    
    s = 0
    p = SRAMC_PART-1
    
    for i in range(elm_array_ext.size):
        
        el = elm_array_ext[i]
        
        # Word overflow
        if (s>=64):
            s = s-64
            p -= 1
                    
        #Split in 2 words if needed
        if (s+OC_W)>64:
            out_words[p] += ((el & OC_MASK) << s).astype(np.uint64)
            out_words[p-1] += ((el & OC_MASK) >> (64-s)).astype(np.uint64)
        else:
            out_words[p] += ((el & OC_MASK) << s).astype(np.uint64)
            
        s += OC_W
                
    return out_words