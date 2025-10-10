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

def get_params(version):
    HOPTS = {}

    # -----------------------------------------
    # COMMON PARAMETERS ACCROSS CONFIGURATIONS
    # -----------------------------------------

    # Address offsets
    # *******************************************
    HOPTS["MainMemory_offset"] =   0x0000_0000      # Starting address of data in main memory
    HOPTS["SAURIA_offset_DMA"] =   0xD000_0000      # SAURIA offset from the POV of DMA
    HOPTS["CTRL_offset"] =         0x4410_0000      # SAURIA controller offset
    HOPTS["CORE_offset"] =         0x4420_0000      # SAURIA core offset
    HOPTS["DMA_offset"] =          0x4430_0000      # uDMA offset
    HOPTS["CFG_CON_offset"] =      0x0000_0200      # Control registers offset
    HOPTS["CFG_IFM_offset"] =      0x0000_0400      # IFmap Feeder registers offset
    HOPTS["CFG_WEI_offset"] =      0x0000_0600      # Weight Fetcher registers offset
    HOPTS["CFG_PSM_offset"] =      0x0000_0800      # Partial sums manager offset
    HOPTS["MEMA_offset"] =         0x0001_0000      # MEM A access via AXI Lite
    HOPTS["MEMB_offset"] =         0x0002_0000      # MEM B access via AXI Lite
    HOPTS["MEMC_offset"] =         0x0003_0000      # MEM C access via AXI Lite
    
    # Config Interface parameters
    # *******************************************
    HOPTS["CFG_AXI_DATA_WIDTH"] =  32      # Configuration interface (AXI4-Lite)
    HOPTS["CFG_AXI_ADDR_WIDTH"] =  32

    # -----------------------------------------
    # HARDWARE VERSIONS
    # -----------------------------------------

    if version=="FP16_8x16":

        # Memory Sizes
        # *******************************************
        HOPTS["MEMA_DEPTH"] =          2048
        HOPTS["MEMB_DEPTH"] =          1024
        HOPTS["MEMC_DEPTH"] =          2048

        # Data Interface parameters
        # *******************************************
        HOPTS["DATA_AXI_DATA_WIDTH"] = 128     # Memory interface (AXI4)
        HOPTS["DATA_AXI_ADDR_WIDTH"] = 32

        # Systolic Array HW parameters
        # *******************************************
        HOPTS["X"] =                   16      # SA X size
        HOPTS["Y"] =                   8       # SA Y size
        HOPTS["DILP_W"] =              64      # Dilation parameter width
        HOPTS["PARAMS_W"] =            8       # General parameters width
        HOPTS["TH_W"] =                2       # Negligence threshold width
        HOPTS["IFM_FIFO_POSITIONS"] =  5       # IFmap Feeder FIFO positions
        HOPTS["WEI_FIFO_POSITIONS"] =  4       # Weight Fetcher FIFO positions
        HOPTS["FIFO_FILL_CYCLES"] =    1       # FIFO filling cycles before computation starts
        
        # Arithmetic options
        # *******************************************
        HOPTS["IA_W"] =                16      # IFmap bits
        HOPTS["IB_W"] =                16      # Weight bits
        HOPTS["OC_W"] =                16      # Partial sum bits
        HOPTS["OP_TYPE"] =             1       # 0 for int, 1 for FP

        # FP configuration
        HOPTS["IA_MANT"] =             10      # IFmap mantissa bits
        HOPTS["IB_MANT"] =             10      # Weight mantissa bits
        HOPTS["IC_MANT"] =             10      # Partial sum mantissa bits
        HOPTS["rounding"] =            "RNE"   # Rounding type

        # Approximate computing
        HOPTS["approx_comp"] =         False   # If false, all options are ignored
        HOPTS["mul_type"] =            3
        HOPTS["M"] =                   14
        HOPTS["add_type"] =            4
        HOPTS["A"] =                   16

    elif version=="int8_8x16":

        # Memory Sizes
        # *******************************************
        HOPTS["MEMA_DEPTH"] =          2048
        HOPTS["MEMB_DEPTH"] =          1024
        HOPTS["MEMC_DEPTH"] =          2048

        # Data Interface parameters
        # *******************************************
        HOPTS["DATA_AXI_DATA_WIDTH"] = 128     # Memory interface (AXI4)
        HOPTS["DATA_AXI_ADDR_WIDTH"] = 32

        # Systolic Array HW parameters
        # *******************************************
        HOPTS["X"] =                   16      # SA X size
        HOPTS["Y"] =                   8       # SA Y size
        HOPTS["DILP_W"] =              64      # Dilation parameter width
        HOPTS["PARAMS_W"] =            8       # General parameters width
        HOPTS["TH_W"] =                2       # Negligence threshold width
        HOPTS["IFM_FIFO_POSITIONS"] =  5       # IFmap Feeder FIFO positions
        HOPTS["WEI_FIFO_POSITIONS"] =  4       # Weight Fetcher FIFO positions
        HOPTS["FIFO_FILL_CYCLES"] =    1       # FIFO filling cycles before computation starts
        
        # Arithmetic options
        # *******************************************
        HOPTS["IA_W"] =                8       # IFmap bits
        HOPTS["IB_W"] =                8       # Weight bits
        HOPTS["OC_W"] =                32      # Partial sum bits
        HOPTS["OP_TYPE"] =             0       # 0 for int, 1 for FP

        # FP configuration
        HOPTS["IA_MANT"] =             0        # IFmap mantissa bits
        HOPTS["IB_MANT"] =             0        # Weight mantissa bits
        HOPTS["IC_MANT"] =             0        # Partial sum mantissa bits
        HOPTS["rounding"] =            "RNE"    # Rounding type

        # Approximate computing
        HOPTS["approx_comp"] =         False   # If false, all options are ignored
        HOPTS["mul_type"] =            0
        HOPTS["M"] =                   0
        HOPTS["add_type"] =            0
        HOPTS["A"] =                   0

    # WARNING!!!!! - Not tested yet!!!!
    elif version=="FP16_16x16":

        # Memory Sizes
        # *******************************************
        HOPTS["MEMA_DEPTH"] =          1024
        HOPTS["MEMB_DEPTH"] =          1024
        HOPTS["MEMC_DEPTH"] =          1024

        # Data Interface parameters
        # *******************************************
        HOPTS["DATA_AXI_DATA_WIDTH"] = 128     # Memory interface (AXI4)
        HOPTS["DATA_AXI_ADDR_WIDTH"] = 32

        # Systolic Array HW parameters
        # *******************************************
        HOPTS["X"] =                   16      # SA X size
        HOPTS["Y"] =                   16      # SA Y size
        HOPTS["DILP_W"] =              64      # Dilation parameter width
        HOPTS["PARAMS_W"] =            8       # General parameters width
        HOPTS["TH_W"] =                2       # Negligence threshold width
        HOPTS["IFM_FIFO_POSITIONS"] =  5       # IFmap Feeder FIFO positions
        HOPTS["WEI_FIFO_POSITIONS"] =  4       # Weight Fetcher FIFO positions
        HOPTS["FIFO_FILL_CYCLES"] =    1       # FIFO filling cycles before computation starts
        
        # Arithmetic options
        # *******************************************
        HOPTS["IA_W"] =                16      # IFmap bits
        HOPTS["IB_W"] =                16      # Weight bits
        HOPTS["OC_W"] =                16      # Partial sum bits
        HOPTS["OP_TYPE"] =             1       # 0 for int, 1 for FP

        # FP configuration
        HOPTS["IA_MANT"] =             10      # IFmap mantissa bits
        HOPTS["IB_MANT"] =             10      # Weight mantissa bits
        HOPTS["IC_MANT"] =             10      # Partial sum mantissa bits
        HOPTS["rounding"] =            "RNE"   # Rounding type

        # Approximate computing
        HOPTS["approx_comp"] =         False   # If false, all options are ignored
        HOPTS["mul_type"] =            3
        HOPTS["M"] =                   14
        HOPTS["add_type"] =            4
        HOPTS["A"] =                   16

    # WARNING!!!!! - Not tested yet!!!!
    elif version=="int8_16x16":

        # Memory Sizes
        # *******************************************
        HOPTS["MEMA_DEPTH"] =          2048
        HOPTS["MEMB_DEPTH"] =          2048
        HOPTS["MEMC_DEPTH"] =          512

        # Data Interface parameters
        # *******************************************
        HOPTS["DATA_AXI_DATA_WIDTH"] = 128     # Memory interface (AXI4)
        HOPTS["DATA_AXI_ADDR_WIDTH"] = 32

        # Systolic Array HW parameters
        # *******************************************
        HOPTS["X"] =                   16      # SA X size
        HOPTS["Y"] =                   16      # SA Y size
        HOPTS["DILP_W"] =              64      # Dilation parameter width
        HOPTS["PARAMS_W"] =            8       # General parameters width
        HOPTS["TH_W"] =                2       # Negligence threshold width
        HOPTS["IFM_FIFO_POSITIONS"] =  5       # IFmap Feeder FIFO positions
        HOPTS["WEI_FIFO_POSITIONS"] =  4       # Weight Fetcher FIFO positions
        HOPTS["FIFO_FILL_CYCLES"] =    1       # FIFO filling cycles before computation starts
        
        # Arithmetic options
        # *******************************************
        HOPTS["IA_W"] =                8      # IFmap bits
        HOPTS["IB_W"] =                8      # Weight bits
        HOPTS["OC_W"] =                32     # Partial sum bits
        HOPTS["OP_TYPE"] =             0      # 0 for int, 1 for FP

        # FP configuration
        HOPTS["IA_MANT"] =             10      # IFmap mantissa bits
        HOPTS["IB_MANT"] =             10      # Weight mantissa bits
        HOPTS["IC_MANT"] =             10      # Partial sum mantissa bits
        HOPTS["rounding"] =            "RNE"   # Rounding type

        # Approximate computing
        HOPTS["approx_comp"] =         False   # If false, all options are ignored
        HOPTS["mul_type"] =            3
        HOPTS["M"] =                   14
        HOPTS["add_type"] =            4
        HOPTS["A"] =                   16

    # Dependent parameters
    HOPTS["MEMA_W"] = HOPTS["Y"]*HOPTS["IA_W"]
    HOPTS["MEMB_W"] = HOPTS["X"]*HOPTS["IB_W"]
    HOPTS["MEMC_W"] = HOPTS["Y"]*HOPTS["OC_W"]

    HOPTS['ADRA_W'] = int(np.ceil(np.log2(HOPTS['MEMA_DEPTH'])))
    HOPTS['ADRB_W'] = int(np.ceil(np.log2(HOPTS['MEMB_DEPTH'])))
    HOPTS['ADRC_W'] = int(np.ceil(np.log2(HOPTS['MEMC_DEPTH'])))

    HOPTS['MEMA_N'] = int(HOPTS['MEMA_W']/HOPTS['IA_W'])
    HOPTS['IFM_WOFS_W'] = int(np.ceil(np.log2(HOPTS['MEMA_N'])))
    HOPTS['IFM_IDX_W'] = HOPTS['ADRA_W'] + HOPTS['IFM_WOFS_W'] + 1

    HOPTS['MEMB_N'] = int(HOPTS['MEMB_W']/HOPTS['IB_W'])
    HOPTS['WEI_WOFS_W'] = int(np.ceil(np.log2(HOPTS['MEMB_N'])))
    HOPTS['WEI_IDX_W'] = HOPTS['ADRB_W'] + HOPTS['WEI_WOFS_W'] + 1

    HOPTS['MEMC_N'] = int(HOPTS['MEMC_W']/HOPTS['OC_W'])
    HOPTS['PSM_WOFS_W'] = int(np.ceil(np.log2(HOPTS['MEMC_N'])))
    HOPTS['PSM_IDX_W'] = HOPTS['ADRC_W'] + HOPTS['PSM_WOFS_W'] + 1

    HOPTS['HOST_N'] = int(HOPTS['DATA_AXI_DATA_WIDTH']/HOPTS['IA_W'])

    HOPTS['MEMA_size'] = HOPTS['MEMA_DEPTH'] * HOPTS['MEMA_N']
    HOPTS['MEMB_size'] = HOPTS['MEMB_DEPTH'] * HOPTS['MEMB_N']
    HOPTS['MEMC_size'] = HOPTS['MEMC_DEPTH'] * HOPTS['MEMC_N']

    HOPTS['MEMA_PART'] = int(np.ceil(HOPTS['MEMA_W']/64))
    HOPTS['MEMB_PART'] = int(np.ceil(HOPTS['MEMB_W']/64))
    HOPTS['MEMC_PART'] = int(np.ceil(HOPTS['MEMC_W']/64))
            
    HOPTS['MAX_PART'] = 2   # Max 128b (for now)

    HOPTS['MEMA_HOST_N'] = int(np.ceil(HOPTS['MEMA_W']/HOPTS['DATA_AXI_DATA_WIDTH']))
    HOPTS['MEMB_HOST_N'] = int(np.ceil(HOPTS['MEMB_W']/HOPTS['DATA_AXI_DATA_WIDTH']))
    HOPTS['MEMC_HOST_N'] = int(np.ceil(HOPTS['MEMC_W']/HOPTS['DATA_AXI_DATA_WIDTH']))
            
    HOPTS['HOST_PART'] = int(np.ceil(HOPTS['DATA_AXI_DATA_WIDTH']/64))

    HOPTS['MEMA_CFG_N'] = int(np.ceil(HOPTS['MEMA_W']/HOPTS['CFG_AXI_DATA_WIDTH']))
    HOPTS['MEMB_CFG_N'] = int(np.ceil(HOPTS['MEMB_W']/HOPTS['CFG_AXI_DATA_WIDTH']))
    HOPTS['MEMC_CFG_N'] = int(np.ceil(HOPTS['MEMC_W']/HOPTS['CFG_AXI_DATA_WIDTH']))    

    HOPTS['intyp'] = np.float16 if (HOPTS['OP_TYPE']==1) else np.int64

    return HOPTS