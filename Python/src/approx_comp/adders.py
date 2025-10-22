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

def generic_adder(a, b, cin, AdderType=0, N_bits=16, A=0, remove_carry=True, signed=True):

    # ADDER TYPES:
    # 0 => Exact
    # 1 => GeAr
    # 2 => GeAr-plus
    # 3 => TruA
    # 4 => TruA-H
    # 5 => LOA
    
    # Just in case, typecast the inputs as integers!
    a = int(a)
    b = int(b)
    
    # If an input is negative, convert to unsigned with a trick
    if signed and (a<0):
        a = (a + (1<<64)) & ((1<<N_bits)-1)
    
    if signed and (b<0):
        b = (b + (1<<64)) & ((1<<N_bits)-1)
                     
    if AdderType==0:
        addition = a+b+cin
        
    elif AdderType==1:
        addition = GeAr_adder(a, b, N_bits=N_bits, R=A[0], P=A[1])
        
    elif AdderType==2:
        addition = GeAr_plus_adder(a, b, N_bits=N_bits, R=A[0], P=A[1])
        
    elif AdderType==3:
        addition = TruA(a, b, N_bits=N_bits, A=A)
        
    elif AdderType==4:
        addition = TruA_H(a, b, N_bits=N_bits, A=A)
        
    elif AdderType==5:
        addition = LOA(a, b, N_bits=N_bits, A=A)
        
    else:
        assert 0, "Unrecognized Adder! :("
        return
    
    # Discard carry & limit to Nbits
    if remove_carry: addition = addition & ((1<<N_bits)-1)
    
    # Convert the result back to signed integer
    if signed and ((addition & ((1<<N_bits)-1))>(1<<(N_bits-1))):
            
        addition = addition-(1<<N_bits)
    
    return addition

def GeAr_adder(a, b, N_bits=16, R=4, P=4, silent=True):
      
    L = R+P
    
    prospect_k = ((N_bits-L)/R)+1
    k = int(np.ceil(prospect_k))
    effective_N = L + (k-1)*R 
     
    #print(k)
    
    final_sum = 0
    
    for i in range(k):
        
        # Get current part of operands
        a_part = (a >> (i*R)) & ((1<<L)-1)
        b_part = (b >> (i*R)) & ((1<<L)-1)
        
        if not silent:  print("\ni=",i)
        
        if not silent:  print(a_part, b_part)
        if not silent:  print(bin(a_part), bin(b_part))
        
        # Perform subsum
        sub_sum = a_part + b_part
        
        # Carry for later
        carry = (sub_sum>>L)&0x1
        
        # Discard carry out
        sub_sum = sub_sum & ((1<<L)-1)
        
        if not silent:  print("Sub sum: ", bin(sub_sum))
        
        # Discard lower P bits (if not the first!)
        if i>0:
            sub_sum = sub_sum >> P
            bitloc = R*i + P
        else:
            bitloc = 0
            
        # Add to the final sum after relocating the bits
        final_sum = final_sum + (sub_sum << bitloc)
        
    if not silent:      print("Bitloc: ", bitloc)
    if not silent:      print("Sub sum (postshift): ", bin(sub_sum))
    if not silent:      print("Current final sum: ", bin(final_sum))

    # Add final carry
    final_sum = final_sum | (carry << (N_bits))

    if not silent:  print("\nFINAL RESULT (+carry): ")
    if not silent:  print("a = ", bin(a))
    if not silent:  print("b = ", bin(b))
    if not silent:  print("+")
    if not silent:  print("=>  ", bin(final_sum))
    if not silent:  print("=> (", bin(a+b),")")

    return final_sum

