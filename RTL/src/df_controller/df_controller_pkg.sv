// Copyright 2023 Barcelona Supercomputing Center (BSC)
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Licensed under the Solderpad Hardware License v 2.1 (the “License”);
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at

// https://solderpad.org/licenses/SHL-2.1/

// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.

//
// Juan Miguel de Haro <juan.deharoruiz@bsc.es>
// Jordi Fornt <jfornt@bsc.es>
//

package df_ctrl_pkg;

    typedef struct {
        logic [11:0] x_step;
        logic [23:0] y_step;
        logic [23:0] k_step;
    } PsumsTilePointer;

    typedef struct {
        logic [11:0] x_step;
        logic [23:0] y_step;
        logic [23:0] c_step;
    } IFmapsTilePointer;

    typedef struct {
        logic [11:0] k_step;
        logic [23:0] c_step;
    } WeightsTilePointer;

    typedef struct {
        logic [23:0] ett;
        logic [23:0] y_step;
        logic [23:0] y_lim;
        logic [23:0] k_step;
        logic [11:0] k_lim;
    } PsumsDMAPointer;

    typedef struct {
        logic [23:0] ett;
        logic [11:0] y_step;
        logic [11:0] y_lim;
        logic [23:0] c_step;
        logic [11:0] c_lim;
    } IFmapsDMAPointer;

    typedef struct {
        logic [23:0] ett;
        logic [11:0] w_step;
        logic [23:0] w_lim;
    } WeightsDMAPointer;

    typedef struct {
        logic [11:0] x_lim;
        logic [11:0] y_lim;
        logic [11:0] k_lim;
        logic [11:0] c_lim;
        PsumsTilePointer psums;
        IFmapsTilePointer ifmaps;
        WeightsTilePointer weights;
    } TilePointers;

    typedef struct {
        PsumsDMAPointer psums;
        IFmapsDMAPointer ifmaps;
        WeightsDMAPointer weights;
    } DMAPointers;

    typedef struct {
        TilePointers tile;
        DMAPointers dma;
    } DMAParams;

    localparam SAURIA_NARGS = 17;

    localparam A_BYTES = 2;
    localparam B_BYTES = 2;
    localparam C_BYTES = 2;

endpackage