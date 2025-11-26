#!/usr/bin/env bash

export PYTHON_DIR=$(pwd)/Python

if [ -d "$PYTHON_DIR/sauria-env" ]; then
    echo "Activating Python virtual environment found in $PYTHON_DIR/sauria-env..."
    source "$PYTHON_DIR/sauria-env/bin/activate"
else
    echo "Python virtual environment does not exist. Creating new Python venv in" \
        "$PYTHON_DIR/sauria-env... (Only needs to be done once)"
    source "$PYTHON_DIR/install_venv.sh"
fi

DATA_DIR=$(jupyter --data-dir 2>/dev/null || :)
if [ -z "$DATA_DIR" ]; then
    echo "WARNING: Unable to determine Jupyter data dir. No Python Kernel will be registered"
else
    KERNEL_DIR="$DATA_DIR/kernels"
    KERNEL_NAME="sauria_kernel"

    if [ -d "$KERNEL_DIR/$KERNEL_NAME"  ]; then
        echo "Updating Python kernel $KERNEL_DIR/$KERNEL_NAME..."
    else
        echo "Creating new Python kernel for Jupyter Notebooks in $KERNEL_DIR/$KERNEL_NAME..."
    fi

    python -m ipykernel install --user --name "$KERNEL_NAME" --display-name "SAURIA Kernel"
fi

export RTL_DIR=$(pwd)/RTL
export PULP_DIR=$(pwd)/pulp_platform

export TEST_DIR=$(pwd)/test
export VERILATOR_ROOT=$(pwd)/tools/verilator
export PATH="$VERILATOR_ROOT/bin:$PATH"

# Export environment variables to load with Python
env > $PYTHON_DIR/env_raw

# Remove everything after "BASH_FUNC_ml" to avoid nasty warnings
sed -n '/BASH_FUNC_ml*/q;p' $PYTHON_DIR/env_raw > $PYTHON_DIR/env
rm $PYTHON_DIR/env_raw
