#!/usr/bin/python
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

# --------------------------------------
# IMPORTS
# --------------------------------------

import argparse
import numpy as np
import sys

sys.path.insert(1, './../')

import src.sauria_lib as slib
import src.test_helper as th
import src.hw_versions as hwv

# MAIN SCRIPT
# ----------------------------------------------------

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='SAURIA RTL verification tests')

    # Arguments
    parser.add_argument('--version', default='FP16_8x16', help='Hardware version used')
    parser.add_argument('--test_type', default='bmk_small', help='\
                                        Test type - One of the following options:\n \
                                        *******************************************\n \
                                        \t* conv_validation :     100 small convolutions to validate all shapes and modes\n \
                                        \t* bmk_small :           4 medium-sized convolutions with tiling\n \
                                        \t* bmk_torture :         40 large convolutions with tiling\n \
                                        \t* power_estimation :    1 small convolution with high PE utilization for power estimation\n \
                                        \t* debug_test :          testing different memory accesses\n')
    parser.add_argument('--n_random_tests', default=70, help='Number of randomly generated tests (applies only to --test_type conv_validation)')

    parser.add_argument('--print_statistics', action='store_true', help='Display performance statistics after every test (NOTE: these tests are meant to verify functionality, not to acheive high utilization)')
    parser.add_argument('--assert_no_errors', action='store_true', help='Stop and raise an error if any test fails')
    parser.add_argument('--ones_test', action='store_true', help='Set all tensor elements to 1')
    parser.add_argument('--insert_deadbeef', action='store_true', help='Insert regognizable values (0xDEAD, 0xBEEF, 0xBEBE, 0x0FE0) for easy debugging')
    parser.add_argument('--compute_macs', action='store_true', help='Generate compute cycle-accurate MAC results (SLOW)')

    parser.add_argument('--gauss_scale', default=1.0, help='Scale used for gaussian data')
    parser.add_argument('--pzero_A', default=0.0, help='Probability of 0s in Tensor A')
    parser.add_argument('--pzero_B', default=0.0, help='Probability of 0s in Tensor B')
    parser.add_argument('--pzero_C', default=0.0, help='Probability of 0s in Tensor C')

    parser.add_argument('--test_dir', default="../../test", help='Test directory where intermediate files will be stored.')

    # Parse arguments
    args = parser.parse_args()
    version = args.version

   # Parameters are decided by the version
    HW_PARAMS = hwv.get_params(version)

    # --------------------------------------
    # TEST SCRIPT OPTIONS
    # --------------------------------------

    silent = False

    # RANDOM SEED
    np.random.seed(117)

    TOPTS = {
        "test_type" :           args.test_type,
        "print_statistics" :    True if (args.print_statistics) else False,
        "assert_no_errors" :    True if (args.assert_no_errors) else False,
        "ones_test" :           True if (args.ones_test) else False,
        "insert_deadbeef" :     True if (args.insert_deadbeef) else False,
        "compute_macs" :        True if (args.compute_macs) else False,
        "gauss_scale" :         float(args.gauss_scale),
        "pzero_tensors" :       [float(args.pzero_A),float(args.pzero_B),float(args.pzero_C)]
    }

    # --------------------------------------
    # MAIN TEST LOOP
    # --------------------------------------
    
    # Prepare configuration dict for systolic array model
    SA = slib.get_sa_dict(HW_PARAMS)

    # Prepare tests
    TESTS, TILEINFO, LIMITS = th.generate_tests(TOPTS, HW_PARAMS, int(args.n_random_tests))

    print("Starting test: {}".format(TOPTS['test_type']))

    # Debug test is special, we don't use the normal flow
    if (TOPTS['test_type']=='debug_test'):
        th.run_cfg_test(HW_PARAMS, TOPTS['assert_no_errors'], test_dir=args.test_dir)

    # Normal convolution tests
    else:
        # Loop over all tests to be performed
        for i in range(len(TESTS[0])):
            
            # Reformat the test lists into tensor_shapes and TILING_DICT
            d = TESTS[2][i]; s = TESTS[3][i]; p = 0

            Aw = (1+s*(TESTS[5][i]-1)) + (1+d*(TESTS[0][i]-1)) - 1
            Ah = (1+s*(TESTS[6][i]-1)) + (1+d*(TESTS[1][i]-1)) - 1

            tensor_shapes = [
                [TESTS[4][i],Ah,Aw],                                # A tensor (inputs)
                [TESTS[7][i],TESTS[4][i],TESTS[1][i],TESTS[0][i]],  # B tensor (outputs)
                [TESTS[7][i],TESTS[6][i],TESTS[5][i]]               # C tensor (psums)
            ]

            TILING_DICT = {
                'C_tile_shape'  :   [TILEINFO[1][i],TILEINFO[2][i],TILEINFO[3][i]],  #[C_out, Ch, Cw]
                'tile_cin'      :   TILEINFO[0][i],
                'X_used'        :   TESTS[8][i],
                'Y_used'        :   TESTS[9][i]
            }

            preload = TESTS[10][i]

            if not silent:
                print("------------------------------------------------------------------------------------------------------------------------")
                print("Test number {}".format(i+1))
                print("PSum size: [{},{},{}] | Weight size: [{},{},{},{}] | Input size: [{},{},{}] | d={}, s={}, p={}".format(tensor_shapes[2][0],tensor_shapes[2][1],tensor_shapes[2][2],tensor_shapes[1][0],tensor_shapes[1][1],tensor_shapes[1][2],tensor_shapes[1][3],tensor_shapes[0][0],tensor_shapes[0][1],tensor_shapes[0][2],d,s,0))
                print("Tile size: [{},{},{}] | C_in tile size: {} | X_used: {}, Y_used: {} ".format(TILEINFO[1][i],TILEINFO[2][i],TILEINFO[3][i],TILEINFO[0][i],TESTS[8][i],TESTS[9][i]))
                print("------------------------------------------------------------------------------------------------------------------------")
                
            # Generate random values and run convolution
            slib.generate_and_run_test(tensor_shapes, TILING_DICT, d, s, HW_PARAMS, preload=preload, generate_vcd=False, pzero_tensors=TOPTS['pzero_tensors'], insert_deadbeef=TOPTS['insert_deadbeef'], gauss_scale=TOPTS['gauss_scale'], ones_test=TOPTS['ones_test'], print_statistics=TOPTS['print_statistics'], assert_no_errors=TOPTS['assert_no_errors'], test_dir=args.test_dir, silent=silent)
            
