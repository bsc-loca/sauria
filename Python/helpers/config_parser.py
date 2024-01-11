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

def bmask(bit_width):
    
    return ((2**bit_width)-1)

def parse_reg_config(ALL_SIGNALS, TOTAL_REGS, Y, IF_W, silent=True):
    
    regs = np.zeros((TOTAL_REGS), dtype=np.uint32)
    regs_idx = 0

    for r, region in enumerate(ALL_SIGNALS):
           
        current_idx = 0
        current_lsb_bit = 0
        current_msb_bit = 0
        
        for i, signal in enumerate(region):
                        
            # Dilation pattern is a "special" case => Occupies several registers itself
            if (r==1) and (i==10):
                
                if not silent:
                    print("\n{} mapped in:".format(signal[0]))
                    print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx, current_lsb_bit))
                
                accumulated_bits = 0
                
                for k in range(int(np.ceil((signal[1]+current_lsb_bit)/IF_W))):
                    
                    # LSBs from first register
                    if(k==0):
                        regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))<<current_lsb_bit)&0xFFFFFFFF)
                        
                        accumulated_bits += (IF_W-current_lsb_bit)
                        current_idx += 1
                        regs_idx += 1
                    
                    # MSBs from last register
                    elif(k==(int(np.ceil((signal[1]+current_lsb_bit)/IF_W))-1)):
                        regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))>>accumulated_bits)&0xFFFFFFFF)
                        
                        current_msb_bit = signal[1]-accumulated_bits-1

                        # Prep for next array position
                        if (current_msb_bit == (IF_W-1)):
                            current_lsb_bit = 0
                            current_idx += 1
                            regs_idx += 1
                        else:
                            current_lsb_bit = current_msb_bit + 1

                    # Other bits from intermediate registers
                    else:
                        regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))>>accumulated_bits)&0xFFFFFFFF)
                        
                        accumulated_bits += IF_W
                        current_idx += 1
                        regs_idx += 1
            
                if not silent: print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
            
            # Local woffs is another "special" case => Array of Y values spanning over several registers
            elif (r==1) and (i==12):
                
                # Loop through all array positions
                for y in range(Y):
                    
                    current_msb_bit = current_lsb_bit + signal[1]-1
                
                    # If we go to next register
                    if(current_msb_bit >= IF_W):
                        current_msb_bit = current_msb_bit - IF_W
                        regs[regs_idx] = regs[regs_idx] | (((signal[2][y]&bmask(signal[1]))<<current_lsb_bit)&0xFFFFFFFF)
                        regs[regs_idx+1] = regs[regs_idx+1] | ((signal[2][y]&bmask(signal[1]))>>(IF_W-current_lsb_bit))
                        
                        current_idx += 1
                        regs_idx += 1
                    
                        if not silent:
                            print("\n{} mapped in:".format(signal[0]))
                            print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx-1, current_lsb_bit))
                            print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
                    
                    # If contained in current register
                    else:
                        regs[regs_idx] = regs[regs_idx] | ((signal[2][y]&bmask(signal[1]))<<current_lsb_bit)
                    
                        if not silent:
                            print("\n{} mapped in:".format(signal[0]))
                            print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx, current_lsb_bit))
                            print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
    
                    # Prep for next array position
                    if (y<Y-1):
                        if (current_msb_bit == (IF_W-1)):
                            current_lsb_bit = 0
                            current_idx += 1
                            regs_idx += 1
                        else:
                            current_lsb_bit = current_msb_bit + 1
        
                # Final Prep for next array position
                if i==(len(region)-1):
                    current_lsb_bit = 0
                    current_idx += 1
                    regs_idx += 1
                else:
                    if (current_msb_bit == (IF_W-1)):
                        current_lsb_bit = 0
                        current_idx += 1
                        regs_idx += 1
                    else:
                        current_lsb_bit = current_msb_bit + 1
        
            # Otherwise we map procedurally
            else:
                        
                current_msb_bit = current_lsb_bit + signal[1]-1
                
                # If we go to next register
                if(current_msb_bit >= IF_W):
                    current_msb_bit = current_msb_bit - IF_W
                    regs[regs_idx] = regs[regs_idx] | (((signal[2]&bmask(signal[1]))<<current_lsb_bit)&0xFFFFFFFF)
                    regs[regs_idx+1] = regs[regs_idx+1] | ((signal[2]&bmask(signal[1]))>>(IF_W-current_lsb_bit))
                    
                    current_idx += 1
                    regs_idx += 1
                
                    if not silent:
                        print("\n{} mapped in:".format(signal[0]))
                        print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx-1, current_lsb_bit))
                        print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
                
                # If contained in current register
                else:
                    regs[regs_idx] = regs[regs_idx] | ((signal[2]&bmask(signal[1]))<<current_lsb_bit)
    
                    if not silent:
                        print("\n{} mapped in:".format(signal[0]))
                        print("Start_reg_idx = {}; Start_bit = {}".format(regs_idx, current_lsb_bit))
                        print("  End_reg_idx = {};   End_bit = {}".format(regs_idx, current_msb_bit))
    
    
                if i==(len(region)-1):
                    current_lsb_bit = 0
                    current_idx += 1
                    regs_idx += 1
                else:
                    if (current_msb_bit == (IF_W-1)):
                        current_lsb_bit = 0
                        current_idx += 1
                        regs_idx += 1
                    else:
                        current_lsb_bit = current_msb_bit + 1
                        
    return regs


