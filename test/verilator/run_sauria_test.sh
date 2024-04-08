MAX_CYCLES=1000000000
VCD_NAME="new_test.vcd"
VCD_START_TIME=0

TEST_TYPE=$1
USE_VCD=$2

if [ -z "$TEST_TYPE" ]
then
      echo "No test type passed. Running a conv_validation test by default. You can pass a test type as:"
      echo "source run_sauria_test.sh test_type"
      echo "Supported test types: [conv_validation, bmk_small, bmk_torture]"
      echo ""
      TEST_TYPE="conv_validation"
else
      echo "Running test type: $TEST_TYPE"
      echo ""
fi

if [ "$TEST_TYPE" = "debug_test" ]
then
    MAX_CYCLES=100000
fi

if [ -z "$USE_VCD" ]
then
    VCD_OPTS=""
else
    VCD_OPTS="+vcd +vcd_name=$VCD_NAME +start_vcd_time=$VCD_START_TIME"
fi

./Test-Sim $TEST_TYPE +max-cycles=$MAX_CYCLES $VCD_OPTS