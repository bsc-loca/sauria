if [ -z "$PYTHON_DIR" ]
then
      echo "Error: Environment variable PYTHON_DIR is not set. Please source the setup.sh script."
      exit 1
fi

if [ -d "$PYTHON_DIR/sauria-env" ]; then
    echo "Activating Python virtual environment found in $PYTHON_DIR/sauria-env."
    source "$PYTHON_DIR/sauria-env/bin/activate"
else
    echo "(Only first time after clone) Creating new Python virtual environment in $PYTHON_DIR/sauria-env."
    cd "$PYTHON_DIR"
    source install_venv.sh
fi

TEST_TYPE=$1

if [ -z "$TEST_TYPE" ]
then
      echo "No test type passed. Generating a conv_validation test by default."
      echo "Test type options: [conv_validation, bmk_small, bmk_torture, power_estimation]"
      echo ""
      TEST_TYPE="conv_validation"
else
      echo "Generating stimuli for test type: $TEST_TYPE"
      echo ""
fi

sed -i "43s/.*/    \"test_type\" :           \"$TEST_TYPE\",/" helpers/test_helper.py

python3.9 tb_sauria_generator.py
