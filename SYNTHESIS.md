# Synthesis Report

**Tool:** Vivado 2025.2  
**Target:** Xilinx Artix-7 xc7a200tsbg484-2  
**Top module:** `top_pipeline`  
**Sources:** `src/*.sv`  
**Clock constraint:** `create_clock -period 10.000 [get_ports clk]` (100 MHz)  
**Synthesis option:** `-flatten_hierarchy none`

---

## Fmax Progression

| Step | WNS | Fmax | RTL Change |
|------|-----|------|------------|
| Baseline | -7.787 ns | ~57 MHz | — |
| `ex_addr_i = ex_alu_result` | -4.467 ns | ~69 MHz | Removed SIMD/CSR result mux from dcache prefetch address path |
| `wb_csr_rd` removed | -3.670 ns | ~73 MHz | Replaced combinational CSR bypass in WB mux with registered value; broke csr_rd fanout-34 into forwarding/SIMD path |
| Registered SIMD inputs + 2-cycle stall | -2.730 ns | ~79 MHz | Registered `ex_fwd_a/b/acc` before SIMD unit; removed forwarding network from SIMD timing path entirely |

**Final Fmax: ~79 MHz** (1 / 12.730 ns = 78.6 MHz)

---

## Post-Implementation Timing

| Metric | Value |
|--------|-------|
| WNS | -2.730 ns |
| TNS | -2605.561 ns |
| Failing endpoints | 1,679 / 20,318 |
| Achieved Fmax | ~79 MHz |

### Critical Path

**Source:** `BP/bht_reg[32][1]` (branch predictor BHT flip-flop)  
**Sink:** `ICACHE/data_q_reg`  
**Delay:** 13.476 ns, 21 logic levels

The BHT array is read combinationally through a 64:1 mux tree. The result feeds `predict_taken` (AND-gated with `btb_valid` and tag comparison), which drives the `pc_next` mux, which feeds the icache prefetch address register.

**Known fix:** Register `predict_taken` and `predict_target` with a one-cycle validity gate that suppresses stale predictions after any of the five `pc_next` override conditions (trap, mret, jump mispredict, branch mispredict, icache stall interaction). Expected gain: 4–8 MHz. Not implemented — the validity gate must interact correctly with all five override conditions and three stall types; correctness risk outweighs the gain at this stage. See `Known_limitations.md`.

---

## Post-Implementation Utilization

### Top-Level

| Resource | Count |
|----------|-------|
| Slice LUTs | 14,084 |
| Slice Registers | 5,399 |
| F7 Muxes | 640 |
| F8 Muxes | 278 |
| Block RAM Tile | 1 |
| — RAMB36E1 | 1 |
| DSP48E1 | 8 |
| Bonded IOB | 4 |

### Module-Level

| Module | LUTs | FFs | BRAMs | DSPs |
|--------|------|-----|-------|------|
| top_pipeline (total) | 14,084 | 5,399 | 1 | 8 |
| ACCEL_SUB (parallel_mac_sub) | 3,338 | 883 | 0 | 0 |
| SYSTOLIC_SUB (systolic_array_sub) | 3,372 | 1,089 | 0 | 0 |
| ID_EX (id_ex_reg) | 1,697 | 256 | 0 | 0 |
| EX_MEM (ex_mem_reg) | 1,549 | 151 | 0 | 0 |
| DCACHE (dcache) | 1,384 | 631 | 0 | 0 |
| RF (register_file) | 861 | 992 | 0 | 0 |
| PC (program_counter) | 379 | 40 | 0 | 0 |
| MEM_WB (mem_wb_reg) | 235 | 104 | 0 | 0 |
| BP (branch_predictor) | 242 | 192 | 0 | 0 |
| MULDIV (mul_div_unit) | 298 | 137 | 0 | 8 |
| ICACHE (icache) | 257 | 301 | 1 | 0 |
| DSRAM (axi4_lite_sram_sub READ_ONLY=0) | 128 | 0 | 0 | 0 |
| CSRS (csr_regfile) | 20 | 160 | 0 | 0 |
| PERF (perf_counters) | 72 | 256 | 0 | 0 |
| UART_SUB | 80 | 107 | 0 | 0 |
| ISRAM (axi4_lite_sram_sub READ_ONLY=1) | 97 | 0 | 0 | 0 |

---

## BRAM Inference Status

### icache `data[]` — success

`data[1024]` (1024×32, 4 KB) inferred as 1× RAMB36E1 in Simple Dual Port (SDP) mode. Port A: write-only `always_ff` with no reset clause. Port B: unconditional registered read driven one cycle ahead by `pc_next_i`.

### dcache `data[]` — failed

`data[1024]` (1024×32, 4 KB) maps to RAM64M×176 distributed RAM. 0 Block RAM Tiles.

Root cause: Port B `always_ff` requires a conditional bypass (`write_merge` forwarding) for write-hit coherence. Vivado requires an unconditional synchronous read for BRAM inference. Removing the bypass creates a combinational loop through `write_merge → cached_word_q → write_merge`. See `Known_limitations.md`.

### ISRAM / DSRAM (`axi4_lite_sram_sub`) — not applicable

Both instances are 256×32 (1 KB each). Read path is combinational; BRAM inference is not applicable regardless of `(* ram_style = "block" *)` attribute.

---

## Simulation Results

**Test suite:** 34/34 pass (`make test-all`)

### 4×4 INT8 GEMM Benchmark (`make sim MODULE=matmul`)

Instruction counter uses corrected PMU: `instr_retired = wb_reg_we && !mem_wb_stall` (prior to this fix, stall cycles were counted as extra retirements, inflating instruction counts).

| Version | Cycles | Instrs | CPI | Speedup vs Scalar |
|---------|--------|--------|-----|-------------------|
| Scalar (RV32M mul) | 1,065 | 835 | 1.275 | 1.00× |
| SIMD (PDOT) | 293 | 195 | 1.503 | 3.63× |
| Parallel MAC | 79 | 22 | 3.59 | 13.48× |
| Systolic array | 87 | 26 | 3.35 | 12.24× |

Scalar uses hardware `mul` (RV32M) in a triple-nested loop; 64 load-use stalls from `lbu→mul` on each k-iteration. SIMD CPI increase (1.275→1.503) reflects the two-stall-cycle cost of registered SIMD inputs; speedup drop (4.08×→3.63×) is the direct cost of closing timing on the SIMD carry-chain path. Parallel MAC and Systolic CPIs (3.59 and 3.35) are dominated by AXI4-Lite register-write setup overhead on a 4×4 problem — the accelerators compute in 4 and 11 cycles respectively; at larger matrix sizes CPU overhead amortizes and speedup grows.

---

## How to Reproduce

**Requirements:** Vivado 2025.2, target `xc7a200tsbg484-2`

1. Add all `src/*.sv` files as sources in a new Vivado project.
2. Set `top_pipeline` as the top module.
3. Add the clock constraint:
   ```tcl
   create_clock -period 10.000 [get_ports clk]
   ```
4. Run synthesis with `-flatten_hierarchy none`.
5. Run implementation (`opt_design`, `place_design`, `route_design`).
6. Check timing: `report_timing_summary -file timing.rpt`
7. Check utilization: `report_utilization -hierarchical -file util.rpt`
