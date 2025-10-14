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

# --------------------------------------------
# FP <-> Integer conversion functions
# --------------------------------------------

def convert_to_intN(i_array, N):

    o_array = np.zeros(i_array.shape, dtype=np.uint64)    

    for i, val in enumerate(i_array):
        o_array[i] = int(np.binary_repr(val, width=N), 2)
    
    return o_array

def encode_FP(val, MANT_BITS, E_BITS, e_bias, expanded=False):
    
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

def encode_array_to_FP(i_array, MANT_BITS, TOTAL_BITS, expanded=False):
      
    E_BITS = TOTAL_BITS - MANT_BITS - 1
    e_bias = 2**(E_BITS-1) - 1
    
    if expanded:
        o_array = np.zeros(i_array.shape+(3,), dtype=np.uint64)    
    else:
        o_array = np.zeros(i_array.shape, dtype=np.uint64)    

    for i, val in enumerate(i_array):
        o_array[i] = encode_FP(val, MANT_BITS, E_BITS, e_bias, expanded=expanded)
        
    return o_array

def decode_FP(val, MANT_BITS, E_BITS):
    
    TOTAL_BITS = MANT_BITS + E_BITS + 1
    
    bias = (2**(E_BITS-1))-1
    
    sign = (int(val)>>(TOTAL_BITS-1))
    exp = ((int(val)>>MANT_BITS) & (2**E_BITS-1)) - bias
    mant = val & (2**MANT_BITS-1)
        
    real = ((-1)**sign) * (2**exp) * (1+(mant/(2**MANT_BITS)))
    
    #print(sign, exp, mant)
    
    return real

def decode_FP_array(i_array, MANT_BITS, E_BITS):
    
    o_array = np.zeros(i_array.shape)  
    
    for i, val in enumerate(i_array):
        o_array[i] = decode_FP(val, MANT_BITS, E_BITS)

    return o_array

# --------------------------------------------
# Generate random tensor with zome sparsity
# --------------------------------------------

def gen_random_tensor(shape, pzero, bit_width, FP=False, distribution='unif', gauss_scale=1, ones_test=False):

    # Uniform distribution
    if (distribution=='unif'):
        start_values = (np.random.random(shape) - 0.5)
        
    # Gaussian distribution
    elif (distribution=='gauss'):
        start_values = np.random.normal(scale=gauss_scale, size=shape)
        
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
    if ones_test:
        tensor[:] = 1

    return tensor

# --------------------------------------------------------------
# Generate the three random tensors for a convolution (A,B,C)
# --------------------------------------------------------------

def generate_tensors(CONV, HYPER, pzero=[0,0,0], insert_deadbeef=True, gauss_scale=1, ones_test=False):
    
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
    A_tensor = gen_random_tensor([A_c,A_h,A_w], pzero[0], HYPER['IA_W'], HYPER['OP_TYPE'], distribution, gauss_scale=gauss_scale, ones_test=ones_test)
            
    # Weights tensor
    B_tensor = gen_random_tensor([C_c,A_c,B_h,B_w], pzero[1], HYPER['IB_W'], HYPER['OP_TYPE'], distribution, gauss_scale=gauss_scale, ones_test=ones_test)
    
    # Partial sums tensor
    C_tensor = gen_random_tensor([C_c,C_h,C_w], pzero[2], HYPER['OC_W'], HYPER['OP_TYPE'], distribution, gauss_scale=gauss_scale, ones_test=ones_test)
            
    # FOR EASY DEBUGGING, PUT SOME RECOGNIZABLE VALUES
    if insert_deadbeef:
        if (HYPER['OP_TYPE']==1):
                
            MANT_W = HYPER['IC_MANT']
            EXP_W = HYPER['OC_W'] - HYPER['IC_MANT'] - 1
            
            B_tensor[:,0,0,0] =         decode_FP(0xbeef, MANT_W, EXP_W)
            B_tensor[:,-1,-1,-1] =      decode_FP(0xbeef, MANT_W, EXP_W)
            
            C_tensor[0,:,0] =                                   decode_FP(0xbeef, MANT_W, EXP_W)
            C_tensor[CONV['X_used']-1,:,:] =                    decode_FP(0xdead, MANT_W, EXP_W)
            C_tensor[0,:,CONV['Y_used']-1] =                    decode_FP(0xbebe, MANT_W, EXP_W)
            C_tensor[CONV['X_used']-1,:,CONV['Y_used']-1] =     decode_FP(0xfe0, MANT_W, EXP_W)
            C_tensor[-1,:,-1] =                                 decode_FP(0xfe0, MANT_W, EXP_W)            

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

# -------------------------------------------------------------
# Flatten & encode A,B,C,C_out tensors
# -------------------------------------------------------------

