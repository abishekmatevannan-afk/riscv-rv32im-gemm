# RV32I+M RISC-V CPU Core

A complete RV32I+M RISC-V processor implemented from scratch in SystemVerilog. Features a 5-stage pipeline with full hazard handling, split 4KB L1 cache hierarchy backed by a 5-manager/5-subordinate AXI4-Lite fabric, 2-bit branch predictor, M-mode exception handling, memory-mapped UART, hardware performance counters, two custom accelerators (parallel MAC array and output-stationary systolic array), and custom SIMD extensions benchmarked at **13.5× speedup** on INT8 matrix multiply.

---

## Architecture

```mermaid
flowchart TD
    subgraph Pipeline["5-Stage Pipeline"]
        IF["IF\nFetch + Predict"]
        ID["ID\nDecode + CSR"]
        EX["EX\nExecute + Exception"]
        MEM["MEM\nCache / IO"]
        WB["WB\nWriteback"]
        IF --> ID --> EX --> MEM --> WB
    end

    subgraph Hazards["Hazard Control"]
        HU["Hazard Unit\nload-use · branch flush\ncache stall · trap flush\nPMACC acc stall"]
        FU["Forward Unit\nEX/MEM → EX\nMEM/WB → EX\nacc port (PMACC)"]
        BP["Branch Predictor\n2-bit BHT · BTB\n64 entries"]
    end

    subgraph Caches["L1 Cache Hierarchy"]
        IC["I$ 4KB\ndirect-mapped\nread-only"]
        DC["D$ 4KB\ndirect-mapped\nwrite-back\nwrite-allocate"]
    end

    subgraph Fabric["AXI4-Lite Fabric\n5M · 5S"]
        XBAR["Interconnect"]
        ISRAM["ISRAM\n(parameterized)"]
        DSRAM["DSRAM\n(parameterized)"]
        PMAC["Parallel MAC\n0xFFFE0000\n4×4 PE grid, 4-cycle"]
        SYS["Systolic Array\n0xFFFD0000\nwavefront, 11-cycle"]
    end

    subgraph IO["Memory-Mapped IO"]
        UART["UART TX/RX\n0xFFFF0000\n8N1, IRQ"]
        PMU["PMU\n0xFFFF2000\n8 counters"]
        CSR["CSR File\nmtvec · mepc\nmcause · mstatus"]
        EXC["Exception Unit\nECALL · IRQ\nillegal · misalign"]
    end

    subgraph Exec["Execution Units"]
        ALU["ALU 32-bit"]
        MUL["MUL/DIV\nRV32M"]
        SIMD["SIMD ALU\nPADD · PSUB · PMUL\nPDOT · PMACC\nPSRA · PRELU"]
        RF["Register File\n32 × 32-bit\n3 read ports"]
    end

    IF --> IC
    IC --> Fabric
    MEM --> DC
    DC --> Fabric
    EX --> ALU & MUL & SIMD
    ID --> RF
    WB --> RF
    MEM --> UART & PMU & PMAC & SYS
    EX --> EXC --> CSR
    HU -.stall/flush.-> IF & ID & EX
    FU -.forward.-> EX
    BP -.predict.-> IF
```

---

## Features

### RV32I + RV32M Base ISA
All 37 base integer instructions (R, I, S, B, U, J formats). Hardware multiply/divide unit: MUL, MULH, MULHU, MULHSU, DIV, DIVU, REM, REMU — 32-cycle restoring divider, combinational multiplier that maps to DSP48 on Xilinx targets.

### 5-Stage Pipeline
- **Data forwarding** — EX/MEM and MEM/WB paths for rs1/rs2; dedicated acc forwarding path for PMACC (gated on `ex_is_pmacc` to prevent false forwards)
- **Load-use stall** — 1-cycle bubble for load→use; extended to cover PMACC accumulator port (load→PMACC with same rd stalls)
- **Branch predictor** — 2-bit saturating counter BHT with 64-entry BTB; trained on JAL/JALR/branches; flushes only on misprediction
- **Cache stall** — all five stages frozen during D$ miss; IF/ID frozen with bubble on I$ miss

### L1 Cache Hierarchy
| Cache | Size | Organization | Policy |
|-------|------|-------------|--------|
| Instruction | 4KB | 256 lines × 16 bytes, direct-mapped | Read-only |
| Data | 4KB | 256 lines × 16 bytes, direct-mapped | Write-back, write-allocate |

Both caches back onto the AXI4-Lite fabric via dedicated manager modules.

