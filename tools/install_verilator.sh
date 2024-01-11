#!/bin/bash

cd verilator
echo $VERILATOR_ROOT
autoconf
./configure --prefix $VERILATOR_ROOT
make
