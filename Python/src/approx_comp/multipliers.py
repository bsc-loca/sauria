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

import src.approx_comp.abm as abm
import src.approx_comp.bam as bam
import src.approx_comp.lm as lm 
import src.approx_comp.udm as udm

sys.path.insert(1, './../')

def generic_multiplier(a, b, MulType=0, N_bits=16, m=0, signed=True):

    # MULTIPLIER TYPES:
    # 0 => Exact
    # 1 => UDM
    # 2 => ABM-M1
    # 3 => ABM-M2
    # 4 => ALM
    # 5 => BAM
    
    # Just in case, typecast the inputs as integers!
    a = int(a)
    b = int(b)
    
    if MulType==0:
        return a*b
    elif MulType==1:
        return udm.udm_multiplier(a, b, N_bits=N_bits, signed=signed, approx=m)
    elif MulType==2:
        return abm.booth_multiplier(a, b, N_bits=N_bits, m=m, approx='M1')
    elif MulType==3:
        return abm.booth_multiplier(a, b, N_bits=N_bits, m=m, approx='M3')
    elif MulType==4:
        approx = 'log' if m==0 else 'log-SOA'
        return lm.logarithm_multiplier(a, b, N_bits=N_bits, signed=signed, m=m, approx=approx)
    elif MulType==5:
        return bam.array_multiplier(a, b, N_bits=N_bits, signed=signed, hbl=m[0], vbl=m[1])
    else:
        assert 0, "Unrecognized Multiplier! :("
        return
