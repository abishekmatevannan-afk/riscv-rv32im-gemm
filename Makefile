# Makefile for RV32I Core Simulation

SRC_DIR = src
TB_DIR = tb
SIM_DIR = sim

$(shell mkdir -p $(SIM_DIR))

# Simulate a specific module: make sim MODULE=alu
sim:
ifeq ($(filter $(MODULE),top top_pipeline uart_integration),$(MODULE))
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

# View waveform
wave:
	code $(SIM_DIR)/$(MODULE).vcd

# Simulate everything
all:
	@for tb in $(TB_DIR)/tb_*.sv; do \
		mod=$$(basename $$tb .sv | sed 's/tb_//'); \
		echo "Simulating $$mod..."; \
		iverilog -g2012 -o $(SIM_DIR)/$$mod.vvp $$tb $(SRC_DIR)/*.sv && \
		vvp $(SIM_DIR)/$$mod.vvp; \
	done

clean:
	rm -f $(SIM_DIR)/*.vvp $(SIM_DIR)/*.vcd

.PHONY: sim wave all clean