def GeAr_plus_adder(a, b, N_bits=16, R=4, P=4, silent=True):
          
    L = R+P
    L_mask = ((1<<L)-1)
    
    prospect_k = ((N_bits-L)/R)+1
    k = int(np.ceil(prospect_k))
    effective_N = L + (k-1)*R
             
    ext_bits = ((1<<effective_N)-1) - ((1<<N_bits)-1)
    neg_thres = (1<<(N_bits-1))
    
    if not silent: print(N_bits,effective_N)
    if not silent: print(bin(b))
    if not silent: print(bin(ext_bits))
    
    # EXTEND SIGN BITS WHEN NEGATIVE
    if (a>=neg_thres): a = a | ext_bits
    if (b>=neg_thres): b = b | ext_bits    
        
    final_sum = 0
    carries = 0
    
    for i in range(k):
        
        # Get current part of operands
        a_part = (a >> (i*R)) & ((1<<L)-1)
        b_part = (b >> (i*R)) & ((1<<L)-1)
        
        if not silent: print("\ni=",i)
        
        if not silent:  print(a_part, b_part)
        if not silent:  print(bin(a_part), bin(b_part))
        
        # Perform subsum
        sub_sum_raw = a_part + b_part
                
        # Discard carry out
        sub_sum = sub_sum_raw & L_mask
        
        # AND all bits to get ON
        ON = (sub_sum==L_mask)
        
        # Carry for next adders
        carry = (sub_sum_raw>>L)&0x1
        
        if not silent:  print("Sub sum: ", bin(sub_sum), bin(L_mask))
        if not silent:  print("Carry :", carry)
        
        # If first adder, starts at zero
        if i==0:
            bitloc = 0
            final_sub_sum = sub_sum
            
            # First carry is just carry
            carries = carry
            
        # If not first adder:
        else:
            # Replicate ON and Carries bits
            ON_mask = ON*L_mask
            C_mask_neg = (carries*L_mask)^L_mask
            
            # Corrected output
            sub_sum_corrected = (sub_sum & (ON_mask^L_mask)) | ((C_mask_neg) & ON_mask)
            
            if not silent:  print("ON: {}, Co: {}".format(ON, carries))
            if not silent:  print("Sub sum: ", bin(sub_sum))
            if not silent:  print("Correc.: ", bin(sub_sum_corrected))
            
            # Discard P bits
            final_sub_sum = sub_sum_corrected >> P
            bitloc = R*i + P
                        
            # Accumulate carry, but reset if ON
            carries = (carries & ON) | carry
            
        # Add to the final sum after relocating the bits
        final_sum = final_sum + (final_sub_sum << bitloc)
    
    if not silent:      print("Bitloc: ", bitloc)
    if not silent:      print("Sub sum (postshift): ", bin(sub_sum>>P))
    if not silent:      print("Sub sum (corrected): ", bin(final_sub_sum))
    if not silent:      print("Current final sum: ", bin(final_sum))
    
    # CROP EXTENDED SIGN BITS
    final_sum = final_sum & ((1<<(N_bits))-1)
            
    # Add final carry
    final_sum = final_sum | (carries << (N_bits))
    
    if not silent:  print("\nFINAL RESULT (+carry): ")
    if not silent:  print("a = ", bin(a))
    if not silent:  print("b = ", bin(b))
    if not silent:  print("+")
    if not silent:  print("=>  ", bin(final_sum))
    if not silent:  print("=> (", bin(a+b),")")
    
    return final_sum

def TruA(a, b, N_bits=16, A=0):
    
    higher_mask = ((1<<N_bits)-1) - ((1<<A)-1)
    
    a_sum = a & higher_mask
    b_sum = b & higher_mask
    
    return (a_sum + b_sum)

def TruA_H(a, b, N_bits=16, A=0):
    
    higher_mask = ((1<<N_bits)-1) - ((1<<A)-1)
    lower_mask = ((1<<A)-1)
    
    a_sum = a & higher_mask
    b_sum = b & higher_mask
    
    return (a_sum + b_sum + lower_mask)

def LOA(a, b, N_bits=16, A=0):
    
    higher_mask = ((1<<N_bits)-1) - ((1<<A)-1)
    lower_mask = ((1<<A)-1)
    
    a_lower = a & lower_mask
    b_lower = b & lower_mask
    
    sum_lower = a_lower | b_lower
    carry_lower = (a_lower>>(A-1)) & (b_lower>>(A-1))
    
    a_higher = a & higher_mask
    b_higher = b & higher_mask
    
    sum_higher = a_higher + b_higher + (carry_lower<<A)
        
    sum_total = sum_higher | sum_lower
        
    return sum_total
    
    
    