MAX_CYCLES=1000000000
VCD_START_TIME=0

VCD_NAME=$1

if [ -z "$VCD_NAME" ]
then
    VCD_OPTS=""
else
    VCD_OPTS="+vcd +vcd_name=$VCD_NAME +start_vcd_time=$VCD_START_TIME"
fi

./Test-Sim $TEST_TYPE +max-cycles=$MAX_CYCLES $VCD_OPTS