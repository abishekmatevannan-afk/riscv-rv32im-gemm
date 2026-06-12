# Makefile for RV32I Core CPU
# All simulation output goes to sim/ which is created automatically if missing.

SRC_DIR = src
TB_DIR  = tb
SIM_DIR = sim

$(shell mkdir -p $(SIM_DIR))

# Integration tests need every source file because they instantiate the full
# pipeline. Unit tests only need their own module file.
INTEGRATION = top top_pipeline uart_integration uart_mem_map \
              exception_test axi4_lite matmul \
              exception_handler_stack \
              uart_integration_debug \
              perf_demo \
              parallel_mac systolic_array \
              mul_div \
              pmacc \
              pmacc_pipeline


# make sim MODULE=<name>
# Compile and run one testbench. Two modes:
#   Unit test:        make sim MODULE=alu
#     compiles tb/tb_alu.sv + src/alu.sv only
#   Integration test: make sim MODULE=top_pipeline
#     compiles tb/tb_top_pipeline.sv + all src/*.sv
# Output goes straight to the terminal. Use make wave after to view signals.
sim:
ifeq ($(filter $(MODULE),$(INTEGRATION)),$(MODULE))
	iverilog -g2012 -o $(SIM_DIR)/$(MODULE).vvp \
		$(TB_DIR)/tb_$(MODULE).sv \
		$(SRC_DIR)/*.sv && \
	vvp $(SIM_DIR)/$(MODULE).vvp
else
	iverilog -g2012 -o $(SIM_DIR)/$(MODULE).vvp \
		$(TB_DIR)/tb_$(MODULE).sv \
		$(SRC_DIR)/$(MODULE).sv && \
	vvp $(SIM_DIR)/$(MODULE).vvp
endif


# make wave MODULE=<name>
# Open the VCD waveform from the last simulation run for a module in VS Code.
# Run make sim MODULE=<name> first to generate the .vcd file.
#   Example: make wave MODULE=dcache
#   Opens:   sim/dcache.vcd in Wavetrace
wave:
	code $(SIM_DIR)/$(MODULE).vcd


# make test-all
# Run every testbench in tb/ and print a pass/fail line for each one.
# Compilation errors are caught and reported separately from runtime failures.
# Exits with a nonzero code if anything fails, so this works in CI pipelines.
#   Example: make test-all
#   Output:  one line per module, then a totals summary at the bottom
test-all:
	@echo "========================================================"
	@echo "  RV32I Core — Full Test Suite"
	@echo "========================================================"
	@pass=0; fail=0; \
	for tb in $(TB_DIR)/tb_*.sv; do \
		mod=$$(basename $$tb .sv | sed 's/^tb_//'); \
		printf "  %-32s" "$$mod"; \
		if echo "$(INTEGRATION)" | tr ' ' '\n' | grep -qx "$$mod"; then \
			compile_out=$$(iverilog -g2012 -o $(SIM_DIR)/$$mod.vvp \
				$$tb $(SRC_DIR)/*.sv 2>&1); \
		else \
			compile_out=$$(iverilog -g2012 -o $(SIM_DIR)/$$mod.vvp \
				$$tb $(SRC_DIR)/$$mod.sv 2>&1); \
		fi; \
		if [ $$? -ne 0 ]; then \
			echo "COMPILE ERROR"; \
			echo "$$compile_out" | sed 's/^/    /'; \
			fail=$$((fail + 1)); \
			continue; \
		fi; \
		run_out=$$(vvp $(SIM_DIR)/$$mod.vvp 2>&1); \
		if echo "$$run_out" | grep -qE "(^FAIL|^TIMEOUT| FAIL | FAIL$$|[1-9][0-9]* failed)"; then \
			echo "FAIL"; \
			echo "$$run_out" | grep -E "(FAIL|TIMEOUT|error|Error)" | head -5 | sed 's/^/    /'; \
			fail=$$((fail + 1)); \
		else \
			echo "pass"; \
			pass=$$((pass + 1)); \
		fi; \
	done; \
	echo "========================================================"; \
	echo "  $$pass passed   $$fail failed"; \
	echo "========================================================"; \
	test $$fail -eq 0


# make all
# Run every testbench with full verbose output — no pass/fail filtering,
# everything gets printed. Useful when you want to read raw simulation output
# without the summary wrapper, or when debugging a new testbench.
#   Example: make all
#   Output:  full simulation output for every module, one after another
all:
	@for tb in $(TB_DIR)/tb_*.sv; do \
		mod=$$(basename $$tb .sv | sed 's/tb_//'); \
		echo "=== $$mod ==="; \
		iverilog -g2012 -o $(SIM_DIR)/$$mod.vvp $$tb $(SRC_DIR)/*.sv && \
		vvp $(SIM_DIR)/$$mod.vvp; \
		echo ""; \
	done


# make clean
# Delete all compiled simulation binaries and waveform files from sim/.
# Safe to run any time — source files in src/ and tb/ are never touched.
#   Example: make clean
#   Removes: sim/*.vvp  sim/*.vcd
clean:
	rm -f $(SIM_DIR)/*.vvp $(SIM_DIR)/*.vcd


.PHONY: sim wave test-all all clean