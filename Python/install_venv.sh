#!/usr/bin/env bash

if [ -z "$PYTHON_DIR" ]
then
    echo "ERROR: Environment variable PYTHON_DIR is not set. Please source the setup.sh script."
    return 1 2>/dev/null || exit 1
fi

ENV_DIR="$PYTHON_DIR/sauria-env"

if [ -d "$ENV_DIR" ]; then
    echo "Virtual environment already exists. Setup cancelled."
    return 0 2>/dev/null || exit 0
fi

echo "Creating virtual environment..."
PYTHON_3_9=$(python3.9 --version 2>/dev/null || :)
if [ -z "$PYTHON_3_9" ]; then
    PYTHON3=$(python3 --version 2>/dev/null || :)
    if [ -z "$PYTHON3" ]; then
        echo "ERROR: No python3 installation found."
        return 1 2>/dev/null || exit 1
    fi

    if echo "$PYTHON3" | grep -q "Python 3\.9"; then
        #python3 --version returns a python3.9v
        true
    else
        echo "WARNING: You are using a different version to Python3.9, which is the recommended" \
             "version. This can cause issues with some required packages being incompatible."
    fi
    python3 -m venv "$ENV_DIR"
else
    python3.9 -m venv "$ENV_DIR"
fi

echo "Activating the virtual environment..."
source "$ENV_DIR/bin/activate"

pip install --upgrade pip

echo "Installing project dependencies..."
pip install -r "$PYTHON_DIR/requirements_pip.txt"

echo "Virtual environment setup completed."
