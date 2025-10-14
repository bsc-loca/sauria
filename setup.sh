export PYTHON_DIR=$(pwd)/Python

if [ -d "$PYTHON_DIR/sauria-env" ]; then
    echo "Activating Python virtual environment found in $PYTHON_DIR/sauria-env."
    source "$PYTHON_DIR/sauria-env/bin/activate"
else
    echo "(Only first time after clone) Creating new Python virtual environment in $PYTHON_DIR/sauria-env."
    cd "$PYTHON_DIR"
    source install_venv.sh
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
