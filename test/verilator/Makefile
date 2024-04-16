default: all

arith = EXACT
base_dir = $(abspath .)
tb_top = sauria_tester
veri_opt_flags = -O2 -CFLAGS "-O2"

veri_flags = \
	-DVERILATOR_GCC \
	+define+$(arith) \
	+define+COMMON_CELLS_ASSERTS_OFF \
	+incdir+$(PULP_DIR)/axi/include \
	+incdir+$(PULP_DIR)/common_cells/include \
	--top-module $(tb_top) \
	--unroll-count 256 \
	--trace \
	--trace-max-array 256 \
	--trace-max-width 256 \
	-Wno-lint -Wno-style -Wno-STMTDLY -Wno-fatal \
	-CFLAGS "-std=c++11 -D$(arith)" \
	--clk clk_sys \
	--exe \
	--trace-structs \
	--trace-params \
	--trace-underscore \
	--assert \
	--savable \
	--build

junk += Test-Sim

all: verilator.log
verilator.log:
	verilator --version
	verilator --cc -F verilator_filelist.f $(veri_flags) $(veri_opt_flags) -o Test-Sim 2>&1 | tee $@
	cp obj_dir/Test-Sim .

junk += verilator.log
junk += obj_dir

clean:
	rm -rf $(junk)
	