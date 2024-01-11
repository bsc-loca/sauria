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

from model.approx.multipliers import generic_multiplier
from model.approx.adders import generic_adder

from helpers import drac_sa_top_helper as dsth


def FP_Madd(a, b, c, MANT_bits=10, N_bits=16, MulType=0, m=16, AdderType=0, A=0, rounding='RNE'):
    
    # Initialization
    # ***************************************
    
    E_bits = N_bits-1-MANT_bits
    e_bias = 2**(E_bits-1) - 1
    
    PRECISION_bits = MANT_bits + 1
        
    # Conversion (one-by-one, unfortunately)
    # ***************************************
    
    [s_a, e_a, m_a] = dsth.val_to_FP(a, MANT_bits, E_bits, e_bias, expanded=True)
    [s_b, e_b, m_b] = dsth.val_to_FP(b, MANT_bits, E_bits, e_bias, expanded=True)
    [s_c, e_c, m_c] = dsth.val_to_FP(c, MANT_bits, E_bits, e_bias, expanded=True)
    
    # a_p = 0xb326
    # b_p = 0x3800
    # c_p = 0x3941
    
    # s_a = a_p>>15
    # s_b = b_p>>15
    # s_c = c_p>>15
    
    # e_a = (a_p>>10) & 0x1f
    # e_b = (b_p>>10) & 0x1f
    # e_c = (c_p>>10) & 0x1f
    
    # m_a = (a_p) & 0x3ff
    # m_b = (b_p) & 0x3ff
    # m_c = (c_p) & 0x3ff
    
    # Add implicit one
    m_a = m_a | (1<<(MANT_bits))
    m_b = m_b | (1<<(MANT_bits))
    m_c = m_c | (1<<(MANT_bits))
    
    # Product
    # ********
    
    s_prod = s_a ^ s_b
    e_prod = e_a + e_b - e_bias
    
    # If any multiplicand is zero, set exponent to minimum
    if (a==0) or (b==0):
        e_prod = 2 - e_bias
    
    # ********************************************************************************
    # GENERIC MULTIPLIER => Depending on MULTYPE we do one realization or the other
    # ********************************************************************************
    
    mul_bits = MANT_bits+2 if ((MulType==2) or (MulType==3)) else MANT_bits+1       # Booth multipliers need one extra bit for unsignedness....
    
    m_prod = generic_multiplier(m_a, m_b, MulType=MulType, N_bits=mul_bits, m=m, signed=False)
    
    # # Exact multiplier
    # if approx=='':
    #     m_prod = m_a*m_b
        
    # # Logarithmic multiplier
    # elif approx[0:3]=='log':
    #     m_prod = lm.logarithm_multiplier(m_a, m_b, MANT_bits+1, m=m, approx=approx, signed=False)
    
    # # Broken Array multiplier
    # elif approx=='BAM':
    #     m_prod = bam.array_multiplier(m_a, m_b, MANT_bits+1, hbl=m[0], vbl=m[1], approx='', signed=False)
    
    # # UnderDesigned multiplier (UDM)
    # elif approx=='UDM':
    #     m_prod = udm.udm_multiplier(m_a, m_b, MANT_bits+1, approx=m, signed=False)
        
    # # Approximate Booth Multiplier (ABM)
    # else:
    #     m_prod = abm.booth_multiplier(m_a, m_b, N_bits=MANT_bits+2, m=m, approx=approx)[0]
    
    m_prod_shft = m_prod << 2
    
    # Sum
    # ********
    
    effective_subs = s_a ^ s_b ^ s_c
    
    e_diff = e_c - e_prod
    e_tent = max(e_c, e_prod)
    
    # Prod-anchored case => Addend is very small
    if (e_diff <= (-2 * PRECISION_bits - 1)):
        addend_shamt = 3*PRECISION_bits + 4
        
    # Addend and product will have bits to add
    elif (e_diff <= (PRECISION_bits + 2)):
        addend_shamt = PRECISION_bits + 3 - e_diff
    
    # Addend-anchored case => Product is very small
    else:
        addend_shamt = 0
    
    m_add_vector = (m_c << (3*PRECISION_bits + 4)) >> addend_shamt
    
    m_add_shft = m_add_vector>>PRECISION_bits
    m_add_sticky = m_add_vector & (2**PRECISION_bits-1)
    
    sticky_b4_add = m_add_sticky>0
    
    addend = m_add_shft if (effective_subs==0) else (2**(3*PRECISION_bits+4)-1)^m_add_shft     # Inversion when negative
    cin = (effective_subs==1) and (not(sticky_b4_add))
    
    # +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    # GENERIC ADDER => Depending on ADDERTYPE we do one realization or the other
    # +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    m_sum_raw = generic_adder(m_prod_shft, addend, cin, AdderType=AdderType, N_bits=3*PRECISION_bits+4, A=A, signed=False, remove_carry=False)
    #m_sum_raw = m_prod_shft + addend + cin
    
    #print("Adder: {}+{}={} ({})".format(m_prod_shft, addend, m_sum_raw, m_prod_shft+addend))
    #print("Adder (b): \n{}\n+\n{}\n=\n{}\n({})".format(bin(m_prod_shft), bin(addend), bin(m_sum_raw), bin(m_prod_shft+addend)))
    
    sum_carry = (m_sum_raw >> 3*PRECISION_bits+4)&0x1
    
    # Complement negative sum
    m_sum = ((2**(3*PRECISION_bits+5)-1)^m_sum_raw)+1 if (effective_subs and (sum_carry==0)) else m_sum_raw
    
    # Discard carry as sum won't overflow
    m_sum = m_sum & (2**(3*PRECISION_bits+4)-1)
    
    # Sign flip in case of misprediction
    if (effective_subs):
        if (sum_carry == s_prod):
            final_sign = 1
        else:
            final_sign = 0
    else:
        final_sign = s_prod
    
    # Lower sum
    m_sum_lower = m_sum & (2**(2*PRECISION_bits+3)-1)

    # Normalization
    # **************
    
    # Leading zero counter
    lzc = 0
    for b in range(2*PRECISION_bits+3):
        
        all_shft = m_sum_lower >> b
        nonzero = all_shft>0
        
        #frst_one_pos[nonzero] = b
        if nonzero:
            lzc = 0
        else:
            lzc += 1
            
    # Prod-anchored case or cancellations
    if (e_diff <= 0) or (effective_subs and (e_diff<=2)):
        
        # # Assume result is always normal
        # norm_shamt = PRECISION_bits + 2 + lzc
        # norm_exp = e_prod - lzc + 1
        
        # Normal result
        if (e_prod - lzc + 1 >= 0) and not (lzc==2*PRECISION_bits+3):
                
            # Assume result is always normal
            norm_shamt = PRECISION_bits + 2 + lzc
            norm_exp = e_prod - lzc + 1
            
        # Subnormal result (or zero)
        else:
            norm_shamt = PRECISION_bits + 2 + e_prod
            norm_exp = 0
        
    # Addend-anchored case
    else:
        norm_shamt = addend_shamt        
        norm_exp = e_tent
    
    sum_shifted = m_sum << norm_shamt
    
    # sum_sticky_bits = sum_shifted & (2**(2*PRECISION_bits+3)-1)
    # sticky_after_norm = (sum_sticky_bits>0) or sticky_b4_add
    
    msb0 = (sum_shifted >> 3*PRECISION_bits+4) & 0x1
    msb1 = (sum_shifted >> 3*PRECISION_bits+3) & 0x1
    
    # Align right
    if (msb0==1):
        final_mant = sum_shifted >> 1
        final_exp = norm_exp + 1
        
    # Do nothing
    elif (msb1==1):
        final_mant = sum_shifted
        final_exp = norm_exp
        
    # Align left
    elif (norm_exp>1):
        final_mant = sum_shifted << 1
        final_exp = norm_exp - 1
        
    # Denormal
    else:
        final_mant = sum_shifted
        final_exp = 0
    
    sum_sticky_bits = final_mant & (2**(2*PRECISION_bits+3)-1)
    sticky_after_norm = (sum_sticky_bits>0) or sticky_b4_add
    
    final_mant = final_mant >> (2*PRECISION_bits+3)
    
    # Rounding
    # *************************
    
    lsb_mant = final_mant & 0x1
    
    # ROUND TO NEAREST
    if rounding == 'RNE':
    
        if lsb_mant>0:
            if sticky_after_norm:
                round_bit = 1
            else:
                round_bit = (final_mant>>1) & 0x1
        else:
            round_bit = 0
    
    # ROUND TO ZERO
    elif rounding == 'RTZ':
        round_bit = 0
    
    # ROUND UP
    elif rounding == 'RUP':
        if (lsb_mant>0 and sticky_after_norm):
            round_bit = final_sign^0x1
        else:
            round_bit = 0
            
    # ROUND DOWN
    else:
        if (lsb_mant>0 and sticky_after_norm):
            round_bit = final_sign
        else:
            round_bit = 0
        
    final_mant = ((final_mant>>1) & (2**(MANT_bits)-1)) + round_bit
    
    # If rounding created a mantissa overflow, increment exponent
    if (final_mant>=2**MANT_bits):
        final_exp += 1
        final_mant -= 2**MANT_bits
    
    final_result_packed = (final_sign<<(N_bits-1)) + (final_exp<<MANT_bits) + final_mant
    
    return final_result_packed, [final_sign, final_exp, final_mant], dsth.FP_to_val(final_result_packed, MANT_bits, E_bits)