### AXI4-Lite Memory Fabric (5M/5S)
Address-decoded crossbar connecting five managers (icache, dcache, IO, parallel MAC, systolic array) to five subordinates:

| Subordinate | Address | Description |
|-------------|---------|-------------|
| ISRAM | — | Instruction SRAM (read-only, `$readmemh` init) |
| DSRAM | — | Data SRAM (read/write, zero-init) |
| UART | `0xFFFF0000` | UART TX/RX subordinate |
| Parallel MAC | `0xFFFE0000` | 4×4 PE grid accelerator |
| Systolic Array | `0xFFFD0000` | Output-stationary wavefront accelerator |

### M-Mode Exception Handling
Full trap/return pipeline: ECALL, illegal instruction, load/store misalign, external IRQ. CSR instructions CSRRW, CSRRS, CSRRC. MRET restores PC from mepc and re-enables interrupts.

### UART TX/RX
Memory-mapped at `0xFFFF0000` on the AXI4-Lite bus. 8-entry TX FIFO, 8N1 framing, status polling. RX path with 2-flop synchronizer, falling-edge start-bit detection, and IRQ output.

### Hardware PMU
8 read-only counters at `0xFFFF2000`:

| Offset | Counter |
|--------|---------|
| +0x00 | Cycle count |
| +0x04 | Instructions retired |
| +0x08 | Branches executed |
| +0x0C | Branch mispredictions |
| +0x10 | D$ hits |
| +0x14 | D$ misses |
| +0x18 | I$ hits |
| +0x1C | I$ misses |

### Custom SIMD Extensions
Seven instructions at RISC-V custom opcode `0001011`, operating on 32-bit registers as packed 4×8-bit vectors:

| Instruction | funct3 | Operation | Notes |
|-------------|--------|-----------|-------|
| `PADD rd, rs1, rs2` | 000 | `rd[i] = rs1[i] + rs2[i]` | 8-bit unsigned wrap |
| `PSUB rd, rs1, rs2` | 000 | `rd[i] = rs1[i] - rs2[i]` | funct7=0100000 |
| `PMUL rd, rs1, rs2` | 001 | `rd[i] = (rs1[i] × rs2[i])[7:0]` | Lower 8 bits |
| `PDOT rd, rs1, rs2` | 010 | `rd = Σ rs1[i] × rs2[i]` | 32-bit accumulation |
| `PMACC rd, rs1, rs2` | 011 | `rd = rd + PDOT(rs1, rs2)` | rd is src+dst; acc forwarded |
| `PSRA rd, rs1, shamt` | 100 | `rd[i] = rs1[i] >>> shamt` | shamt in funct7[3:0], signed lanes |
| `PRELU rd, rs1` | 101 | `rd[i] = max(0, rs1[i])` | Signed byte interpretation |

**PMACC** reads `rd` as a third source (accumulator), writes back `rd + PDOT(rs1, rs2)`. The register file has a dedicated third read port; the hazard unit and forward unit both handle the accumulator path independently from rs1/rs2.

### Hardware Accelerators

**Parallel MAC** (`0xFFFE0000`): 4×4 systolic PE grid where all 16 PEs fire in parallel each k-step. Computes a full 4×4 INT8 GEMM in 4 cycles. Supports:
- Tile-K accumulation (CTRL bit 1 preserves `c_acc` across passes for K > 4)
- Requantization: `saturate_uint8((c_acc >> scale_shift) + zero_point)`
- Raw INT32 readback at `0xFFFE0080–0xFFFE00BC`

**Systolic Array** (`0xFFFD0000`): Kung-Leiserson output-stationary wavefront. Compute latency 11 cycles (wavefront fill + drain). Same register map, accumulate mode, and requantization interface as the parallel MAC.

---

## Benchmark Results

4×4 INT8 GEMM (`make sim MODULE=matmul`), measured via hardware PMU:

| Version | Cycles | Instrs | CPI | Speedup |
|---------|--------|--------|-----|---------|
| Scalar (RV32M `mul`) | 1,065 | 841 | 1.266 | 1.00× |
| SIMD (`PDOT`) | 261 | 201 | 1.299 | 4.08× |
| Parallel MAC | 79 | — | — | 13.48× |
| Systolic Array | 87 | — | — | 12.24× |

**Scalar**: hardware `mul` (RV32M), 4×4 triple-nested loop. D$ hit rate 98.3%.  
**SIMD**: load-use stall before each PDOT eliminated by scheduling three independent C-address instructions into the stall slot. D$ hit rate 96.2%. 261−201=60 overhead cycles from branch mispredictions and cold cache.  
**Parallel MAC**: 4-cycle PE compute; remaining 75 cycles are AXI4-Lite register writes (4×4 A tiles, 4×4 B columns, CTRL).  
**Systolic Array**: 11-cycle wavefront fill/drain; 76 cycles AXI overhead. Higher CPU overhead than parallel MAC for single 4×4 tile because the wavefront must fully drain before results are valid.

