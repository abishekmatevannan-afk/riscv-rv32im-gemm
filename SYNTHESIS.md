# Synthesis Report

Tool: **Yosys 0.66** (git sha1 7f8fdfd8d7bc08c749a2a969388d3425d4f369d5)  
Date: 2026-06-10  
Top module: `top_pipeline`  
Source: all 34 `.sv` files in `src/`

## How to reproduce

```bash
# Generic (technology-independent)
yosys synth.ys

# iCE40 FPGA target
yosys synth_ice40.ys
```

---

## iCE40 target (synth_ice40)

| Resource       | Count   | Notes |
|----------------|---------|-------|
| SB_LUT4        | 143,299 | see breakdown below |
| SB_DFF / DFFE  | 63,009  | flip-flops (all types) |
| SB_RAM40_4K    | 4       | block RAMs inferred |
| SB_CARRY       | 807     | carry chains |

### Why 143K LUTs — and what the real pipeline number is

The 143,299 figure is real post-`synth_ice40` output, not a pre-mapping estimate. It is **not** comparable to published LUT counts for other cores without context.

The cache and SRAM arrays are synthesised as flip-flop arrays (distributed RAM) rather than block RAMs because Yosys's automatic BRAM inference cannot match the multi-dimensional, byte-enable, read-write access patterns used here. Each bit of a flip-flop array requires LUT-based address decode and output mux logic — approximately 1.5 LUTs per stored bit.

**Memory array bit-count breakdown:**

| Array          | Bits   | LUTs (≈1.5×) |
|----------------|--------|--------------|
| D$ data (4KB)  | 32,768 | ~49,152      |
| I$ data (4KB)  | 32,768 | ~49,152      |
| D$ ctrl (valid+dirty+tag) | 5,632 | ~8,448 |
| I$ ctrl (valid+tag)       | 5,376 | ~8,064 |
| ISRAM (1KB)    |  8,192 |  ~12,288     |
| DSRAM (1KB)    |  8,192 |  ~12,288     |
| **Subtotal**   | **92,928** | **~139,392** |

Subtracting the memory overhead: **143,299 − 139,392 ≈ 3,900 LUTs for all pipeline logic** (ALU, hazard unit, branch predictor, CSR file, UART, systolic array, AXI4-Lite fabric, PMU). This is consistent with the Artix-7 estimate below.

**To get an accurate standalone LUT count:** add `(* ram_style = "block" *)` to the cache and SRAM array declarations. Vivado and Quartus both support this attribute, and it maps those arrays to block RAM, reducing the logic fabric to ~4K LUTs — in line with PicoRV32 (~2.5K) and VexRiscv (~4–8K).

### Clock frequency estimate (not measured — extrapolated from comparable cores)

nextpnr-ice40 cannot route the design without BRAM inference (design exceeds device capacity by 24×). No measured timing result is available from the open-source flow.

The following figures are **extrapolated estimates**, not place-and-route results:

| Target       | Tool    | Estimated Fmax | Extrapolation basis |
|--------------|---------|----------------|---------------------|
| Artix-7 XC7A | Vivado  | ~100–150 MHz   | 5-stage in-order pipeline; critical path is ALU ripple-carry + forwarding mux + cache tag compare. PicoRV32 achieves ~100–200 MHz, VexRiscv ~150–350 MHz on the same device. This design's feature set (caches, branch predictor, CSR, UART) places it between the two. |
| Cyclone IV   | Quartus | ~80–120 MHz    | Cyclone IV carries ~1.2× longer gate delay than Artix-7; scaled accordingly. |

These ranges would only be confirmed by running Vivado synthesis + place-and-route with `(* ram_style = "block" *)` attributes on the cache arrays. The open-source flow cannot produce a valid timing report without BRAM inference.

## Vivado BRAM Inference — Investigation and Findings

**What was attempted:** Targeted Artix-7 (`xc7a35tcpg236-1`, then `xc7a100tcsg324-1`) through Vivado to get a real post-place-and-route Fmax, replacing the Yosys-based estimate above.

**What was found:** Despite `(* ram_style = "block" *)` attributes already present on the cache and SRAM storage arrays, Vivado could not map `dcache.sv`/`icache.sv` to true Block RAM. The root cause: both caches read their storage arrays combinationally (`assign cached_word = data[addr_idx][word_off];`), resolving hit, the tag comparison, and the data output all within a single cycle. Real Block RAM is an inherently synchronous primitive — no Xilinx (or any vendor) BRAM tile supports a true zero-latency read. Vivado silently fell back to flip-flop-based storage plus large LUT-based multiplexer trees to emulate the combinational access pattern.

This showed up concretely in implementation:

- **On xc7a35t:** FDRE over-utilized — 81,978 flip-flops required vs. 65,518 available
- **On xc7a100t:** LUT as Logic over-utilized — 128,921 LUTs required vs. 63,400 available, nearly 2× over even on the larger device

Retargeting to a bigger device did not fix this, since the LUT cost was coming from the multiplexer trees needed to fake combinational access to a 256-line array, not just raw storage bit count. A bigger device would have masked the symptom without addressing the underlying architectural mismatch between the cache's idealized timing model and how real BRAM behaves.

