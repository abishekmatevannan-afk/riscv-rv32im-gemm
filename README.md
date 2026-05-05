# RV32I RISC-V CPU Core

A fully functional RV32I RISC-V processor implemented from scratch in SystemVerilog, featuring a 5-stage pipeline, hazard handling, memory-mapped UART peripheral, and custom SIMD extensions for packed arithmetic.

---

## Architecture Overview

---

## Features

### RV32I Base ISA
Full implementation of all 37 base integer instructions across all six instruction formats — R, I, S, B, U, and J types. Includes arithmetic, logical, shift, branch, jump, and memory load/store operations.

### 5-Stage Pipeline
Classic fetch-decode-execute-memory-writeback pipeline with full hazard handling:
- **Data forwarding** — EX/MEM and MEM/WB forwarding paths eliminate stalls for most data hazards
- **Load-use hazard detection** — automatic 1-cycle stall when a load result is needed immediately
- **Branch flush** — IF/ID and ID/EX registers flushed on taken branches to prevent incorrect execution

### Memory-Mapped UART
A memory-mapped UART peripheral accessible at base address `0xFFFF0000`. CPU assembly programs write characters directly to the TX register and poll the status register for readiness. Verified end-to-end by transmitting ASCII "HELLO" from CPU-executed code.

### Custom SIMD Extensions
Four custom instructions using RISC-V's reserved custom opcode space (`0001011`), operating on 32-bit registers as packed 4x8-bit vectors:

| Instruction | Operation | Description |
|-------------|-----------|-------------|
| PADD | `rd[i] = rs1[i] + rs2[i]` | Packed 8-bit add, 4 lanes |
| PSUB | `rd[i] = rs1[i] - rs2[i]` | Packed 8-bit subtract, 4 lanes |
| PMUL | `rd[i] = rs1[i] * rs2[i]` | Packed 8-bit multiply, lower 8 bits |
| PDOT | `rd = Σ rs1[i] * rs2[i]` | 4-element integer dot product |

PDOT maps directly to the multiply-accumulate operation at the core of neural network inference.

---

## Project Structure
rv32i-core/
├── src/
│   ├── alu.sv                # 32-bit ALU
│   ├── register_file.sv      # 32x32-bit register file, 2R/1W ports
│   ├── program_counter.sv    # PC with stall and branch support
│   ├── instruction_memory.sv # ROM, initialized from hex file
│   ├── data_memory.sv        # 1KB byte-addressable RAM
│   ├── control_unit.sv       # Instruction decoder, control signals
│   ├── simd_alu.sv           # Custom SIMD extension unit
│   ├── uart_tx.sv            # UART transmitter FSM, 8N1
│   ├── uart_mem_map.sv       # Memory-mapped UART interface
│   ├── if_id_reg.sv          # IF/ID pipeline register
│   ├── id_ex_reg.sv          # ID/EX pipeline register
│   ├── ex_mem_reg.sv         # EX/MEM pipeline register
│   ├── mem_wb_reg.sv         # MEM/WB pipeline register
│   ├── forward_unit.sv       # Forwarding path logic
│   ├── hazard_unit.sv        # Hazard detection and stall/flush
│   ├── top.sv                # Single-cycle top level
│   └── top_pipeline.sv       # Pipelined top level
├── tb/
│   ├── tb_alu.sv
│   ├── tb_register_file.sv
│   ├── tb_program_counter.sv
│   ├── tb_instruction_memory.sv
│   ├── tb_control_unit.sv
│   ├── tb_data_memory.sv
│   ├── tb_forward_unit.sv
│   ├── tb_hazard_unit.sv
│   ├── tb_simd_alu.sv
│   ├── tb_uart_tx.sv
│   ├── tb_uart_integration.sv
│   ├── tb_top.sv
│   └── tb_top_pipeline.sv
├── programs/
│   ├── test1.hex             # Arithmetic, branch, loop program
│   ├── test2.hex             # Memory load/store, logic, LUI
│   └── uart_hello.hex        # UART HELLO transmission program
└── Makefile

