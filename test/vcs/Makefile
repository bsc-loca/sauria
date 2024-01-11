#######################################################
# Makefile
#######################################################

################################################################################################
###																							 ###
###								BEHAVIORAL SIMULATIONS								 		 ###
###																							 ###
################################################################################################

default: sim

# Analyze the design (3-step flow)
analyze:
	vlogan -V -kdb -sverilog -timescale=1ps/1ps -f vcs_filelist.f +delay_mode_zero -l vlogan.log

# Build the RTL
build:
	vcs tb_sauria_subsystem -V -kdb -ignore initializer_driver_checks +vcs+loopreport+100000 -debug_access+all -l vcs.log
	
# Execute the simulation
run:
	./simv -gui=ultra -l simv-log

run_nogui:
	./simv -l simv-log

# Build and execute
sim: analyze build run
sim_nogui: analyze build run_nogui

clean:
	rm -rf $(junk) *.err *.log verdiLog LIB/AN.DB csrc LIB/work.lib++ simv.daidir verdilog novas* race* ucli* *.key simv* *.fsdb* verdi_config_file AN.DB work.lib++