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
import torch
import sys
from model.approx.fp import FP_Madd

def custom_matmul(Mat_A, Mat_B, preloads=[], exact=True, MANT_bits=10, N_bits=16, mul_type=0, M=0, add_type=0, A=0, rounding='RNE'):
    
    A_shape = Mat_A.shape
    B_shape = Mat_B.shape
    
    assert len(A_shape)==3, "Matrices must have 3 dimensions [reps, y, x]"
    assert A_shape[2]==B_shape[1], "Matrix dimensions must fit for GeMM"
    assert A_shape[0]==B_shape[0], "Number of batches must be the same"
    
    # Initialize final matrix
    Mat_C = np.zeros((A_shape[0], A_shape[1], B_shape[2]))
    
    if (len(preloads)>0):
        Mat_C = preloads
    
    # For each output matrix dimension
    for k in range(A_shape[0]):
        for j in range(A_shape[1]):
            for i in range(B_shape[2]):

                
                # Reduction dimension
                for t in range(A_shape[2]):
                    
                    # MAC
                    if exact:
                        Mat_C[k, j, i] += Mat_A[k, j, t] * Mat_B[k, t, i]
                    else:
                        
                        # Zero gating => Quite important for efficiency!
                        if (Mat_A[k, j, t]!=0) and (Mat_B[k, t, i]!=0):
                            _, _, Mat_C[k, j, i] = FP_Madd(Mat_A[k, j, t], Mat_B[k, t, i], Mat_C[k, j, i], MANT_bits=MANT_bits, N_bits=N_bits, MulType=mul_type, m=M, AdderType=add_type, A=A, rounding=rounding)
    
    return Mat_C