---

## Tools

| Tool | Purpose |
|------|---------|
| SystemVerilog | Hardware description language |
| Icarus Verilog | Open-source RTL simulator |
| Wavetrace / GTKWave | Waveform analysis |
| GNU Make | Build automation |
| Git | Version control |

---

## Building and Simulating

### Prerequisites
```bash
brew install icarus-verilog  # macOS
sudo apt install iverilog    # Ubuntu/WSL
```

### Run a specific module testbench
```bash
make sim MODULE=alu
make sim MODULE=register_file
make sim MODULE=control_unit
make sim MODULE=forward_unit
make sim MODULE=hazard_unit
make sim MODULE=simd_alu
make sim MODULE=uart_tx
```

### Run full CPU integration tests
```bash
make sim MODULE=top           # single-cycle
make sim MODULE=top_pipeline  # pipelined
```

### Run UART integration test
```bash
make sim MODULE=uart_integration
```

### View waveforms
```bash
make wave MODULE=alu
```

---

## Test Programs

### test1.hex — Arithmetic, Branch, Loop
```asm
addi x1, x0, 5        # x1 = 5
addi x2, x0, 10       # x2 = 10
add  x3, x1, x2       # x3 = 15
addi x4, x0, 5        # x4 = 5
addi x5, x0, 0        # x5 = 0 (accumulator)
addi x6, x0, 10       # x6 = 10 (loop counter)
loop:
add  x5, x5, x3       # x5 += 15
addi x6, x6, -1       # x6--
bne  x6, x0, loop     # repeat 10 times
# result: x5 = 150, x6 = 0
```

### test2.hex — Memory and Logic
Covers SW, LW, SH, LHU, LH, LBU, SLT, LUI, XOR, OR, AND across multiple registers and addresses.

### uart_hello.hex
Polls UART status register and transmits H, E, L, L, O, newline sequentially. Verified to produce correct ASCII output in simulation.

---

## Verification Status

| Module | Status |
|--------|--------|
| ALU | ✅ All operations verified |
| Register File | ✅ Dual-port read, x0 hardwired zero |
| Program Counter | ✅ Sequential, branch, jump, reset |
| Instruction Memory | ✅ Hex file load, word-aligned read |
| Control Unit | ✅ All opcodes, funct3, funct7 combinations |
| Data Memory | ✅ Byte, halfword, word R/W, sign extension |
| Forward Unit | ✅ EX/MEM and MEM/WB forwarding, priority |
| Hazard Unit | ✅ Load-use stall, branch flush, jump flush |
| SIMD ALU | ✅ PADD, PSUB, PMUL, PDOT |
| UART TX | ✅ 8N1 framing, all ASCII characters |
| UART Integration | ✅ End-to-end HELLO transmission |
| Single-cycle CPU | ✅ Both test programs passing |
| Pipelined CPU | ✅ Both test programs passing |

---

## What I Learned

Building this project from scratch in SystemVerilog taught me things that coursework alone didnt really cover. The single-cycle implementation was straightforward — the complications came in the pipeline. Getting forwarding right requires thinking precisely about which stage each value is in at every clock cycle. The load-use hazard is a good example of a case where forwarding alone isn't sufficient and you need to stall.

The UART peripheral taught me about the hardware/software interface aspect that I haven't been exposed to much, the main thing being how a CPU communicates with the outside world through memory-mapped registers and polling. The SIMD extension showed me how ML accelerators are fundamentally just chips that do packed multiply-accumulate very efficiently at scale.

---

## Future Work that should be done or I might do on a whim

- [ ] FPGA synthesis and hardware demo (any Vivado-compatible board)
- [ ] Digital oscilloscope peripheral using FPGA ADC
- [ ] Branch predictor (2-bit saturating counter)
- [ ] Instruction cache (direct-mapped)
- [ ] Performance counters (cycles, instructions retired, cache hits)