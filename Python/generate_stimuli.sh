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

python3 tb_sauria_generator.py