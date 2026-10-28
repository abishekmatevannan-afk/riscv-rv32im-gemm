# Black hole renderer on the RV32IM core
#
#   make            assemble, build the expected image, simulate, write PNGs
#   make test       assembler self-test
#   make clean      remove generated files
#
# The CPU is the RTL in ../src, so this always runs on the current core.

SRC = ../src
OUT = out

$(shell mkdir -p $(OUT))

all: run

blackhole.hex: blackhole.s rvasm.py
	python3 rvasm.py blackhole.s -o blackhole.hex

expected.hex: blackhole.hex blackhole_ref.py
	python3 blackhole_ref.py expected

$(OUT)/blackhole.vvp: tb_blackhole.sv $(wildcard $(SRC)/*.sv)
	iverilog -g2012 -s tb_blackhole -o $@ tb_blackhole.sv $(SRC)/*.sv 2>&1 \
		| grep -v "sorry: constant selects\|cannot be synthesized" || true
	@test -f $@

run: expected.hex $(OUT)/blackhole.vvp
	vvp $(OUT)/blackhole.vvp
	python3 blackhole_ref.py png $(OUT)/blackhole_cpu.hex $(OUT)/blackhole_cpu.png

test:
	python3 rvasm.py --self-test

clean:
	rm -rf $(OUT) blackhole.hex expected.hex

.PHONY: all run test clean