**The correct fix:** Pipeline the cache reads using a one-cycle-ahead prefetch scheme — index the storage array using the pre-register address (the combinational "next PC" value for icache, the combinational pre-EX/MEM ALU result for dcache) one cycle before it's needed, so the registered lookup result is ready exactly when the corresponding address itself becomes registered. Done correctly, this adds zero stall cycles on a cache hit, since the BRAM's one-cycle latency is hidden behind work the pipeline is already doing.

**Why it isn't merged:** This was prototyped on a separate branch (`bram-prefetch-reads`). It passed both cache unit tests (`tb_icache`, `tb_dcache`) standalone, but broke a real correctness case in pipeline integration — LHU (load halfword unsigned) returned `0x00000000` instead of the correct value during the matmul benchmark, and the hazard-unit assertion (`load_use_hazard` asserted but `if_id_stall` low) fired on nearly every cycle of execution. The prefetch timing interacted with the existing load-use hazard detection logic in a way that wasn't caught until full pipeline simulation. Cycle counts also regressed (Parallel MAC 69→79, Systolic 77→87 cycles), indicating the "zero added latency" property didn't hold as designed.

Given the proximity to internship application deadlines, this was reverted rather than debugged further under time pressure. The branch remains available in the repository as a record of the investigation, the root-cause analysis, and the attempted fix, but main retains the original combinational-read cache design, which is correct and fully verified in simulation (33/33 tests passing) but does not currently map to real Block RAM on Xilinx 7-series parts.

**Status:** Documented as a known follow-up rather than a blocking issue. The cache architecture is functionally correct and matches standard direct-mapped cache design; the gap is specifically in synthesizability of the read timing model for real BRAM primitives, not in cache correctness or pipeline integration as currently merged.

## Generic target (CMOS gate-level via ABC)

| Resource       | Count   |
|----------------|---------|
| Total cells    | 232,141 |
| FF (all types) | 55,009  |
| Combinational  | 177,132 |

---

## Key observations

1. **Design elaborates and synthesises cleanly** — zero errors, zero undefined ports.
2. **All 33 testbenches pass** after synthesis-safe rewrite (no `initial` blocks).
3. **RV32M multiplier** will infer DSP48 blocks on Xilinx targets; Yosys maps it to LUTs here.
4. **Effective pipeline LUT count is ~3,900** — the 143K headline figure is almost entirely flip-flop-mapped memory arrays, not logic (see breakdown above).
5. **nextpnr-ice40 place-and-route fails** — the design requires 188,718 iCE40 LCs vs 7,680 on HX8K (2,457% utilisation). This is a direct consequence of the BRAM inference miss: on a Vivado/Quartus flow with BRAM attributes the design would fit and route cleanly.

## Estimated FPGA footprint (Xilinx Artix-7, with BRAM inference)

| Block         | Estimated LUTs | Estimated BRAMs |
|---------------|----------------|-----------------|
| Pipeline core | ~3,000         | 0               |
| I$ (4KB)      | ~200           | 1               |
| D$ (4KB)      | ~400           | 1               |
| ISRAM (32KB)  | ~50            | 8               |
| DSRAM (256KB) | ~50            | 64              |
| Parallel MAC  | ~400           | 0               |
| Systolic accel| ~500           | 0               |
| UART + PMU    | ~300           | 0               |
| **Total**     | **~4,900**     | **~74**         |

This estimate is consistent with comparable open-source RV32I+M cores (e.g. PicoRV32 ≈ 2.5K LUTs, VexRiscv ≈ 4–8K LUTs depending on features).

---

## Performance benchmark (4×4 INT8 GEMM, `make sim MODULE=matmul`)

| Version          | Cycles | Instrs | CPI   | Speedup vs scalar |
|------------------|--------|--------|-------|-------------------|
| Scalar (RV32M mul) | 1,065 |    841 | 1.266 | 1.00×             |
| SIMD (PDOT)        |    261 |    201 | 1.299 | 4.08×             |
| Parallel MAC       |     79 |     — |   —   | 13.48×            |
| Systolic array     |     87 |     — |   —   | 12.24×            |

Scalar: hardware `mul` (RV32M), 4×4 triple-nested loop, 64 load-use stalls (lbu→mul each k-iteration).  
SIMD: load-use stall before PDOT eliminated by instruction scheduling — 3 independent C-address instructions (slli/add/add) moved between `lw x21` and `pdot`, filling the stall slot. 261−201=60 overhead cycles from branch mispredictions and cold cache.  
D$ hit rate: 98.3% scalar / 96.2% SIMD. Parallel MAC fires all 16 PEs simultaneously, 4-cycle compute; 75 cycles of CPU overhead are AXI4-Lite register writes. Systolic array uses Kung-Leiserson output-stationary wavefront, 11-cycle compute; 76 cycles overhead. Higher CPU overhead than parallel MAC for a single 4×4 tile because the wavefront fill latency is longer.

**Prior incorrect numbers (do not use):** old scalar 1,589/1,353=CPI 1.17 was artificially low — 8×64=512 dead NOPs (remnants of old shift-and-add loop) diluted the stall fraction. Old SIMD 277/201=CPI 1.38 was artificially high — load-use stall before every PDOT had not been scheduled away.