def flatten_tensors(A_tensor, B_tensor, C_tensor, C_output, CONV, HYPER):
    
    # Normal convolution
    A_tensor_flat = A_tensor.flatten()
    C_tensor_flat = C_tensor.flatten()
    C_output_flat = C_output.flatten()
    
    # Weights tensor has the output channel dimension contiguous!
    B_tensor_flat = np.moveaxis(B_tensor, 0, -1).flatten()
                
    # If FP mode, encode values
    if (HYPER['OP_TYPE']==1):
        A_tensor_flat = encode_array_to_FP(A_tensor_flat, HYPER['IA_MANT'], HYPER['IA_W'])
        B_tensor_flat = encode_array_to_FP(B_tensor_flat, HYPER['IB_MANT'], HYPER['IB_W'])
        C_tensor_flat = encode_array_to_FP(C_tensor_flat, HYPER['IC_MANT'], HYPER['OC_W'])
        C_output_flat = encode_array_to_FP(C_output_flat, HYPER['IC_MANT'], HYPER['OC_W'])
        
    return A_tensor_flat, B_tensor_flat, C_tensor_flat, C_output_flat

# ------------------------------------------------------
# Pack array values of any bitwidth as contiguous bytes
# ------------------------------------------------------

def pack_as_bytes(MEM, data_array, start_bit_index, bit_width):

    # Initialize bit index
    bit_idx = start_bit_index

    for el in data_array.astype(int):
        
        start_bit = bit_idx
        end_bit = bit_idx + bit_width - 1

        start_byte = int(np.floor(start_bit/8))
        end_byte = int(np.floor(end_bit/8))

        written_bits = 0
        remaining_bits = bit_width
        for b_pos in range(start_byte, end_byte+1):

            mem_offs = bit_idx % 8
            curr_bits = min(min(bit_width, 8 - mem_offs), remaining_bits)
            elm_offs = written_bits

            MEM[b_pos] = MEM[b_pos] | (((el >> elm_offs) << mem_offs) & 0xFF)

            bit_idx += curr_bits
            written_bits += curr_bits
            remaining_bits -= curr_bits

    return bit_idx

# ------------------------------------------------------
# Writes the tensors into a DRAM memory region
# ------------------------------------------------------

def assign_dram_values(A_tensor, B_tensor, C_tensor, C_output, dram_offset, CONV, HYPER):
    
    # Get flat & encoded tensors
    A_tensor_flat, B_tensor_flat, C_tensor_flat, C_output_flat = flatten_tensors(A_tensor, B_tensor, C_tensor, C_output, CONV, HYPER)

    A_bit_width = HYPER['IA_W']
    B_bit_width = HYPER['IB_W']
    C_bit_width = HYPER['OC_W']

    # Initialize bit index
    bit_idx = 8*dram_offset

    # Initialize DRAM regions
    A_tensor_size = int(A_tensor.size * np.ceil(A_bit_width/8))
    B_tensor_size = int(B_tensor.size * np.ceil(B_bit_width/8))
    C_tensor_size = int(C_tensor.size * np.ceil(C_bit_width/8))

    DRAM_mem = np.zeros((A_tensor_size+B_tensor_size+C_tensor_size), dtype=np.uint8)
    DRAM_mem_gold = np.zeros((A_tensor_size+B_tensor_size+C_tensor_size), dtype=np.uint8)                                 

    # Write inputs
    A_tensor_offset = int(np.floor(bit_idx/8))
    _ =         pack_as_bytes(DRAM_mem,         A_tensor_flat, bit_idx, A_bit_width)
    bit_idx =   pack_as_bytes(DRAM_mem_gold,    A_tensor_flat, bit_idx, A_bit_width)    # Gold has a copy of the inputs

    # Force new region to start on a NEW BYTE
    bit_idx = 8*int(np.ceil(bit_idx/8))

    # Write weights
    B_tensor_offset = int(np.floor(bit_idx/8)) 
    _ =         pack_as_bytes(DRAM_mem,         B_tensor_flat, bit_idx, B_bit_width)
    bit_idx =   pack_as_bytes(DRAM_mem_gold,    B_tensor_flat, bit_idx, B_bit_width)    # Gold has a copy of the weights

    # Force new region to start on a NEW BYTE
    bit_idx = 8*int(np.ceil(bit_idx/8))

    # Write preloads and results
    C_tensor_offset = int(np.floor(bit_idx/8)) 
    _ =         pack_as_bytes(DRAM_mem,         C_tensor_flat, bit_idx, C_bit_width)    # PRELOADS
    bit_idx =   pack_as_bytes(DRAM_mem_gold,    C_output_flat, bit_idx, C_bit_width)    # RESULTS

    # Total number of bytes
    region_len = int(np.ceil(bit_idx/8)) - dram_offset

    return DRAM_mem, DRAM_mem_gold, [A_tensor_offset, B_tensor_offset, C_tensor_offset, region_len]