---

## Memory Map

| Address | Description |
|---------|-------------|
| `0x00000000` | Instruction SRAM (via I$) |
| `0x00000000` | Data SRAM (via D$, separate Harvard path) |
| `0xFFFF0000` | UART TX/RX (AXI4-Lite subordinate) |
| `0xFFFF2000` | PMU counters (8 × 4B) |
| `0xFFFD0000` | Systolic Array registers |
| `0xFFFD0030` | Systolic SCALE_SHIFT (5-bit) |
| `0xFFFD0034` | Systolic ZERO_POINT (8-bit) |
| `0xFFFD0080` | Systolic C_INT32 readback (16 × 4B) |
| `0xFFFE0000` | Parallel MAC registers |
| `0xFFFE0030` | Parallel MAC SCALE_SHIFT |
| `0xFFFE0034` | Parallel MAC ZERO_POINT |
| `0xFFFE0080` | Parallel MAC C_INT32 readback (16 × 4B) |

---

## Project Structure

```
rv32i-core-cpu/
├── src/
│   ├── top_pipeline.sv              # 5-stage pipeline top level
│   ├── top.sv                       # Single-cycle top (regression baseline)
│   ├── program_counter.sv
│   ├── if_id_reg.sv
│   ├── id_ex_reg.sv                 # includes acc_data for PMACC
│   ├── ex_mem_reg.sv
│   ├── mem_wb_reg.sv
│   ├── register_file.sv             # 3 read ports (rs1, rs2, acc)
│   ├── alu.sv
│   ├── simd_alu.sv                  # PADD PSUB PMUL PDOT PMACC PSRA PRELU
│   ├── mul_div_unit.sv              # RV32M: MUL/DIV/REM
│   ├── control_unit.sv              # All RV32I+M+custom opcodes
│   ├── forward_unit.sv              # rs1/rs2/acc forwarding
│   ├── hazard_unit.sv               # load-use stall, PMACC acc stall
│   ├── branch_predictor.sv          # 2-bit BHT + BTB
│   ├── dcache.sv                    # 4KB direct-mapped WB/WA
│   ├── icache.sv                    # 4KB direct-mapped read-only
│   ├── axi4_lite_interconnect.sv    # 5M/5S address-decoded crossbar
│   ├── axi4_lite_icache_manager.sv
│   ├── axi4_lite_dcache_manager.sv
│   ├── axi4_lite_accel_manager.sv   # shared by both accelerators
│   ├── axi4_lite_io_manager.sv
│   ├── axi4_lite_sram_sub.sv        # parameterized SRAM subordinate
│   ├── axi4_lite_uart_sub.sv        # UART subordinate
│   ├── parallel_mac_sub.sv          # 4×4 PE grid, 4-cycle compute
│   ├── systolic_array_sub.sv        # Kung-Leiserson wavefront, 11-cycle
│   ├── uart_tx.sv
│   ├── uart_rx.sv
│   ├── uart_mem_map.sv
│   ├── csr_regfile.sv
│   ├── exception_unit.sv
│   └── perf_counters.sv
├── tb/
│   ├── tb_top_pipeline.sv           # Full pipeline integration
│   ├── tb_top.sv                    # Single-cycle regression
│   ├── tb_simd_alu.sv               # PADD/PSUB/PMUL/PDOT/PMACC/PSRA/PRELU
│   ├── tb_pmacc.sv                  # PMACC unit test (acc port isolation)
│   ├── tb_pmacc_pipeline.sv         # PMACC pipeline integration (all fwd paths)
│   ├── tb_parallel_mac.sv           # Accelerator: baseline, requant, K-tiling
│   ├── tb_systolic_array.sv         # Accelerator: same test suite at 0xFFFD
│   ├── tb_matmul.sv                 # 4-way benchmark (scalar/SIMD/pmac/systolic)
│   ├── tb_hazard_unit.sv
│   ├── tb_forward_unit.sv
│   ├── tb_dcache.sv
│   ├── tb_icache.sv
│   ├── tb_axi4_lite.sv
│   ├── tb_uart_rx.sv
│   ├── tb_uart_tx.sv (or tb_uart_mem_map.sv)
│   ├── tb_exception_test.sv
│   ├── tb_exception_handler_stack.sv
│   ├── tb_mul_div.sv
│   └── tb_perf_demo.sv
├── programs/
│   ├── test1.hex                    # Arithmetic, branch, loop
│   ├── test2.hex                    # Memory, logic, LUI
│   ├── exception_test.hex           # ECALL, MRET, CSR
│   ├── matmul_scalar.hex            # 4×4 INT8 GEMM, RV32M mul
│   ├── matmul_simd.hex              # 4×4 INT8 GEMM, PDOT
│   ├── matmul_systolic.hex          # 4×4 INT8 GEMM, systolic array
│   └── pmacc_test.hex               # PMACC forwarding paths test
└── Makefile
```

