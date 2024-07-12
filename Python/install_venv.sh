if [ -z "$PYTHON_DIR" ]
then
      echo "Error: Environment variable PYTHON_DIR is not set. Please source the setup.sh script."
      exit 1
fi

ENV_DIR="$PYTHON_DIR/sauria-env"

if [ -d "$ENV_DIR" ]; then
    echo "Virtual environment already exists. Setup cancelled."
    exit 0
fi

echo "Creating virtual environment using Python 3.9 (change version if desired, but some required packages might not be compatible with that specific version of Python)..."
python3.9 -m venv "$ENV_DIR"

echo "Activating the virtual environment..."
source "$ENV_DIR/bin/activate"

pip install --upgrade pip

echo "Installing project dependencies"
pip install -r "$PYTHON_DIR/requirements_pip.txt"

echo "Setup completed."
