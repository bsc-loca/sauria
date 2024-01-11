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
import abm

sys.path.insert(1, './../')

#%%

np.random.seed(29)

N = 1000000
golden_results = np.zeros((N))
booth_results = np.zeros((N))

#m = 16
N_bits = 16
max_val = (2**(N_bits-2)) - 1

a = np.random.randint(-max_val,max_val, size=N)
b = np.random.randint(-max_val,max_val, size=N)

# Remove zeros on b (catastrophic and not really relevant)
b = b + (b==0)

# Golden results are constant
golden_results = a*b

# ------------------------
# APPROXIMATE RUNS: M1
# ------------------------

booth_M1_results_list = []
booth_M1_err_list = []
booth_M1_rel_err_list = []

approx = 'M1'
m_list = [0, 4, 8, 12, 16]

for m in m_list:
    
    booth_results = abm.booth_multiplier(a, b, N_bits=N_bits, m=m, approx=approx)
    
    err = np.abs(golden_results - booth_results)
    rel_err = err/(np.abs(golden_results) + (golden_results==0))
    
    booth_M1_results_list.append(booth_results)
    booth_M1_err_list.append(err)
    booth_M1_rel_err_list.append(rel_err)
    
    print("******************************")
    print("         RESULTS (M1)")
    print("         m = ", m)
    print("******************************")
    
    print("\nMean relative error (MRED): ", np.mean(rel_err))
    print("Max relative error: ", np.max(rel_err))
    print("\nResults pair for max error: golden = ", golden_results[rel_err.argmax()], "approx = ", booth_results[rel_err.argmax()])
    print("Inputs causing max error: a = ", a[rel_err.argmax()], "b = ", b[rel_err.argmax()])

# ------------------------
# APPROXIMATE RUNS: M3
# ------------------------

booth_M3_results_list = []
booth_M3_err_list = []
booth_M3_rel_err_list = []

approx = 'M3'
m_list = [0, 4, 8, 12, 16]

for m in m_list:
    
    booth_results = abm.booth_multiplier(a, b, N_bits=N_bits, m=m, approx=approx)
    
    err = np.abs(golden_results - booth_results)
    rel_err = err/(np.abs(golden_results) + (golden_results==0))
    
    booth_M3_results_list.append(booth_results)
    booth_M3_err_list.append(err)
    booth_M3_rel_err_list.append(rel_err)
    
    print("******************************")
    print("         RESULTS (M3)")
    print("         m = ", m)
    print("******************************")
    
    print("\nMean relative error (MRED): ", np.mean(rel_err))
    print("Max relative error: ", np.max(rel_err))
    print("\nResults pair for max error: golden = ", golden_results[rel_err.argmax()], "approx = ", booth_results[rel_err.argmax()])
    print("Inputs causing max error: a = ", a[rel_err.argmax()], "b = ", b[rel_err.argmax()])

#%%

import matplotlib.pyplot as plt
from matplotlib import cm

cmap = cm.brg
mk_size = 10
alpha = 0.5

# --------
# M1
# --------

fig, ax = plt.subplots()
ax_new = fig.add_axes([0.55, 0.2, 0.3, 0.25]) # the position of zoom-out plot compare to the ratio of zoom-in plot 

for i, m in enumerate(reversed(m_list)):

    # Big plot
    ax.scatter(golden_results, booth_M1_results_list[len(m_list)-i-1], s=mk_size, alpha=alpha, color=cmap(i/len(m_list)), label="m={}; MRED={:.1e}".format(m, np.mean(booth_M1_rel_err_list[len(m_list)-i-1])))

    # Create zoom-out plot
    ax_new.scatter(golden_results, booth_M1_results_list[len(m_list)-i-1], s=mk_size, alpha=alpha, color=cmap(i/len(m_list)))

ax.plot([golden_results.min(),golden_results.max()], [golden_results.min(),golden_results.max()], color='black')
ax_new.plot([golden_results.min(),golden_results.max()], [golden_results.min(),golden_results.max()], color='black')
ax.legend(loc='upper left')
ax_new.set_xlim([-2.5e4, 2.5e4])
ax_new.set_ylim([-2.5e4, 2.5e4])
ax.set_xlim([-1e6, 1e6])
ax.set_ylim([-1e6, 1e6])

ax.set_xlabel('Exact value')
ax.set_ylabel('Approx value')

plt.suptitle("M1-type Approximate Booth Multplier")

# --------
# M3
# --------

fig, ax = plt.subplots()
ax_new = fig.add_axes([0.55, 0.2, 0.3, 0.25]) # the position of zoom-out plot compare to the ratio of zoom-in plot 

for i, m in enumerate(reversed(m_list)):

    # Big plot
    ax.scatter(golden_results, booth_M3_results_list[len(m_list)-i-1], s=mk_size, alpha=alpha, color=cmap(i/len(m_list)), label="m={}; MRED={:.1e}".format(m, np.mean(booth_M3_rel_err_list[len(m_list)-i-1])))
    
    # Create zoom-out plot
    ax_new.scatter(golden_results, booth_M3_results_list[len(m_list)-i-1], s=mk_size, alpha=alpha, color=cmap(i/len(m_list)))

ax.plot([golden_results.min(),golden_results.max()], [golden_results.min(),golden_results.max()], color='black')
ax_new.plot([golden_results.min(),golden_results.max()], [golden_results.min(),golden_results.max()], color='black')
ax.legend(loc='upper left')
ax_new.set_xlim([-2.5e4, 2.5e4])
ax_new.set_ylim([-2.5e4, 2.5e4])
ax.set_xlim([-1e6, 1e6])
ax.set_ylim([-1e6, 1e6])

ax.set_xlabel('Exact value')
ax.set_ylabel('Approx value')

plt.suptitle("M3-type Approximate Booth Multplier")

# ----------------------
# RELATIVE ERRORS
# ----------------------

# Representatives: the values with max m
rel_err_m3 = booth_M3_rel_err_list[-1]
rel_err_m1 = booth_M1_rel_err_list[-1]

plt.figure()

plt.scatter(golden_results, rel_err_m3, s=mk_size, alpha=alpha, color='r', label="M3; m={}; MRED={:.1e}".format(m_list[-1], np.mean(rel_err_m3)))
plt.scatter(golden_results, rel_err_m1, s=mk_size, alpha=alpha, color='b', label="M1; m={}; MRED={:.1e}".format(m_list[-1], np.mean(rel_err_m1)))
plt.scatter(golden_results, golden_results-golden_results, s=mk_size, alpha=alpha, color='black', label="Int exact; MRED={:.1e}".format(np.mean(golden_results-golden_results)))

err_scale = 10*max(np.mean(rel_err_m3),np.mean(rel_err_m1))

plt.xlim([-1e7, 1e7])
plt.ylim([0, err_scale])
plt.legend(loc='upper left')
plt.xlabel('Exact value')
plt.ylabel('Relative Error Distance')
plt.suptitle("FP16 MAC results with Approximate Booth Multpliers - RED")

plt.figure()
plt.hist(rel_err_m3[rel_err_m3<np.percentile(rel_err_m3,95)], bins=1000, density=True)
plt.xlabel('Relative Error Distance')
plt.ylabel('Probability Density')
plt.suptitle("Relative errors distribution (M3)")

plt.figure()
plt.hist(rel_err_m1[rel_err_m1<np.percentile(rel_err_m1,95)], bins=1000, density=True)
plt.xlabel('Relative Error Distance')
plt.ylabel('Probability Density')
plt.suptitle("Relative errors distribution (M1)")