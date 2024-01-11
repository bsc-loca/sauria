# SAURIA - Systolic Array tensor Unit for aRtificial Intelligence Acceleration

SAURIA is a Convolutional Neural Network (CNN) accelerator based on an output stationary (OS) systolic array with on-chip, on-the-fly convolution lowering, written entirely in SystemVerilog. 

The accelerator can natively compute convolution and general matrix-matrix multiplication (GEMM) operations of any shape and size. The architecture is parametric and can be configured to use different systolic array shapes and sizes, local memory shapes, and arithmetic formats, but it has been tested extensively using FP16 arithmetic and an array of shape 8x16.

Maintainer: Jordi Fornt Mas (jordi.fornt@bsc.es)

![diagram](diagram.svg?raw=true){width=60%}

## Documentation

Check out the project's Wiki (https://gitlab.bsc.es/jfornt/sauria/-/wikis/home) for some in-depth explanations on how the accelerator is built.

## Requirements

- [Python](https://www.python.org/) (to generate the test stimuli)
- [Gtkwave](http://gtkwave.sourceforge.net/) (for visualization of verilator simulations)

## Installation

After cloning the repository and selecting the branch, run the following command to update all the submodules needed:

```bash
git submodule update --init --recursive
```

## Running Simulations

SAURIA can be emulated using Verilator v4.224. We have observed issues with older and newer versions, so we recommend using a local installation as described below. A testbench for simulation with commercial RTL simulators (e.g. Synopsys VCS or Questa) is also provided.

The first step is to install Verilator, which can be done as follows:

```bash
source setup.sh
cd tools/
source install_verilator.sh
```

Before starting a simulation, we generate a set of random convolutions and GEMMs using Python:

```bash
source setup.sh
cd Python
source generate_stimuli.sh
```

Then, we can move to the test directory to compile and run the emulated accelerator using verilator:

```bash
cd ../test/verilator/
source compile_sauria.sh
source run_sauria_test.sh bmk_small
```

To visualize the waveforms of the simulation we have to generate a VCD dump and read it using GTKWave:

```bash
source run_sauria_test.sh bmk_small vcd
source display_sauria_waves.sh new_test.vcd gtk_waves/sauria_8x16_fp16.gtkw
```
## Publication

If you use SAURIA in your work, you can cite the following paper:

```
@ARTICLE{sauria2023,
  author={Fornt, Jordi and Fontova-Musté, Pau and Caro, Martí and Abella, Jaume and Moll, Francesc and Altet, Josep and Studer, Christoph},
  journal={IEEE Transactions on Very Large Scale Integration (VLSI) Systems}, 
  title={An Energy-Efficient GeMM-Based Convolution Accelerator With On-the-Fly im2col}, 
  year={2023},
  volume={31},
  number={11},
  pages={1874-1878},
  doi={10.1109/TVLSI.2023.3286122}}
```

## Licensing

SAURIA is released under the [Solderpad v2.1 license](https://solderpad.org/licenses/SHL-2.1/).