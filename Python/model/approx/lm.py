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

#%% Functions

# LEADING ONE DETECTOR (LEADING ZERO COUNTER)
def LOD(x, N_bits):

    if x==0:
        return 0
    else:

        lzc = 0
        for b in range(N_bits):
            
            all_shft = x >> b
            nonzero = all_shft>0
            
            #frst_one_pos[nonzero] = b
            if nonzero:
                lzc = 0
            else:
                lzc += 1
        
        return N_bits-lzc-1
    
def logarithm_multiplier(a, b, N_bits=16, m=0, approx='log', signed=True):
    
    if signed:
        out_sign = (a*b)<0
        a = np.abs(a)
        b = np.abs(b)
    
    # LOD results represent exponent
    k_a = LOD(a, N_bits)
    k_b = LOD(b, N_bits)
    
    # Mantissas are everything to the right of first one
    m_a = a & ((2**k_a)-1)
    m_b = b & ((2**k_b)-1)
    
    # ... and shifted to bring LO-1 to MSB
    x_a = m_a << (N_bits-k_a-1)
    x_b = m_b << (N_bits-k_b-1)
    
    # ENCODING : Concatenation of exponent and mantissa make the logarithm values
    f_a = (k_a << (N_bits-1)) + x_a
    f_b = (k_b << (N_bits-1)) + x_b
    
    # Logarithm result of product is just the sum of the logarithms
    if (approx=='log'):
        f_prod = f_a + f_b
    
    # ALM-SOA => lowest m bits set to one
    elif (approx=='log-SOA'):
        soa_mask = ((2**(N_bits-1+int(np.ceil(np.log2(N_bits)))))-1) - ((2**m)-1)
        
        f_a_soa = f_a & soa_mask
        f_b_soa = f_b & soa_mask
        
        carry = ((f_a & (1<<(m-1)))&(f_b & (1<<(m-1))))<<1
        
        f_prod = f_a_soa + f_b_soa + carry
        f_prod = f_prod | ((2**m)-1)
    
    # Exponent is the upper bits and tells us where the leading one will be
    k_prod = f_prod >> (N_bits-1)
    
    # Mantissa is the lower bits and contains the values after the leading one
    x_prod = f_prod & (2**(N_bits-1)-1)
    
    # DECODING : Final value is a leading 1, followed by the mantissa, followed by many 0s
    # until the leading 1 is at its proper position

    # If exponent is large enough, we left-shift
    if (k_prod>(N_bits-1)):
        prod_shamt = k_prod - (N_bits-1)
        product = x_prod<<prod_shamt     

    # If the exponent is small, we right shift
    else:
        prod_shamt = (N_bits-1)-k_prod
        product = x_prod>>prod_shamt     
    
    product = (1<<k_prod) + product

    if signed and out_sign:
        product = -1*product

    return product

# #%% Test

# np.random.seed(31)

# N = 10000
# golden_results = np.zeros((N))
# lm_results = np.zeros((N))

# N_bits = 16
# max_val = (2**(N_bits-1)) - 1

# approx = 'log'
# m = 10

# a = np.random.randint(1, max_val, size=N)
# b = np.random.randint(1, max_val, size=N)

# # Remove zeros on a,b (catastrophic and not really relevant)
# #b = b + (b==0)
# #a = a + (a==0)

# # Golden results are constant
# golden_results = a*b

# lm_results = np.zeros((N), dtype=np.int)

# for i in range(N):
    
#     if (i%100000==0):
#         print("Processing inputs... ", i)
    
#     lm_results[i] = logarithm_multiplier(a[i], b[i], N_bits=N_bits, m=m, approx=approx)

# err = np.abs(golden_results - lm_results)
# rel_err = err/(np.abs(golden_results) + (golden_results==0))

# print("\nMean relative error (MRED): ", np.mean(rel_err))
# print("Max relative error: ", np.max(rel_err))
# print("\nResults pair for max error: golden = ", golden_results[rel_err.argmax()], "approx = ", lm_results[rel_err.argmax()])
# print("Inputs causing max error: a = ", a[rel_err.argmax()], "b = ", b[rel_err.argmax()])

# #%% PLOT

# import matplotlib.pyplot as plt
# from matplotlib import cm

# cmap = cm.brg
# mk_size = 10
# alpha = 0.5

# fig, ax = plt.subplots()
# ax_new = fig.add_axes([0.55, 0.2, 0.3, 0.25]) # the position of zoom-out plot compare to the ratio of zoom-in plot 

# # Big plot
# ax.scatter(golden_results, lm_results, s=mk_size, alpha=alpha, color='r', label="MRED={:.1e}".format(np.mean(rel_err)))

# # Create zoom-out plot
# ax_new.scatter(golden_results, lm_results, s=mk_size, alpha=alpha, color='r')

# ax.plot([golden_results.min(),golden_results.max()], [golden_results.min(),golden_results.max()], color='black')
# ax_new.plot([golden_results.min(),golden_results.max()], [golden_results.min(),golden_results.max()], color='black')
# ax.legend(loc='upper left')
# ax_new.set_xlim([5.5e8, 6.5e8])
# ax_new.set_ylim([5e8, 6e8])

# ax.set_xlabel('Exact value')
# ax.set_ylabel('Approx value')

# plt.suptitle("Logarithm Multplier")


# plt.figure()
# plt.hist(rel_err, bins=1000, density=True)
# plt.xlabel('Relative Error Distance')
# plt.ylabel('Probability Density')
# plt.suptitle("Relative errors distribution")