---

## Getting Started

### Prerequisites

```bash
# macOS
brew install icarus-verilog

# Ubuntu / WSL
sudo apt install iverilog
```

### Run all tests

```bash
make test-all
```

Expected: `33 passed   0 failed`

### Run individual module tests

```bash
make sim MODULE=simd_alu
make sim MODULE=pmacc
make sim MODULE=pmacc_pipeline
make sim MODULE=hazard_unit
make sim MODULE=forward_unit
make sim MODULE=dcache
make sim MODULE=icache
make sim MODULE=parallel_mac
make sim MODULE=systolic_array
make sim MODULE=mul_div
```

### Run the matrix multiply benchmark

```bash
make sim MODULE=matmul
```

Expected output (approximate):
```
Scalar:       1065 cycles   841 instrs   CPI=1.266   1.00x
SIMD:          261 cycles   201 instrs   CPI=1.299   4.08x
Parallel MAC:   79 cycles                            13.48x
Systolic:       87 cycles                            12.24x
```

### View waveforms

```bash
make wave MODULE=top_pipeline
make wave MODULE=pmacc_pipeline
```

---

## Verification

| Module | Tests | Status |
|--------|-------|--------|
| ALU | All RV32I operations | ✅ |
| MUL/DIV | RV32M MUL/MULH/DIV/REM variants | ✅ |
| Register file | 3-port read, x0 hardwired | ✅ |
| Control unit | All RV32I+M+custom opcodes | ✅ |
| Forward unit | EX/MEM, MEM/WB, acc (PMACC) | ✅ |
| Hazard unit | load-use, branch flush, PMACC acc stall | ✅ |
| SIMD ALU | PADD/PSUB/PMUL/PDOT/PMACC/PSRA/PRELU | ✅ |
| PMACC unit | acc=0, chain, large INT32 | ✅ |
| PMACC pipeline | All 4 forwarding paths end-to-end | ✅ |
| D$ cache | Miss, fill, writeback, bypass | ✅ |
| I$ cache | Miss, fill, invalidate | ✅ |
| Branch predictor | BHT update, BTB, mispredict flush | ✅ |
| AXI4-Lite fabric | 5M/5S routing, all subordinates | ✅ |
| Parallel MAC | Baseline, overflow, requant, K-tiling | ✅ |
| Systolic Array | Same suite at 0xFFFD | ✅ |
| UART TX/RX | 8N1 framing, FIFO, IRQ | ✅ |
| Exception handling | ECALL, MRET, illegal, IRQ, stack save/restore | ✅ |
| Performance counters | All 8 counters via PMU | ✅ |
| Single-cycle CPU | Regression baseline | ✅ |
| Pipelined CPU | test1, test2, exception, matmul | ✅ |
| **Total** | **33 testbenches** | **33/33** |

---

## Known Limitations

- **Direct-mapped caches** — conflict misses for working sets that alias to the same cache index. 2-way set associative is the natural next step.
- **Direct-mapped BTB** — 64 entries indexed by PC[7:2]; a new branch evicts the old entry at the same index. The tag check (PC[31:8]) prevents wrong-path redirects but cannot prevent a high-traffic entry from being evicted by a colliding PC.
- **No FPGA timing closure** — Yosys synthesis completes (3,900 LUTs of pipeline logic excluding memory arrays); place-and-route requires `(* ram_style = "block" *)` attributes for BRAM inference before the design fits an iCE40. Vivado/Quartus flows with BRAM attributes are expected to close at ~100–150 MHz on Artix-7. See `SYNTHESIS.md` for details.

---

## Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Icarus Verilog | 11+ | RTL simulation |
| GTKWave / Wavetrace | any | Waveform analysis |
| Yosys | 0.66 | Synthesis (see `SYNTHESIS.md`) |
| GNU Make | any | Build automation |
| Git | any | Version control |

---

*2nd year Computer Engineering — Toronto Metropolitan University*
