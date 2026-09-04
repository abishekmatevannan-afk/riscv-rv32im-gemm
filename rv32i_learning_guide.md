# Building a RISC-V CPU From Scratch
## A Complete Learning Guide: From Digital Logic to a Synthesized, Timed Pipelined Processor with Caches, Branch Prediction, SIMD, and Hardware Accelerators

**Author:** Abishek Matevannan — 2nd Year Computer Engineering, Toronto Metropolitan University
**Repository:** [github.com/abishekmatevannan-afk/rv32i-core-cpu](https://github.com/abishekmatevannan-afk/rv32i-core-cpu)

---

> **Who this is for:** This document starts from first principles and builds up to a complete, verified, industry-pattern CPU design. If you know what a logic gate is, you can follow this. If you are a recruiter or engineer reviewing this project, each section ends with a **Recruiter Note** explaining why a given design decision demonstrates real engineering judgment.

---

## Table of Contents

1. [What Is a CPU?](#1-what-is-a-cpu)
2. [The RISC-V ISA](#2-the-risc-v-isa)
3. [The Instruction Execution Cycle](#3-the-instruction-execution-cycle)
4. [Single-Cycle CPU Architecture](#4-single-cycle-cpu-architecture)
5. [The Register File](#5-the-register-file)
6. [The ALU](#6-the-alu)
7. [The Immediate Generator](#7-the-immediate-generator)
8. [The Control Unit](#8-the-control-unit)
9. [Instruction and Data Memory](#9-instruction-and-data-memory)
10. [Why Pipelining?](#10-why-pipelining)
11. [The 5-Stage Pipeline](#11-the-5-stage-pipeline)
12. [Pipeline Registers](#12-pipeline-registers)
13. [The Forwarding Unit](#13-the-forwarding-unit)
14. [The Hazard Unit](#14-the-hazard-unit)
15. [Branch Prediction](#15-branch-prediction)
16. [Cache Architecture](#16-cache-architecture)
17. [The AXI4-Lite Memory Fabric](#17-the-axi4-lite-memory-fabric)
18. [Exception Handling](#18-exception-handling)
19. [The UART Peripheral](#19-the-uart-peripheral)
20. [Custom SIMD Extensions](#20-custom-simd-extensions)
21. [Hardware Performance Counters](#21-hardware-performance-counters)
22. [Verification Strategy](#22-verification-strategy)
23. [Debugging: Real Bugs, Real Fixes — Simulation and Synthesis](#23-debugging-real-bugs-real-fixes--simulation-and-synthesis)
24. [Performance Analysis](#24-performance-analysis)
25. [FPGA Synthesis and Timing Closure](#25-fpga-synthesis-and-timing-closure)
26. [What to Build Next](#26-what-to-build-next)

---

## 1. What Is a CPU?

### The Core Idea

A CPU (Central Processing Unit) is a machine that reads instructions from memory, one at a time, and carries them out. Every instruction is a number — a 32-bit integer in this project — that encodes an operation like "add two numbers" or "store a value to memory" or "jump to a different part of the program."

At the most basic level, a CPU is a loop:

```
1. Read the next instruction from memory
2. Figure out what it means
3. Do it
4. Move to the next instruction
5. Repeat
```

Everything else — pipelining, caches, branch prediction, SIMD — is an optimization on top of this loop. None of it changes what the CPU does. It only changes how fast it does it.

### Why Build One?

Most engineers who work on CPUs never build one from scratch. They use existing cores, extend existing designs, or write RTL for a specific block (a cache, a floating-point unit, a bus interface). Building a complete CPU from scratch is the fastest way to develop intuition for:

- Why modern processors are so complex
- What actually causes performance bottlenecks
- How hardware and software interact at the instruction level
- How to debug RTL when signals are wrong and the cause is not obvious

This project implements a **RV32I RISC-V processor** — the same ISA used by SiFive cores, the ESP32-C3, and a growing number of industrial chips at companies including Western Digital, Esperanto Technologies, and RISC-V International member companies.

### Connecting to Real CPUs

The design in this project follows the same fundamental architecture as:

| Feature | This project | ARM Cortex-M0 | AMD Zen 4 |
|---------|-------------|---------------|-----------|
| ISA | RV32I | ARMv6-M | x86-64 |
| Pipeline stages | 5 | 3 | ~20 |
| L1 icache | 4KB direct-mapped | 8KB 2-way | 32KB 8-way |
| L1 dcache | 4KB direct-mapped | none | 32KB 8-way |
| Branch predictor | 2-bit BHT + BTB | static | TAGE-SC-L hybrid |
| Exception handling | M-mode | present | ring 0–3 |

The concepts are identical. The scale is different.

> **Recruiter Note:** Candidates who have built a complete CPU understand tradeoffs that candidates who have only used CPUs do not. This project demonstrates register-transfer-level design, hazard reasoning, memory hierarchy design, bus protocol implementation, and systematic hardware verification — all in one codebase.

---

### Interview Questions — Section 1

**Q: What is the difference between a CPU and a microcontroller?**
A: A microcontroller is a CPU plus integrated peripherals (timers, UART, GPIO, ADC) on a single chip. A CPU is just the processor core. The Cortex-M0 is a CPU; the STM32F103 is a microcontroller built around it.

**Q: What does "32-bit CPU" mean?**
A: The general-purpose registers are 32 bits wide, memory addresses are 32 bits, and the ALU operates on 32-bit integers by default. It does not mean instructions are 32 bits wide — though in RV32I they happen to be.

---

## 2. The RISC-V ISA

### What Is an ISA?

An Instruction Set Architecture (ISA) is the contract between hardware and software. It defines what instructions exist, what registers are available, how memory is addressed, and what happens on exceptions. Software is compiled to an ISA. Hardware implements that ISA. The two never need to know about each other's internals.

RISC-V is an open, modular ISA developed at UC Berkeley. The base integer extension is called **RV32I** — 32-bit registers, integer operations only. Additional extensions (M for multiply, F for float, A for atomics, V for vector) can be added independently.

### Why RISC-V?

| ISA | License | Designed for | Common in |
|-----|---------|-------------|-----------|
| x86-64 | Intel/AMD proprietary | High performance desktop/server | PCs, servers |
| ARMv8 | ARM Ltd license fee | Power-efficient mobile/embedded | Phones, tablets, Raspberry Pi |
| RISC-V | Open, royalty-free | Education, custom silicon | Academic, industrial custom chips |
| MIPS | Covered by patents | Education (historically) | Older textbooks |

RISC-V is the right choice for this project because it is simple, free, and real. Real chips are being built on it. Real compilers target it. Verification tools support it.

### Registers

RV32I has 32 general-purpose registers, each 32 bits wide. Register x0 is hardwired to zero — writes are silently discarded, reads always return 0. This simplifies instruction encoding significantly (branch to PC=PC+0 becomes `beq x0, x0, 0`, no special NOP encoding needed).

```
x0  = 0 (hardwired)      x16 = s0  (saved)
x1  = ra (return address) x17 = s1
x2  = sp (stack pointer)  x18 = a0  (function argument / return value)
x3  = gp (global pointer) x19 = a1
x4  = tp (thread pointer)  ...
x5  = t0 (temporary)      x27 = a7
x6  = t1                  x28 = s2  (saved, callee-preserved)
...                        ...
x15 = t5                  x31 = t6
```

The ABI names (ra, sp, a0, etc.) are calling convention, not hardware. The hardware sees only x0–x31.

### Instruction Formats

All RV32I instructions are exactly 32 bits wide. The instruction type determines how those 32 bits are decoded:

```
R-type: [funct7][rs2][rs1][funct3][rd][opcode]   — register-register ops
I-type: [  imm[11:0]  ][rs1][funct3][rd][opcode]  — immediate, loads, JALR
S-type: [imm[11:5]][rs2][rs1][funct3][imm[4:0]][opcode] — stores
B-type: [imm[12,10:5]][rs2][rs1][funct3][imm[4:1,11]][opcode] — branches
U-type: [      imm[31:12]        ][rd][opcode]   — LUI, AUIPC
J-type: [  imm[20,10:1,11,19:12]  ][rd][opcode]  — JAL
```

The opcode field (`[6:0]`) identifies the instruction family. `funct3` and `funct7` discriminate within a family. The immediate fields are split and scattered across the instruction word — this is intentional. It keeps rs1, rs2, and rd at fixed positions in every instruction type, which simplifies the hardware decoder.

### The Six Instruction Types With Examples

**R-type (register-register):**
`add x3, x1, x2` — x3 = x1 + x2. Encoding: `funct7=0, rs2=x2, rs1=x1, funct3=000, rd=x3, opcode=0110011`

**I-type (immediate):**
`addi x1, x0, 5` — x1 = x0 + 5 = 5. The 12-bit immediate is sign-extended to 32 bits before use.
`lw x1, 4(x2)` — x1 = mem[x2 + 4]. Same format, different opcode.

**S-type (store):**
`sw x1, 4(x2)` — mem[x2 + 4] = x1. The immediate is split: `imm[11:5]` in `[31:25]` and `imm[4:0]` in `[11:7]`. Why? To keep rs1 and rs2 at the same positions as in R-type.

**B-type (branch):**
`beq x1, x2, 8` — if x1 == x2, PC = PC + 8. The immediate encodes a byte offset in multiples of 2. The bit layout is deliberately scrambled to keep rs1 and rs2 at fixed positions.

**U-type (upper immediate):**
`lui x1, 0xABCDE` — x1 = 0xABCDE000. Loads a 20-bit immediate into the upper 20 bits. Used to build 32-bit constants when combined with ADDI.

**J-type (jump):**
`jal x1, 100` — x1 = PC + 4 (return address), PC = PC + 100.

> **Recruiter Note:** Understanding instruction encoding at the bit level is a prerequisite for writing an assembler, a disassembler, a debugger, or a hardware decoder. This project required encoding test programs by hand in hex, which required exactly this knowledge.

---

### Interview Questions — Section 2

**Q: Why does RISC-V split the B-type immediate across non-contiguous bit fields?**
A: To keep rs1 and rs2 at positions [19:15] and [24:20] across all instruction types. This means the register file read ports can always be connected to the same bits regardless of instruction type, simplifying the datapath.

**Q: Why is x0 hardwired to zero?**
A: It eliminates the need for special NOP encodings, simplifies comparison instructions (compare with zero = compare with x0), and allows instructions that do not produce a result (stores, branches) to write their unused rd field to x0 harmlessly.

**Q: How many bytes does `lw x1, 4(x2)` load?**
A: 4 bytes (one word). The `w` in `lw` is for "word." `lh` loads a halfword (2 bytes), `lb` loads a byte.

---

## 3. The Instruction Execution Cycle

### Five Operations Every Instruction Performs

Every instruction, regardless of type, goes through some or all of these five operations:

1. **Fetch (IF):** Read the instruction word from instruction memory at the address in the Program Counter (PC). Increment PC by 4.

2. **Decode (ID):** Break the 32-bit instruction into its fields (opcode, rs1, rs2, rd, funct3, funct7, immediate). Read rs1 and rs2 from the register file. Generate control signals.

3. **Execute (EX):** Perform the computation. For arithmetic instructions: run the ALU. For memory instructions: compute the address. For branches: evaluate the condition.

4. **Memory (MEM):** For loads: read from data memory. For stores: write to data memory. For everything else: pass the result through.

5. **Writeback (WB):** Write the result to the destination register (rd).

### Walking Through `add x3, x1, x2`

| Step | What happens |
|------|-------------|
| IF | Read instruction at PC. Instruction = `0x002081B3`. PC becomes PC+4. |
| ID | Decode: opcode=0110011 (R-type ALU), rs1=x1, rs2=x2, rd=x3, funct3=000, funct7=0 → ADD operation. Read x1=5, x2=10 from register file. |
| EX | ALU computes 5 + 10 = 15. |
| MEM | No memory access. Result passes through. |
| WB | Write 15 to x3. |

### Walking Through `lw x5, 8(x3)`

| Step | What happens |
|------|-------------|
| IF | Fetch instruction. |
| ID | Decode: opcode=0000011 (load), funct3=010 (LW), rs1=x3, rd=x5, imm=8. Read x3=100. |
| EX | ALU computes address: 100 + 8 = 108. |
| MEM | Read 4 bytes from data memory at address 108. |
| WB | Write the loaded value to x5. |

---

## 4. Single-Cycle CPU Architecture

### The Design Philosophy

The simplest possible CPU executes one complete instruction per clock cycle. Every clock cycle, all five operations happen in sequence through combinational logic. The clock simply marks when state elements (the register file, PC, memory) capture their new values.

```
         ┌──────┐   ┌──────┐   ┌──────┐   ┌────────┐   ┌────┐
 PC ───► │  IF  │──►│  ID  │──►│  EX  │──►│  MEM   │──►│ WB │──► RF
         └──────┘   └──────┘   └──────┘   └────────┘   └────┘
                    (combinational logic — no registers between stages)
         ◄──────────────────── one clock cycle ────────────────────►
```

This works. `top.sv` in this project is a verified single-cycle RV32I implementation. Every test passes. But there is a fundamental performance problem.

### The Clock Frequency Problem

In a single-cycle CPU, the clock period must be long enough for the slowest instruction to complete. The slowest instruction is `lw` — it must fetch from instruction memory, decode, compute an address, read from data memory, and write back. If each stage takes 1ns, the clock period must be at least 5ns → 200MHz maximum.

But most instructions do not need data memory access. `add` only needs decode, execute, and writeback — 3ns of work. A single-cycle CPU forces `add` to wait the full 5ns clock cycle anyway. The CPU is idle for 2ns every add instruction.

Pipelining solves this by overlapping instruction execution. While one instruction is in the memory access stage, the next instruction is already being executed, and the one after that is being decoded. Five instructions in flight simultaneously. Throughput approaches one instruction per clock cycle.

### Why Keep the Single-Cycle Implementation?

`top.sv` is kept in the repository as a **regression baseline**. Whenever the pipelined CPU produces a wrong result, the single-cycle version can run the same program. If the single-cycle version also fails, the bug is in the instruction encoding or the test program. If only the pipelined version fails, the bug is in the pipeline logic. This binary diagnostic has saved significant debugging time.

> **Recruiter Note:** Keeping a verified reference implementation and using it for regression testing is standard professional practice. It is not the first thing a student thinks to do.

---

### Interview Questions — Section 4

**Q: What limits the clock frequency of a single-cycle CPU?**
A: The critical path — the longest combinational delay from any input to any output within one cycle. For a single-cycle CPU with data memory, this is typically the load instruction path: PC → IMEM → decode → ALU → DMEM → mux → register file write.

**Q: If a single-cycle CPU runs at 100MHz, what is its throughput in MIPS?**
A: 100 MIPS (100 million instructions per second), since it completes exactly one instruction per cycle.

---

## 5. The Register File

### Purpose

The register file is the CPU's fast scratchpad. It holds 32 values, each 32 bits wide. Most instructions read their operands from here and write their results back here. All computation happens on registers — you cannot add two memory locations directly without loading them into registers first.

### Design

The register file has two read ports and one write port, operating simultaneously:

```systemverilog
module register_file (
    input  logic        clk,
    input  logic [4:0]  rs1_addr, rs2_addr,  // read addresses
    input  logic [4:0]  rd_addr,             // write address
    input  logic [31:0] rd_data,             // write data
    input  logic        reg_we,              // write enable
    output logic [31:0] rs1_data, rs2_data   // read data
);
    logic [31:0] regs [31:0];
    
    // Synchronous write
    always_ff @(posedge clk)
        if (reg_we && rd_addr != 5'b0)
            regs[rd_addr] <= rd_data;
    
    // Asynchronous read
    assign rs1_data = (rs1_addr == 0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'b0 : regs[rs2_addr];
endmodule
```

Three decisions worth explaining:

**Synchronous write, asynchronous read.** Writes happen on the rising clock edge. Reads are combinational — the output changes immediately when the address changes. This means a read in the same cycle as a write to the same address sees the OLD value (before the write). This is the write-before-read hazard, handled by the forwarding unit.

**x0 is hardwired to zero.** The write enable check `rd_addr != 5'b0` prevents writes to x0. The read check returns 0 for address 0 regardless of what is stored there. This is not a special register — it is just the convention that address 0 always reads 0.

**Write-before-read forwarding at the ID stage.** In the pipeline, if an instruction in the WB stage is writing to a register that the instruction currently in ID is reading, the ID stage must get the new value, not the register file value. The register file includes a forwarding path:

```systemverilog
assign id_rs1_data_fwd = (wb_reg_we && wb_rd_addr != 0 && wb_rd_addr == id_rs1_addr)
                       ? wb_data : rs1_data;
```

This is separate from the main forwarding unit (which handles EX and MEM stage hazards).

> **Recruiter Note:** The subtle distinction between the register file's WB-to-ID forwarding and the forwarding unit's EX/MEM-to-EX forwarding is something many students conflate. Getting both right simultaneously requires precise cycle-by-cycle pipeline reasoning.

---

### Interview Questions — Section 5

**Q: Why are register file reads asynchronous in this design?**
A: Because registers are read in the ID stage, and their values need to be available by the end of the ID stage (to be captured in the ID/EX register). If reads were synchronous, they would add a full clock cycle of latency, increasing the pipeline depth unnecessarily.

**Q: What happens if you write to x0?**
A: The hardware silently discards the write. The `reg_we && rd_addr != 0` check prevents it.

---

## 6. The ALU

### Purpose

The ALU (Arithmetic Logic Unit) performs all computation in the EX stage: arithmetic, logic, shifts, and comparisons. For memory instructions, it computes the address. For branches, it computes the comparison result.

### Operations

The ALU supports all operations required by RV32I:

| Operation | Description | Instruction(s) |
|-----------|-------------|----------------|
| ADD | a + b | ADD, ADDI, LW, SW, JAL, JALR |
| SUB | a - b | SUB |
| AND | a & b | AND, ANDI |
| OR | a \| b | AND, ORI |
| XOR | a ^ b | XOR, XORI |
| SLL | a << b[4:0] | SLL, SLLI |
| SRL | a >> b[4:0] (logical) | SRL, SRLI |
| SRA | a >>> b[4:0] (arithmetic) | SRA, SRAI |
| SLT | a < b (signed) ? 1 : 0 | SLT, SLTI |
| SLTU | a < b (unsigned) ? 1 : 0 | SLTU, SLTIU |
| LUI | b (pass through) | LUI |

### The Branch-ALU Connection

For branches, the ALU computes the comparison. `BEQ` computes `a - b` and checks for zero. `BLT` checks the sign bit of `a - b`. This reuses the ALU without additional hardware. The branch condition result feeds into the hazard unit to determine if a flush is needed.

### Arithmetic Right Shift vs Logical Right Shift

This is a common interview question. Logical right shift (`SRL`) fills vacated high bits with 0. Arithmetic right shift (`SRA`) replicates the sign bit. `-4 >> 1 = 0xFFFFFFFE` (SRA) vs `0x7FFFFFFE` (SRL). In SystemVerilog: `$signed(a) >>> shamt` for SRA.

---

## 7. The Immediate Generator

### The Problem

Different instruction types encode their immediate fields in different bit positions. An `I-type` immediate is in `[31:20]`. An `S-type` immediate is split between `[31:25]` and `[11:7]`. A `B-type` immediate has its bits scrambled to keep rs1/rs2 at fixed positions. All of this needs to be assembled into a coherent 32-bit signed value before use.

### The Solution

```systemverilog
always_comb begin
    case (opcode)
        7'b0010011,  // I-type ALU
        7'b0000011,  // Loads
        7'b1100111:  // JALR
            imm_out = {{20{instr[31]}}, instr[31:20]};
        
        7'b0100011:  // S-type (stores)
            imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        
        7'b1100011:  // B-type (branches)
            imm_out = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};
        
        7'b0110111,  // U-type (LUI)
        7'b0010111:  // U-type (AUIPC)
            imm_out = {instr[31:12], 12'b0};
        
        7'b1101111:  // J-type (JAL)
            imm_out = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};
        
        default: imm_out = 32'b0;
    endcase
end
```

The critical insight is sign extension: `{{20{instr[31]}}, ...}` replicates the sign bit 20 times. All immediates are sign-extended to 32 bits before use. This is not optional — it is required for negative offsets to work correctly.

### The B-type Immediate Bug

A real bug in this project involved encoding a B-type immediate incorrectly by hand. The branch `beq x5, x0, -8` was encoded as `FE028463` instead of `FE028CE3`. The wrong encoding gave `imm[11] = 0` instead of `imm[11] = 1`, producing an offset of -2072 instead of -8. The CPU jumped to address `0xFFFFF818`, hit an undefined instruction, and looped in the trap handler forever.

**Lesson:** Always manually verify branch encodings. The B-type immediate field layout is:
```
inst[31]    = imm[12]   ← sign bit
inst[30:25] = imm[10:5]
inst[11:8]  = imm[4:1]
inst[7]     = imm[11]   ← THIS IS EASY TO FORGET
imm[0] = 0 always (branches are 2-byte aligned)
```

---

## 8. The Control Unit

### Purpose

The control unit reads the instruction and produces all the control signals that configure the datapath. It is a decoder — purely combinational logic, no state. Given a 32-bit instruction, it outputs a set of 1-bit and 3-bit signals that tell every other module what to do.

### Key Control Signals

| Signal | Width | Meaning |
|--------|-------|---------|
| `reg_we` | 1 | Write result to rd |
| `mem_we` | 1 | Write to data memory |
| `mem_re` | 1 | Read from data memory |
| `alu_src` | 1 | 0=register, 1=immediate for ALU second input |
| `wb_sel` | 2 | 00=ALU, 01=load data, 10=PC+4, 11=CSR |
| `branch` | 1 | Instruction is a branch |
| `jump` | 1 | Instruction is JAL/JALR |
| `alu_ctrl` | 4 | Which ALU operation to perform |
| `funct3` | 3 | Load/store width, branch type |

### The SYSTEM Instruction Bug

A critical bug: extracting `funct12` from `instr[11:0]` instead of `instr[31:20]`.

RISC-V SYSTEM instructions (ECALL, EBREAK, MRET, all CSR instructions) use I-type encoding. The sub-opcode that distinguishes ECALL (0x000) from EBREAK (0x001) from MRET (0x302) lives in `instr[31:20]` — the I-type immediate field. `instr[11:0]` contains the opcode and rd fields, not the discriminator.

The symptom: every SYSTEM instruction decoded as "illegal instruction," the trap handler fired with mcause=2 (illegal instruction) on every ECALL, and MRET jumped to garbage addresses because `mtvec` was written to CSR address `0x073` instead of `0x305`.

**Fix:** `assign funct12 = instr[31:20];`

**Lesson:** Always check the RISC-V spec for which bits encode what in SYSTEM instructions. They look like I-type instructions but the immediate field carries the CSR address, not a data value.

---

## 9. Instruction and Data Memory

### Instruction Memory

The instruction memory is a read-only word-organized array initialized from a hex file. It is accessed by the icache (and in the single-cycle version, directly).

```systemverilog
initial begin
    // Count lines first to avoid $readmemh overflow warnings
    $fopen and $fgets loop to count line_count
    $readmemh(HEX_FILE, mem, 0, line_count - 1);
end
assign instr = mem[addr[31:2]]; // word-aligned access
```

The `addr[31:2]` index converts a byte address to a word index. PC is always a multiple of 4 (instructions are word-aligned in RV32I), so `addr[1:0]` is always `2'b00`.

### Data Memory

The data memory supports byte, halfword, and word accesses with sign and zero extension:

```
LBU:  {24'b0, mem[addr]}                   — zero-extended byte
LB:   {{24{mem[addr][7]}}, mem[addr]}       — sign-extended byte
LHU:  {16'b0, mem[addr+1], mem[addr]}      — zero-extended halfword
LH:   {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]} — sign-extended halfword
LW:   mem[addr+3], mem[addr+2], mem[addr+1], mem[addr] — full word
```

Note the byte ordering: RISC-V is **little-endian**. The byte at the lowest address is the least significant byte. `mem[addr]` is bits `[7:0]` of the loaded word.

### After AXI4-Lite Integration

In the pipelined implementation, instruction memory and data memory are replaced by an AXI4-Lite fabric connecting to ISRAM (32KB) and DSRAM (256KB). The caches sit between the pipeline and the fabric, providing fast access with a hardware-managed backing store. This is covered in Section 17.

---

## 10. Why Pipelining?

### The Throughput vs Latency Distinction

Pipelining increases **throughput** (instructions completed per second) without decreasing **latency** (time to complete one instruction). In fact, pipelining slightly increases latency because pipeline register setup time is added. But for programs that run millions of instructions, throughput is what matters.

### The Laundry Analogy

Imagine doing four loads of laundry sequentially: wash A, dry A, fold A, put away A. Then wash B, dry B... This takes 4 × 4 = 16 steps for 4 loads.

Now pipeline it: wash A, then (dry A, wash B), then (fold A, dry B, wash C), then (put away A, fold B, dry C, wash D). After the pipeline fills, one load completes every step instead of every four steps. This is pipelining.

The CPU equivalent:
```
Sequential (single-cycle):
Cycle 1: [IF A] [ID A] [EX A] [MEM A] [WB A]
Cycle 2: [IF B] [ID B] [EX B] [MEM B] [WB B]
...

Pipelined:
Cycle 1: [IF A]
Cycle 2: [IF B] [ID A]
Cycle 3: [IF C] [ID B] [EX A]
Cycle 4: [IF D] [ID C] [EX B] [MEM A]
Cycle 5: [IF E] [ID D] [EX C] [MEM B] [WB A]  ← pipeline full, 1 instr/cycle
```

### The Clock Frequency Benefit

A single-cycle CPU with 5 stages of 1ns each runs at 200MHz. A pipelined CPU with the same 5 stages runs at 1/1ns = 1GHz — but now each stage takes 1ns independently. Five times more instructions complete per second.

In practice, the benefit is smaller because not every stage takes the same time, pipeline registers add overhead, and hazards reduce effective throughput. But measured CPI for this project is 1.419 for a real benchmark — very close to the theoretical optimum of 1.0 for a 5-stage pipeline.

---

## 11. The 5-Stage Pipeline

### Stage Responsibilities

```
┌──────────────────────────────────────────────────────────────────────┐
│  IF: Instruction Fetch                                               │
│  ├── Program counter drives instruction address                      │
│  ├── I-cache returns instruction (or stalls on miss)                 │
│  └── Branch predictor outputs predicted_taken, predicted_target      │
├──────────────────────────────────────────────────────────────────────┤
│  ID: Instruction Decode                                              │
│  ├── Control unit decodes opcode → control signals                   │
│  ├── Immediate generator assembles immediate                         │
│  ├── Register file reads rs1, rs2                                    │
│  └── WB-to-ID forwarding (if WB is writing rs1 or rs2 this cycle)   │
├──────────────────────────────────────────────────────────────────────┤
│  EX: Execute                                                         │
│  ├── Forwarding unit selects correct operand values                  │
│  ├── ALU or SIMD ALU performs computation                            │
│  ├── Branch: evaluate condition, compare to prediction               │
│  ├── CSR: read/write control/status registers                        │
│  └── Exception unit: detect ECALL, illegal instruction, IRQ         │
├──────────────────────────────────────────────────────────────────────┤
│  MEM: Memory Access                                                  │
│  ├── D-cache: load or store (with stall on miss)                     │
│  ├── IO decode: route UART/PMU accesses around D-cache               │
│  └── Read data mux: cache vs UART vs PMU                             │
├──────────────────────────────────────────────────────────────────────┤
│  WB: Writeback                                                       │
│  ├── Select write data: ALU result, load data, PC+4, or CSR value   │
│  └── Write to register file                                          │
└──────────────────────────────────────────────────────────────────────┘
```

### The pc_next Priority Chain

The program counter update is controlled by a priority chain. Multiple things can want to change the PC simultaneously — a branch mispredict, an exception, a jump instruction. The priority from highest to lowest:

```systemverilog
assign pc_next =
    trap    ? mtvec_out         :  // exception: jump to trap vector
    ex_mret ? mepc_out          :  // MRET: return from trap
    ex_jump ? ex_pc_jump        :  // JAL/JALR: unconditional jump
    mispredict ? (ex_branch_taken ? ex_pc_branch : ex_pc_plus4) :  // correction
    bp_predict_taken ? bp_predict_target :  // branch prediction
    if_pc_plus4;                   // normal sequential fetch
```

This priority must be correct. If a trap fires during a mispredicted branch, the trap must win — otherwise the CPU will resume at the wrong address after the trap handler.


---

## 12. Pipeline Registers

### What They Are

Pipeline registers are flip-flops that sit between each stage. At every rising clock edge, each register captures the outputs of the stage before it. This is what makes the pipeline work: stage N can be processing instruction K while stage N+1 processes instruction K-1, because the register between them holds K-1's results safely while K advances.

### Every Pipeline Register Needs Three Behaviors

```systemverilog
always_ff @(posedge clk) begin
    if (rst || flush)
        // Stage content becomes NOP (zero everything)
    else if (!stall)
        // Capture this cycle's inputs
    else
        // Hold current value (freeze in place)
end
```

**Reset/flush:** Clears the register to all zeros. A zeroed pipeline register produces a NOP — an instruction that does nothing. This is how branch mispredictions are handled: flush the IF/ID and ID/EX registers, injecting two NOPs to cancel the wrongly-fetched instructions.

**Stall:** Holds the current value, preventing the stage from advancing. This is how cache misses are handled: the instruction stays in MEM while the cache fills.

**Capture:** Normal operation. Latch the stage's outputs.

### A Critical Bug: Missing Stall on ID/EX

One of the first pipeline bugs in this project: the ID/EX register had `if (rst || flush) zero; else begin latch; end` — no stall logic. The `else begin` always advanced the register, even during a cache stall. The instruction in MEM would wait, but the instruction in ID/EX would keep advancing, overwriting the stalled MEM instruction.

**Fix:** `else if (!stall) begin latch; end`

**Lesson:** Every pipeline register needs explicit stall gating. There are no exceptions. Leaving one register without stall support causes instructions to disappear mid-stall.

### Signal Naming Convention

All signals carry their stage prefix through the pipeline:

```
if_pc → (IF/ID) → id_pc → (ID/EX) → ex_pc → (EX/MEM) → mem_pc
```

This naming makes it easy to trace a value through the pipeline in waveforms. When debugging, search for `id_` to see what the ID stage is working on, `ex_` for EX, and so on.

---

## 13. The Forwarding Unit

### The Problem

Consider this sequence:
```asm
add  x1, x2, x3   # writes x1
add  x4, x1, x5   # reads x1 — hazard!
```

After the first `add`, the result of `x1` is not in the register file yet — it is in the EX/MEM pipeline register (heading to WB in two more cycles). If the second `add` reads x1 from the register file, it reads the stale pre-`add` value.

Without forwarding, the CPU would need to insert two stall cycles between these instructions. With forwarding, the EX/MEM register's value is forwarded directly to the second instruction's ALU input in the same cycle that the second instruction is in EX.

### The Two Forwarding Paths

**EX/MEM to EX (MEM forwarding):**
When the instruction in EX/MEM is writing a register that the instruction currently in EX is reading, bypass the register file and use `mem_alu_result` directly.

**MEM/WB to EX (WB forwarding):**
When the instruction in MEM/WB is writing a register that the instruction in EX is reading, use `wb_data`.

```systemverilog
// EX/MEM forwarding (takes priority)
if (mem_reg_we && mem_rd_addr != 0 && mem_rd_addr == ex_rs1_addr)
    forward_a = 2'b10;  // use mem_alu_result
// MEM/WB forwarding
else if (wb_reg_we && wb_rd_addr != 0 && wb_rd_addr == ex_rs1_addr)
    forward_a = 2'b01;  // use wb_data
// No forwarding needed
else
    forward_a = 2'b00;  // use register file value
```

**Why EX/MEM takes priority:** If both stages are writing the same register, EX/MEM has the newer value. This happens when two consecutive instructions both write the same register — you want the result of the more recent one.

### The Load-Use Hazard: When Forwarding Is Not Enough

```asm
lw   x1, 0(x2)    # load: result not available until END of MEM
add  x3, x1, x4   # needs x1 at START of EX — one cycle too early
```

A load instruction's result is not available at the end of EX — it is only available at the end of MEM, after the data cache returns the loaded value. Forwarding from MEM to EX cannot work for a load: the data the EX stage needs does not exist yet when the following instruction is in EX.

The solution: **stall for one cycle**. The hazard unit detects when the instruction in EX is a load and the instruction in ID reads the same register. It freezes the PC and IF/ID register for one cycle, inserts a bubble into ID/EX, and lets the load advance to MEM. On the next cycle, the load's data is available in MEM/WB, and the following instruction can now get it via the WB forwarding path.

---

## 14. The Hazard Unit

### What It Controls

The hazard unit is the traffic controller of the pipeline. It decides when to freeze stages (stall) and when to cancel instructions (flush).

```
Outputs:
  pc_stall      — freeze the program counter
  if_id_stall   — freeze the IF/ID register
  if_id_flush   — clear the IF/ID register (inject NOP)
  id_ex_stall   — freeze the ID/EX register
  id_ex_flush   — clear the ID/EX register (inject NOP)
  ex_mem_stall  — freeze the EX/MEM register
  mem_wb_stall  — freeze the MEM/WB register
```

### The Four Hazard Cases

**1. Load-use hazard:**
When a load is in EX and the next instruction reads the loaded register:
```
Stall: pc, if_id, id_ex
Flush: id_ex (inject bubble after stall releases)
```

**2. Branch misprediction:**
When EX determines the branch prediction was wrong:
```
Flush: if_id, id_ex  (cancel the two wrongly-fetched instructions)
```

**3. D-cache miss:**
When the data cache is filling or writing back:
```
Stall: ALL FIVE STAGES — pc, if_id, id_ex, ex_mem, mem_wb
Suppress flushes during the stall
```
Why all five? The instruction in MEM must keep presenting the same address to the cache. If EX/MEM advances, the address changes. If MEM/WB advances, the WB stage writes garbage (the cache output is 0 during fill).

**4. I-cache miss:**
When the instruction cache is filling:
```
Stall: pc, if_id only
Flush (bubble insert): id_ex every stall cycle
```
Why only IF/ID? The instructions behind the cache miss are valid and must complete. Only the instruction being fetched is waiting.

### The Critical Distinction: I-Cache vs D-Cache Stall

This is one of the most subtle bugs in this project. Initially, the I-cache stall froze all five stages (same as D-cache). This caused a failure when a load-use stall and an I-cache miss fired simultaneously.

The load-use stall flushed ID/EX (replaced the load with a NOP). The I-cache stall froze EX/MEM, preventing the load from advancing from EX to MEM. The load was in EX for one cycle, flushed to NOP, and never reached MEM. The register it was supposed to write retained its reset value of 0.

**The rule:**
- D-cache miss = freeze everything (the instruction in MEM is the one waiting)
- I-cache miss = freeze only IF/ID (the instruction in IF is the one waiting; EX/MEM/WB are valid and must drain)

### Suppressing Flushes During D-Cache Stall

Another subtle bug: during a D-cache stall, the EX/MEM register is frozen. If the frozen instruction happened to be a branch, `ex_branch` stays high every frozen cycle. Without suppression, `if_id_flush` fires every stall cycle, repeatedly canceling instructions that should not be canceled.

**Fix:** `assign if_id_flush = control_hazard && !cache_stall;`

During a cache stall, the pipeline is frozen solid — no flushes should fire.

> **Recruiter Note:** The hazard unit is where the vast majority of pipeline bugs live. A candidate who can explain the different stall requirements for I-cache vs D-cache miss, and why flush suppression is needed during D-cache stalls, has done real pipeline debugging — not just followed a textbook.

---

### Interview Questions — Sections 11–14

**Q: What is the difference between a stall and a flush?**
A: A stall holds the pipeline register at its current value — the instruction stays where it is. A flush replaces the pipeline register contents with zeros — the instruction is canceled (replaced by a NOP).

**Q: Why does a load-use hazard require a stall but an add-use hazard does not?**
A: An add's result is available at the end of EX and can be forwarded to the next instruction's EX via the EX/MEM forwarding path. A load's result is not available until the end of MEM (after the data cache returns the value), which is one cycle too late for the next instruction's EX stage.

**Q: If the branch predictor is disabled, how many cycles does a taken branch cost?**
A: Two cycles. The branch resolves in EX. Two instructions have been fetched since the branch (in IF and ID). Both must be flushed, inserting two NOPs.

---

## 15. Branch Prediction

### Why Branches Are Expensive

In a 5-stage pipeline, by the time a branch instruction reaches EX (where the comparison happens and the target address is computed), two more instructions have already been fetched and are in the ID and IF stages. If the branch is taken, those two instructions are wrong — they were fetched sequentially, not from the branch target. They must be flushed, costing 2 cycles per misprediction.

A typical program has a branch every 5–7 instructions. Without prediction (always predict not-taken), a loop that runs 100 times mispredicts 100 times (once on exit for not-taken prediction, and 100 times if always-not-taken). That is 200 wasted cycles from one loop.

### 2-Bit Saturating Counter

Instead of predicting "always not-taken," the predictor tracks the history of each branch. A 2-bit counter per branch entry counts from 0 (strongly not-taken) to 3 (strongly taken):

```
  00 (strongly NT) ──taken──► 01 (weakly NT) ──taken──► 10 (weakly T) ──taken──► 11 (strongly T)
                   ◄─not─────                ◄─not─────                ◄─not─────
```

A 2-bit counter (vs 1-bit) adds hysteresis: a loop that runs 100 times and exits once will be in state 11 (strongly taken). When the exit happens (branch not taken), the counter moves to 10 (weakly taken), not to 00. If there is an inner branch that occasionally goes the other way, the predictor recovers after one mispredict instead of oscillating every cycle.

### Branch History Table and Branch Target Buffer

The BHT (Branch History Table) stores the 2-bit counter for each branch, indexed by `PC[7:2]` (the lower 6 bits of the PC, selecting 1 of 64 entries). The BTB (Branch Target Buffer) stores the predicted target address for each entry.

At fetch time:
1. Look up BHT[PC[7:2]]: if counter MSB = 1, predict taken
2. If predicting taken, redirect PC to BTB[PC[7:2]]
3. If BTB entry is invalid, predict not-taken (fall through to PC+4)

When the branch resolves in EX:
1. Update the BHT counter (increment on taken, decrement on not-taken)
2. Update the BTB with the actual target if taken

### The Critical Bug: branch_taken vs branch_mispredict

The first version of the hazard unit used `control_hazard = (ex_branch && branch_taken) || ex_jump`. This flushed the pipeline on every taken branch — including ones the predictor predicted correctly.

With the predictor enabled, a correctly-predicted taken branch (predict=1, actual=1) had `mispredict = 0`. But `branch_taken = 1` still triggered a flush, canceling the speculatively-fetched instruction that was already correct. The loop accumulator never incremented because the add instruction after the branch was always flushed.

**Fix:** `assign control_hazard = branch_mispredict || ex_jump || trap || ex_mret;`

where `branch_mispredict = ex_branch && (branch_taken != ex_predict_taken)`.

**The lesson:** Once a branch predictor is in place, only *wrong* predictions cause flushes. Right predictions should be invisible to the pipeline.

### The BTB Aliasing Bug

Another real bug: a test program had no halt instruction (no self-loop at the end). After the program completed, the PC kept incrementing through NOP space. At PC = `0x120`, the BTB index was `0x120[7:2] & 0x3F = 8` — the same index as the loop branch at `0x20` (`0x20[7:2] = 8`). The BTB entry from the loop (target = `0x18`, valid = 1, counter = strongly taken) was still there. The predictor redirected PC to `0x18`. The loop restarted with the loop counter at 0, counting negative forever.

**Fix:** Every program ends with `JAL x0, 0` (encoding `0x0000006F`), creating an infinite self-loop. The PC never escapes into NOP space.

**The deeper lesson:** This is a fundamental limitation of index-only BTBs. Real CPUs add tag bits to the BTB — only predict when the stored tag matches the current PC's upper bits.

---

## 16. Cache Architecture

### Why Caches Exist

Main memory (DRAM in real systems, block RAM on FPGA) has high latency: 100+ cycles for DRAM, 2–4 cycles for block RAM. If every instruction fetch and every load/store went to main memory, the pipeline would stall for dozens of cycles on every memory access. A cache stores recently-used data close to the processor in fast SRAM, so most accesses complete in 1 cycle.

### Cache Terminology

**Cache line (cache block):** The unit of transfer between cache and memory. This CPU uses 16-byte lines (4 words). When a cache miss occurs, the entire 16-byte line containing the requested address is fetched — not just the requested word. This exploits **spatial locality**: if you access address X, you are likely to soon access X+4, X+8, etc.

**Direct-mapped:** Each memory address maps to exactly one cache line. Address `A` maps to cache line `A[11:4]` (for this 4KB cache). Simple, fast, no replacement decision needed. Downside: two addresses that map to the same line (A and A+4096) conflict — one evicts the other.

**Tag:** The upper bits of the address stored alongside the cached data to verify that this cache line actually holds data for the requested address and not some other address that happened to map to the same slot.

**Hit:** The requested address is in the cache (valid line, tag matches).

**Miss:** The requested address is not in the cache. Must fetch from memory.

**Write-back:** On a cache hit, writes update the cache only (fast). The memory is updated when the line is evicted (dirty bit = 1 means line has been modified). Alternative: write-through (every write goes to both cache and memory — simpler but slower for write-heavy workloads).

**Write-allocate:** On a write miss, fetch the line into cache first, then apply the write. This CPU uses this policy because future writes to the same line will be fast cache hits.

### Cache Address Breakdown (4KB, Direct-Mapped, 16-byte Lines)

```
Address [31:0]
├── Tag     [31:12]  — 20 bits — identifies which memory block is cached
├── Index   [11:4]   — 8 bits  — selects which of 256 cache lines
└── Offset  [3:0]   — 4 bits  — byte within the 16-byte line
    ├── Word offset [3:2]  — which of 4 words in the line
    └── Byte offset [1:0]  — which byte within the word
```

### The Cache FSM

The data cache uses a 4-state FSM:

```
IDLE ──── miss, dirty line ────► WRITEBACK ──── done ────► FILL
         miss, clean line ──────────────────────────────► FILL
FILL ──── fill complete ─────────────────────────────────► DONE
DONE ─────────────────────────────────────────────────────► IDLE
```

**IDLE:** Check hit. If hit: serve the request in the same cycle. If miss and dirty: evict to WRITEBACK. If miss and clean: go to FILL.

**WRITEBACK:** Send the dirty line's 4 words to memory one by one (4 cycles). Then go to FILL.

**FILL:** Fetch 4 words from memory into the cache line (4 cycles). On the last fill cycle, if the original request was a write, apply the write-allocate write.

**DONE:** Release the stall signal. The pipeline stage captures the data on the next cycle.

### The cache_stall Signal

```systemverilog
assign cache_stall = is_cacheable && (cpu_re || cpu_we) &&
    ((!hit && state == IDLE) || state == WRITEBACK || state == FILL);
```

cache_stall is 0 in DONE state. The pipeline unfreezes at DONE, and on that cycle the cache output `cpu_rd` is valid (data was filled on the last FILL cycle). This is the self-consistent release — mem_mem_re stays high throughout the stall (because EX/MEM is frozen), which keeps cpu_re=1, which keeps cache_stall=1 until DONE. If anything clears EX/MEM mid-fill, cpu_re drops, cache_stall drops, and the pipeline advances with garbage data.

### The One-Shot Flush Disaster

An early attempt introduced `ex_mem_flush = cache_stall && !cache_stall_d` — a one-shot signal that fired only on the first cycle of a miss, to "clean up" EX/MEM. On the first miss cycle: `cache_stall = 1`, `cache_stall_d = 0`, so `ex_mem_flush = 1`. EX/MEM was cleared. `mem_mem_we` dropped to 0. `cache_stall` checked `cpu_re || cpu_we`, now 0. `cache_stall` dropped to 0. The pipeline advanced with `cpu_rd = 0`. The load/store instruction was lost. The cache continued filling in the background, but the pipeline had already moved on.

**Fix:** Remove `ex_mem_flush` entirely. Set `.flush(1'b0)` on EX/MEM. EX/MEM is frozen from cycle 0 of the miss, `mem_mem_re` stays high, `cache_stall` stays high until DONE.

**Lesson:** Never introduce one-shot signals to "initialize" a multi-cycle operation. The freeze-in-place stall mechanism is the correct primitive.

### IO Bypass

Some addresses must bypass the cache entirely — UART registers and PMU counters should not be cached. The bypass is implemented by gating `cpu_re` and `cpu_we`:

```systemverilog
assign is_io   = (mem_alu_result[31:16] == 16'hFFFF);
assign is_perf = (mem_alu_result[31:8]  == 24'hFFFF20);

// dcache only sees non-IO addresses
.cpu_re (mem_mem_re && !is_io),
.cpu_we (mem_mem_we && !is_io),
```

### The PMU Cache Eviction Bug

A real bug: `is_io = (mem_alu_result[31:16] == 16'hFFFF) && !is_perf`. The intent was to separate UART from PMU. The consequence: PMU addresses (`0xFFFF2000+`) had `is_perf = 1`, so `is_io = 0`, so `cpu_re = 1` for PMU reads. The PMU read at `0xFFFF2000` had `addr_idx = 0x00` — the same index as matrix A in data memory. The PMU read missed in the cache (different tag), triggered a writeback of the dirty A data, then filled the cache line with zeros (DSRAM is zero-initialized at `0xFFFF2000`'s word index). A data was evicted.

After a re-fill from DSRAM, A data returned correctly, but the symptom was wrong matrix multiply results for rows 1 and 3.

**Fix:** `assign is_io = (mem_alu_result[31:16] == 16'hFFFF);` — all 0xFFFF addresses bypass the cache, including PMU.

**Lesson:** Every IO/peripheral address must bypass the data cache. If an address satisfies the IO prefix pattern, it must be excluded from caching regardless of what the CPU plans to do with the data.

### Separate Instruction and Data Caches

The Harvard architecture uses separate I-cache and D-cache. The I-cache is simpler — read-only, no dirty bit, no writeback, 3-state FSM (IDLE, FILL, DONE). It adds a `flush` input: when a branch misprediction is detected in EX, the flush signal aborts any in-progress I-cache fill. There is no point finishing a fill for the wrong speculative path.

The benchmark result: **98.3% D-cache hit rate** on the matrix multiply workload with a 4KB cache. This is because matrix A (64 bytes), B (64 bytes), and C (64 bytes) fit comfortably in the 4KB cache, and the loop access pattern has strong spatial and temporal locality.

---

### Interview Questions — Section 16

**Q: What is the difference between write-back and write-through?**
A: Write-through: every write goes to both cache and memory immediately. Simple, but generates significant memory traffic on write-heavy workloads. Write-back: writes update the cache only; memory is updated on eviction. More complex (needs dirty bit, writeback state), but reduces memory traffic substantially.

**Q: What is spatial locality? How does a 16-byte cache line exploit it?**
A: Spatial locality means that if you access address X, you are likely to soon access addresses near X. A 16-byte line fetches the requested word plus the three adjacent words. If the next access is to any of those three words, it is a cache hit without another memory fetch.

**Q: Why is the D-cache hit rate 98.3% on the matrix multiply benchmark?**
A: The matrices (A, B, C — 64 bytes each) fit in three cache lines. After the first pass over each matrix, all subsequent accesses are hits. The 1.7% misses are the compulsory misses on first access to each line.

---

## 17. The AXI4-Lite Memory Fabric

### Why a Bus Protocol?

The original design wired the caches directly to memory modules with custom signals. This works, but it is not portable. FPGA memory IP (BRAM), off-chip SRAM controllers, and peripheral IP are all built with standard bus interfaces. The most common for low-bandwidth control and memory access is **AXI4-Lite** — the simplified version of ARM's AMBA AXI4 protocol used in virtually every Xilinx and Intel FPGA design.

### The Five Channels

AXI4-Lite uses five independent channels, each with a handshake (`VALID`/`READY` pair):

| Channel | Direction | Purpose |
|---------|-----------|---------|
| AR (Address Read) | Manager → Subordinate | "I want to read from this address" |
| R (Read Data) | Subordinate → Manager | "Here is the data you requested" |
| AW (Address Write) | Manager → Subordinate | "I want to write to this address" |
| W (Write Data) | Manager → Subordinate | "Here is the data to write" |
| B (Write Response) | Subordinate → Manager | "Write complete" |

For reads: send AR, receive R. For writes: send AW and W simultaneously, receive B. The handshake: a transfer occurs when both VALID (sender has data) and READY (receiver can accept) are asserted in the same clock cycle.

### Design Decisions

**Combinational managers.** The cache FSMs drive `mem_re` and `mem_addr` as registered outputs (they become stable at posedge N). The AXI managers set `ARVALID = mem_re` combinationally. The SRAM subordinate has `RVALID = ARVALID` (combinational read response). This means data is available in the same cycle the address is presented. The cache's `fill_wait` mechanism already accounts for exactly this one-cycle address-to-data latency. Making the managers registered would break the existing cache timing.

**Separate managers for I-cache and D-cache.** The I-cache manager only has AR and R channels (read-only). The D-cache manager has all five channels. Keeping them separate is cleaner than a parameterized manager — it makes the read-only nature of instruction fetch explicit in the module interface.

**WSTRB = 4'b1111 always.** All cache bus transactions are word-wide. Sub-word access (byte and halfword stores) is resolved inside the cache write-hit path, where individual bytes of the cached word are updated. The AXI bus never sees sub-word writes.

### Fabric Architecture

```
icache ──► ICACHE_MGR (AR/R only) ──► XBAR ──► S0 ──► ISRAM (32KB, read-only)
dcache ──► DCACHE_MGR (all channels) ──► XBAR ──► S1 ──► DSRAM (256KB, read/write)
```

The interconnect (XBAR) has fixed routing: manager 0 always goes to subordinate 0, manager 1 always goes to subordinate 1. No arbitration is needed because the two managers are fully independent. This simplicity is possible because of the Harvard architecture — instruction and data paths never share a transaction.

---

## 18. Exception Handling

### What Exceptions Are

An exception is an event that interrupts normal program flow and transfers control to a handler. In RISC-V M-mode (the only privilege mode in this implementation), exceptions include:

| Exception | mcause value | Cause |
|-----------|-------------|-------|
| External interrupt | 0x8000000B | External IRQ asserted (code=11 decimal, bit 31 set = interrupt) |
| Illegal instruction | 2 | Unrecognized opcode |
| Load address misalign | 4 | LW to non-word-aligned address |
| Store address misalign | 6 | SW to non-word-aligned address |
| ECALL | 11 | System call from user code |

### The CSR File

Control and Status Registers (CSRs) are special registers separate from x0–x31. The M-mode CSRs relevant to exception handling:

| CSR | Address | Purpose |
|-----|---------|---------|
| mstatus | 0x300 | Global interrupt enable (MIE bit) |
| mie | 0x304 | Per-interrupt enable mask |
| mtvec | 0x305 | Trap vector: address of trap handler |
| mepc | 0x341 | Exception Program Counter: PC of interrupted instruction |
| mcause | 0x342 | What caused the exception |
| mip | 0x344 | Pending interrupt flags (read-only) |

### Trap Entry and Return

When an exception is detected (in the EX stage, by the exception unit):
1. Save the current PC to `mepc`
2. Write the cause to `mcause`
3. Set `trap = 1` in the hazard unit
4. `pc_next = mtvec` — redirect to the trap handler

When the trap handler completes and executes `mret`:
1. `pc_next = mepc` — return to the interrupted instruction
2. Re-enable interrupts (clear MIE in mstatus)

### CSR Forwarding Bug

A subtle bug: reading a CSR with CSRRW, then using the read value immediately:
```asm
csrrw x22, mepc, x0   # read mepc into x22
addi  x23, x22, 4     # use x22 immediately
```

The original implementation used `wb_sel = 2'b11` to select CSR data at the WB stage. But CSR data was read directly from `csr_rd` (a combinational read using `ex_csr_addr`). By the time the CSRRW reached WB, `ex_csr_addr` pointed to the NEXT instruction's CSR field — not the CSRRW. The wrong value was read.

**Fix:** Route `csr_rd` through `ex_result` in the EX stage. It then flows through EX/MEM and MEM/WB exactly like any ALU result, and the standard forwarding unit handles the use-after-CSR-read hazard:

```systemverilog
assign ex_result = is_simd ? simd_result :
                   ex_csr_re ? csr_rd :
                   ex_alu_result;
```

**Lesson:** Any value that needs to be forwarded or written back must flow through `ex_result`. The forwarding unit uses `mem_alu_result` (which comes from `ex_result` via EX/MEM). A separate path that bypasses `ex_result` bypasses forwarding.

---

## 19. The UART Peripheral

### What UART Is

UART (Universal Asynchronous Receiver/Transmitter) is the simplest serial communication protocol. It sends one bit at a time over a single wire at a fixed baud rate. 8N1 format: 8 data bits, No parity, 1 stop bit. The receiver samples the middle of each bit to determine its value.

```
Idle: ─────────────────
      ↓ start bit
TX:   ─┐ ┌─┐ ┌─────────┐ ┌──────────
        │0│1│0│ 0 0 0 0 │1│          ← 8 data bits, LSB first
        └─┘ └─┘         └─┘ stop bit
```

### Memory-Mapped Interface

The CPU communicates with the UART by reading and writing specific memory addresses:

```
0xFFFF0000 — TX data register (write: queue byte for transmission)
0xFFFF0004 — TX status register (read: bit 0 = 1 when FIFO not full)
0xFFFF0008 — RX data register (read: last received byte)
0xFFFF000C — RX status register (read: bit 0 = 1 when data valid)
```

A typical transmit sequence:
```asm
poll:   lw   x28, 0(x11)      # read TX status (x11 = 0xFFFF0004)
        andi x28, x28, 1      # check FIFO not-full bit
        beq  x28, x0, poll    # wait until ready
        sw   x25, 0(x10)      # write byte to TX register (x10 = 0xFFFF0000)
```

### The 8-Entry TX FIFO

A FIFO (First In, First Out) buffer between the CPU and the UART transmitter. The CPU can queue up to 8 bytes before the FIFO fills. This prevents the CPU from stalling behind the slow UART baud rate. At 9600 baud, each byte takes 1.04ms. Without a FIFO, every byte transmission would stall the CPU for millions of cycles.

### UART RX

The RX path is harder than TX because the receiver must synchronize to an asynchronous signal coming from outside the CPU's clock domain. The implementation uses:

1. **2-flop synchronizer:** Two flip-flops in series to prevent metastability when sampling the incoming signal.
2. **Falling-edge detection:** The start bit is a falling edge (idle high, start low). The 2-flop output is compared to its delayed version.
3. **Mid-bit sampling:** After detecting the start bit, wait 1.5 bit periods to sample the middle of the first data bit. Then sample every bit period after that.

---

## 20. Custom SIMD Extensions

### Why RISC-V Allows Custom Extensions

RISC-V reserves two 7-bit opcode spaces (`0001011` and `0101011`) for custom instructions. Any implementation can add instructions there without conflicting with the standard ISA. The decoder just needs to recognize the custom opcode and route to a custom execution unit.

### The PDOT Instruction

Neural network inference is dominated by multiply-accumulate (MAC) operations: computing `sum(A[i] * B[i])` for vectors of values. On a standard RV32I CPU, each multiply requires a shift-and-add loop (8 iterations for 8-bit values). Computing one dot product of two 4-element INT8 vectors requires 4 × 8 = 32 loop iterations.

PDOT computes the entire dot product in one instruction:

```
PDOT rd, rs1, rs2:
  rd = rs1[7:0]*rs2[7:0] + rs1[15:8]*rs2[15:8] + rs1[23:16]*rs2[23:16] + rs1[31:24]*rs2[31:24]
```

Each register holds 4 packed 8-bit values. One instruction replaces 32 shift-and-add loop iterations.

### The Benchmark

The matrix multiply benchmark computes C = A × I (identity matrix) for 4×4 INT8 matrices. Results measured via hardware PMU:

| | Scalar | SIMD | Ratio |
|---|--------|------|-------|
| Cycles | 4329 | 277 | **15.6×** |
| Instructions | 3051 | 201 | 15.2× |
| CPI | 1.419 | 1.378 | — |
| D$ hit rate | 98.3% | 96.2% | — |
| Branch mispredict | 9.6% | 35.0% | — |

The SIMD version has a higher branch mispredict rate because the outer loop is only 4 iterations — not enough to train the branch predictor. The scalar version's main loop runs hundreds of iterations, so the predictor learns it well.

The speedup is entirely from instruction throughput. The memory access pattern is identical in both versions (same addresses, same order). The D-cache hit rate difference is noise from the shorter SIMD loop having proportionally more cold misses.

> **Recruiter Note:** This directly demonstrates understanding of how AI accelerators work. Tenstorrent, Nvidia, and AMD all build chips that are, at their core, very efficient SIMD MAC engines. The PDOT instruction is a toy version of what those chips implement at scale.

---

## 21. Hardware Performance Counters

### What PMUs Are

A Performance Monitoring Unit (PMU) counts hardware events that are normally invisible to software. Real CPUs (Intel VTune, ARM PMU, AMD uprof) expose PMU counters to profiling tools. This implementation provides 8 counters accessible from software via memory-mapped reads.

### How the Benchmark Works

The test program reads the cycle and instruction counters at the start of the timed section, runs the computation, reads the counters again at the end, and transmits the deltas over UART:

```asm
lw x1, 0(x12)    # x1 = cycle_start    (x12 = 0xFFFF2000)
lw x2, 4(x12)    # x2 = instr_start
# ... computation ...
lw x3, 0(x12)    # x3 = cycle_end
sub x3, x3, x1   # elapsed cycles
```

This measures only the computation, not the setup or UART transmission overhead.

---

## 22. Verification Strategy

### The Philosophy: Test Before You Integrate

Every module in this project has a standalone testbench written before the module is integrated into the pipeline. This is not optional — it is how hardware verification works professionally.

The verification progression:
1. Write the module
2. Write its testbench
3. Run the testbench until it passes
4. Integrate into the pipeline
5. Run the full pipeline testbench
6. If the pipeline fails, the bug is in the integration, not the module

This approach halved debugging time on every integration. When the AXI4-Lite fabric was integrated, every cache and memory module had already been verified standalone. The integration testbench only needed to check the wiring.

### Testbench Structure

A good hardware testbench is not a script that runs once. It is a verification environment that:

1. **Applies stimulus** — drive the inputs through all meaningful states and transitions
2. **Checks responses** — compare outputs against expected values
3. **Reports pass/fail** — print specific failure messages, not just a final count
4. **Uses randomness** — random inputs expose corner cases that hand-crafted tests miss

### Waveform Debugging

When a test fails, the testbench alone rarely reveals why. The next step is always to open the VCD waveform in Wavetrace (VS Code extension, or GTKWave as fallback). Key signals to inspect:

For cache bugs:
```
cache_stall, cache.state, cache.hit, cache.fill_word
cpu_re, cpu_we, cpu_addr, cpu_rd, cpu_wd
mem_re, mem_we, mem_addr, mem_rd
```

For pipeline bugs:
```
if_pc, id_pc, ex_pc, mem_pc   ← trace an instruction through stages
ex_fwd_a, ex_fwd_b            ← what the ALU actually received
forward_a, forward_b          ← which forwarding path was taken
cache_stall, icache_stall     ← which stall signals are active
```

For branch/jump bugs:
```
ex_branch, ex_branch_taken, ex_predict_taken, branch_mispredict
if_id_flush, id_ex_flush
bp_predict_target, ex_pc_branch
```

### The Diagnostic Pattern

When a pipeline integration fails, add always-at-posedge monitor blocks to print key signals every cycle:

```systemverilog
always @(posedge clk) begin
    if (cpu.ex_branch)
        $display("t=%0t BNE: fwd_a=%08h fwd_b=%08h taken=%b predict=%b mispredict=%b",
            $time, cpu.ex_fwd_a, cpu.ex_fwd_b,
            cpu.ex_branch_taken, cpu.ex_predict_taken, cpu.branch_mispredict);
end
```

This produces a cycle-by-cycle trace of exactly what happened. Form a specific hypothesis from the trace. Test the hypothesis. Fix it. Never stare at code hoping to spot the bug — always add instrumentation to see what is actually happening.

---

## 23. Debugging: Real Bugs, Real Fixes — Simulation and Synthesis

This section documents every significant bug found during this project in the order they were discovered. Each entry explains the symptom, the diagnosis, the fix, and the lesson learned.

### Bug 1: is_io Computed From the Wrong Address

**Symptom:** UART writes appeared to succeed (no error) but no data was transmitted. The UART status register read as a normal memory address.

**Cause:** The original design had `data_memory` compute `is_io` from its own `addr` input. After the dcache was inserted between the CPU and `data_memory`, the `addr` input to `data_memory` was driven by the dcache's internal addresses — the writeback base address during WRITEBACK, the fill address during FILL. Neither of these is `0xFFFF0000`, so `is_io` read 0 when the CPU was actually accessing UART.

**Fix:** Compute `is_io` from `mem_alu_result` (the CPU's address in the pipeline) in `top_pipeline.sv`. Never use a backing memory's IO detection after inserting a cache.

**Lesson:** `mem_alu_result` is the CPU's address. `dcache.cpu_addr` is whatever the cache needs to access memory at the moment, which changes during FILL and WRITEBACK. Always derive IO decode from the CPU-side signal.

---

### Bug 2: Pipeline Registers Missing Stall Enables

**Symptom:** Load instructions followed by a dcache miss returned 0 for the loaded value. Register file was being written with 0 instead of the loaded data.

**Cause:** The ID/EX, EX/MEM, and MEM/WB pipeline registers had no stall logic. During a dcache stall (when the data cache was filling), only the PC and IF/ID register were frozen. EX/MEM and MEM/WB kept advancing. MEM/WB latched `cpu_rd = 0` (the dcache output during FILL is 0), and WB wrote 0 to the destination register.

**Fix:** Add `id_ex_stall`, `ex_mem_stall`, `mem_wb_stall` driven by `cache_stall` to all three registers. Add `else if (!stall)` guard to every pipeline register.

**Lesson:** During any multi-cycle stall, every pipeline register behind the waiting stage must be frozen. No exceptions.

---

### Bug 3: Cache Stall Oscillation

**Symptom:** Loads returned 0 even after the cache was filled. Simulation traces showed `cache_stall` going high for one cycle, dropping to 0, rising again, oscillating.

**Cause:** A `ex_mem_flush` signal was used to "initialize" the first cycle of a cache miss. On cycle 0 of a miss: `cache_stall = 1`, `ex_mem_flush = 1`. EX/MEM was cleared. `mem_mem_re` dropped to 0. `cache_stall` checks `cpu_re || cpu_we`... now 0. `cache_stall` dropped immediately. The pipeline advanced with `cpu_rd = 0`. The cache continued filling, but the pipeline had moved on.

**Fix:** Remove `ex_mem_flush` and `cache_stall_d` entirely. Set `.flush(1'b0)` on the EX/MEM register. The EX/MEM register simply freezes when `cache_stall = 1`. `mem_mem_re` stays high. `cache_stall` stays high until DONE.

**Lesson:** Never use a one-shot signal to handle the first cycle of a multi-cycle operation. The freeze mechanism is the correct and only primitive.

---

### Bug 4: Branch Predictor Flushing Correct Predictions

**Symptom:** Loop accumulator never incremented. Branch was taken correctly every iteration, but the `add` instruction after the branch was always flushed.

**Cause:** `control_hazard = (ex_branch && branch_taken) || ex_jump`. With the predictor predicting correctly (predict=1, actual=1), `branch_taken = 1` still fired the flush. The `add x5, x5, x3` fetched speculatively was always canceled — even though it was the right instruction.

**Fix:** `control_hazard = branch_mispredict || ex_jump` where `branch_mispredict = ex_branch && (branch_taken != ex_predict_taken)`.

**Lesson:** `branch_taken` and `branch_mispredict` are fundamentally different signals. A branch predictor is only useful if correct predictions produce zero penalty cycles.

---

### Bug 5: SYSTEM Instruction funct12 Wrong Bits

**Symptom:** ECALL trapped with `mcause = 2` (illegal instruction) instead of `mcause = 11` (ECALL). MRET jumped to address 0. All CSR writes went to the wrong register.

**Cause:** `assign funct12 = instr[11:0]`. RISC-V SYSTEM instructions use I-type encoding; the CSR address and sub-opcode discriminator (ECALL = 0x000, MRET = 0x302) are in `instr[31:20]`. `instr[11:0]` contains opcode + rd.

**Fix:** `assign funct12 = instr[31:20];`

**Lesson:** For SYSTEM instructions, the 12-bit "immediate" field is not a data value — it is the CSR address or sub-opcode. It is always in bits [31:20]. The symptom pattern (mcause = 2 on every ECALL) is now instantly recognizable as a funct12 decode error.

---

### Bug 6: CSR Read Data Bypassed Forwarding

**Symptom:** `csrrs x22, mepc, x0` returned 0 instead of the mepc value. Subsequent MRET returned to address 0.

**Cause:** CSR read data was selected at WB via `wb_sel = 2'b11 → wb_csr_rd = csr_rd`. But `csr_rd` is a combinational read keyed on `ex_csr_addr`. By the time CSRRW reaches WB (2 cycles later), `ex_csr_addr` points to a different instruction. The wrong CSR was read. Additionally, this path bypassed the forwarding unit — the value could not be forwarded to the next instruction.

**Fix:** Route `csr_rd` through `ex_result` at the EX stage. It flows through EX/MEM and MEM/WB identically to any ALU result. Use `wb_sel = 2'b00` for CSR instructions.

**Lesson:** Any value that needs forwarding must flow through `ex_result`. The forwarding unit only sees `mem_alu_result` and `wb_alu_result` — both derived from `ex_result`. A bypass path to WB is invisible to forwarding.

---

### Bug 7: PMU Reads Evicting Data Cache Contents

**Symptom:** Matrix multiply computed wrong results for rows 1 and 3. SIMD PDOT trace showed `a = 0x04030201` (row 0 of A) for all iterations instead of alternating rows.

**Cause:** `is_io = (addr[31:16] == 0xFFFF) && !is_perf`. PMU addresses (`0xFFFF2000`) have `is_perf = 1`, so `is_io = 0`, so dcache sees `cpu_re = 1` for PMU reads. The PMU read at `0xFFFF2000` has `addr_idx = 0x00` — same cache index as matrix A (at `0x1000`). Cache miss (different tag) → writeback of dirty A data to DSRAM → fill cache line with zeros from DSRAM[0xC800]. A data evicted. Later, when the compute loop first accessed A, a re-fill brought it back from DSRAM correctly — but row 1 data arrived through a chain of fill/re-fill timing that depended on the cache state at the time.

**Fix:** `assign is_io = (mem_alu_result[31:16] == 16'hFFFF);` — include all 0xFFFF addresses, including PMU.

**Lesson:** Any address that should not be cached must be excluded from the cache's `cpu_re`/`cpu_we` inputs. If an address matches the IO address prefix, it bypasses the cache, full stop. The `!is_perf` exception was the mistake.

---

### Bug 8: Icache Stall Froze All Five Stages

**Symptom:** Programs with loads near cache line boundaries occasionally produced wrong register values. The loaded register held its reset value (0) instead of the loaded data.

**Cause:** `id_ex_stall = cache_stall || icache_stall`. When a load-use hazard fired simultaneously with an icache miss: `id_ex_flush = 1` (load-use) cleared the load from ID/EX. `ex_mem_stall = 1` (icache) prevented EX/MEM from advancing. The load was in EX for one cycle, replaced by a NOP via flush, and never reached MEM.

**Fix:** `id_ex_stall = cache_stall` (remove icache_stall). `ex_mem_stall = cache_stall` (same). `id_ex_flush = (load_use || control_hazard || icache_stall) && !cache_stall` — icache stall still inserts bubbles to prevent double-issue.

**Lesson:** Icache miss means only IF is waiting. The instructions behind IF are valid and must complete. Freezing EX/MEM during an icache miss prevents valid instructions from committing.

---

### Bug 9: PMU Instruction Retirement Overcounting During Stalls

**Symptom:** SIMD instruction count reported as 201 instead of the expected value. After adding two stall cycles per SIMD instruction (to implement registered SIMD inputs for timing closure), the instruction count jumped to 231 instead of staying at approximately 201. Instruction count should not change when stall cycles are added — stalls add cycles, not instructions.

**Cause:** `assign instr_retired = wb_reg_we`. When `mem_wb_stall = 1` (any stall condition), the MEM/WB register holds. Whatever instruction is in WB keeps its `wb_reg_we = 1` asserted for every stall cycle. The PMU counts each of those stall cycles as a separate retirement. With one stall cycle per SIMD instruction: 16 extra counts. With two stall cycles: 32 extra counts. Non-SIMD instructions in WB during the stall (the instruction behind the SIMD in the pipeline) also stall in MEM/WB, adding further overcounting beyond just the SIMD instruction itself.

**Fix:** `assign instr_retired = wb_reg_we && !mem_wb_stall;`

**How it was found:** The instruction count changed when a microarchitectural parameter (stall cycles per SIMD instruction) changed. Instruction count should be a property of the program, not the microarchitecture. When a counter that should be architecture-level changes in response to a microarchitectural change, the counter is measuring the wrong thing. Systematic reasoning about what should and should not change under a specific modification is how subtle measurement bugs are found.

**Corrected benchmark numbers after fix:** Scalar 835 instrs (was 841), SIMD 195 instrs (was 201), parallel MAC and systolic unchanged (no SIMD or divider stalls in those paths). SIMD CPI corrects from 1.299 to 1.503 — accurately reflecting the two-stall cost.

---

### Bug 10: wb_csr_rd Combinational Bypass Creating Timing Path and Latent Forwarding Bug

**Symptom:** Vivado timing report showed a critical path from `ex_csr_addr_reg` through CSR decode (fanout 34) through the forwarding network into the SIMD carry chain and dcache. Path delay 17.5 ns, well over the 10 ns budget.

**Cause:** `assign wb_csr_rd = csr_rd` and `wb_data = ... (wb_wb_sel == 2'b11) ? wb_csr_rd ...`. `csr_rd` is a combinational read from the CSR register file, keyed on `ex_csr_addr` — the CSR address of whichever instruction is currently in EX. By the time a CSR instruction reaches WB (two cycles later), `ex_csr_addr` points to a completely different instruction. The bypass was re-reading the wrong CSR register at WB. It worked by coincidence in most cases because the CSR file updates were synchronous and the stale read happened to return the right value — but it created a live combinational path from the current EX stage's CSR address decode through `wb_data` through the ID-stage forwarding mux (`id_rs1_data_fwd`, `id_rs2_data_fwd`) and from there into the SIMD unit's operand inputs. This is also a latent forwarding bug: the forwarding unit only sees `mem_alu_result` and `wb_alu_result`, both derived from `ex_result`. A CSR result that bypasses `ex_result` and goes directly to WB cannot be forwarded to the instruction immediately following the CSR read.

**Fix:** Use `wb_alu_result` for `wb_wb_sel == 2'b11` instead of `wb_csr_rd`. Remove `wb_csr_rd` entirely. The CSR read result enters `ex_result` when `ex_csr_re = 1`, flows through EX/MEM into `mem_alu_result`, then through MEM/WB into `wb_alu_result`. It is already in the pipeline and already visible to the forwarding unit.

**Lesson:** Any value that a subsequent instruction might need to forward must flow through `ex_result`. A bypass to WB that skips the pipeline registers is invisible to the forwarding unit. This is the same lesson as Bug 6, surfaced again by the timing tool rather than by a functional test — which is why synthesis is not just an implementation step but a verification step.

---

### Bug 11: Waveform Artifact Mistaken for RTL Bug

**Symptom:** During waveform review of `tb_dcache.sv`, `wb_addr` appeared stuck at `0x00000000` across two separate dirty evictions. The waveform showed `wb_addr` transitioning from `x` to `0x00000000` at the first eviction and never updating for the second, despite the second eviction appearing to target a different address.

**Initial hypothesis:** `wb_addr` register failing to latch on the second dirty miss detection. Possible causes: missing condition in the IDLE state dirty-miss branch, or a gating signal preventing the register from updating.

**Diagnostic approach:** Before touching any RTL, added `$display` statements to the IDLE state dirty-miss branch and to the WRITEBACK state:

```systemverilog
// In IDLE dirty miss branch:
$display("[DCACHE] t=%0t EVICT: addr_idx=%0h tags[addr_idx]=%0h wb_addr_next=%0h",
         $time, addr_idx, tags[addr_idx], {tags[addr_idx], addr_idx, 4'd0});

// In WRITEBACK:
$display("[DCACHE] t=%0t WB: fill_word=%0d mem_addr=%0h mem_wd=%0h",
         $time, fill_word, {wb_addr[31:4], fill_word, 2'b00}, cached_word_q);
```

**What the $display output proved:** Both evictions genuinely target `0x00000000`. Test 4 writes to `0x00000000` (dirty, tag=0), then reads `0x00001000` (different tag, same index → evict). Test 5 writes `0xCAFEBABE` to `0x00000000` again — this is a miss because the cache now holds tag=1 from the previous fill, so it re-fills the line with tag=0 and marks it dirty. The subsequent `read(0x1000)` again evicts the tag=0 line. Both evictions legitimately target `0x00000000`.

**Why the waveform looked wrong:** `0x00000000` and `0x00001000` differ only in bit 12. With 8-bit index (bits 4-11) and 256 lines, both addresses map to cache index 0. Tag for `0x0` is `0x00000`, tag for `0x1000` is `0x00001`. The test never creates a dirty line at a non-zero index. Wavetrace compressed the `wb_addr` signal between evictions since it held the same value both times, making it appear stuck when it was simply stable at the correct value.

**End-to-end confirmation:** Zoomed into the second writeback burst and confirmed `mem_wd = 0xCAFEBABE` at `mem_addr = 0x0000100C` (word offset 3 of the 0x1000-base dirty line). Address-matched and data-matched — the dirty write correctly landed in the cache and the writeback correctly carried it out.

**Lesson:** Always add simulation instrumentation before forming conclusions from waveforms. Visual artifacts (a signal that holds the same value and appears compressed) and genuine bugs (a signal that fails to update) are visually identical. The `$display` output takes 30 seconds to add and gives ground truth. Also: index aliasing in direct-mapped caches is exactly the kind of subtle behavior that looks wrong from the outside but is architecturally correct. Understanding the address breakdown (tag bits, index bits, offset bits) lets you predict whether two addresses will conflict before looking at waveforms at all.

---

## 24. Performance Analysis

### Corrected Benchmark Numbers

All numbers are measured via hardware PMU with the corrected `instr_retired` signal: `assign instr_retired = wb_reg_we && !mem_wb_stall`. The earlier version used `assign instr_retired = wb_reg_we` which overcounted retirements during any stall cycle — the instruction held in WB kept `wb_reg_we` asserted for every stall cycle, inflating the count. The fix gates retirement on `!mem_wb_stall`.

4×4 INT8 GEMM on RV32I+M core:

| Version | Cycles | Instrs | CPI | Speedup |
|---------|--------|--------|-----|---------|
| Scalar (RV32M mul) | 1,065 | 835 | 1.275 | 1.00× |
| SIMD (PDOT) | 293 | 195 | 1.503 | 3.63× |
| Parallel MAC | 79 | 22 | 3.59 | 13.48× |
| Systolic Array | 87 | 26 | 3.35 | 12.24× |

### CPI Breakdown

The theoretical minimum CPI for a 5-stage pipeline is 1.0. The scalar measured CPI is 1.275. The gap comes from:

| Source | Estimated cycles added |
|--------|----------------------|
| Load-use stalls | ~100 (LBU + dependent ops in scalar loop) |
| D$ cold misses | 3 misses × ~8 cycles = 24 |
| Branch mispredictions | ~60 × 2 = 120 |
| I$ cold misses | ~20 |
| **Total above ideal** | ~264 cycles over 835 instructions ≈ 0.316 CPI overhead |

### SIMD CPI Increase

The SIMD CPI of 1.503 is higher than scalar (1.275). This is expected and correct — it reflects the two-stall-cycle cost of registered SIMD inputs. Each SIMD instruction takes three pipeline cycles (IDLE → WAIT1 → WAIT2) to allow the forwarding network to settle before the SIMD carry chain computes. 16 PDOT instructions × 2 extra stall cycles = 32 extra cycles. The timing benefit (removing the SIMD carry chain from the critical path, gaining 6 MHz) is worth the CPI cost.

The old SIMD CPI of 1.299 was misleadingly close to scalar because the PMU bug was inflating the instruction count, making the stall overhead look smaller than it was.

### Why SIMD Is Still 3.63× Faster

A single PDOT instruction replaces an 8-iteration multiply-accumulate loop. For 16 output elements each requiring 4 multiply-accumulate operations, scalar requires 16 × 4 × 8 = 512 multiply loop iterations. SIMD requires 16 PDOT instructions. The 3.63× speedup comes from instruction count reduction (195 vs 835), not CPI improvement — SIMD CPI is actually worse, but there are so many fewer instructions that the total cycle count drops sharply.

### Accelerator CPI

Parallel MAC CPI of 3.59 and systolic CPI of 3.35 are high because the 4×4 tile is small relative to the AXI register-write overhead. For a 4×4 GEMM, the CPU spends more cycles writing input tiles into the accelerator's register map than the accelerator spends computing. This overhead amortizes at larger tile sizes — the design supports K > 4 tile accumulation specifically to address this.

### What the PMU Bug Taught

The PMU overcounting bug was caught by noticing that the instruction count for SIMD (201 in the old version, 195 corrected) changed when two stall cycles were added per SIMD instruction. If the PMU were correct, adding stall cycles should increase the cycle count but not the instruction count — instructions are instructions regardless of how many stall cycles surround them. The instruction count increasing confirmed the PMU was counting stall cycles as retirements. Systematic reasoning about what should and should not change when a microarchitectural parameter changes is how you find subtle measurement bugs.

---

## 25. FPGA Synthesis and Timing Closure

### Results

Synthesized and implemented on Xilinx Artix-7 xc7a200tsbg484-2 using Vivado 2025.2 with a 10 ns (100 MHz) clock constraint and `-flatten_hierarchy none`.

**Post-implementation results:**

| Metric | Value |
|--------|-------|
| Achieved Fmax | ~79 MHz |
| WNS | -2.730 ns |
| TNS | -2605.561 ns |
| Failing endpoints | 1,679 / 20,318 |
| Slice LUTs | 14,084 |
| Slice Registers | 5,399 |
| Block RAM Tile | 1 (icache, RAMB36E1) |
| DSP48E1 | 8 |

### Fmax Progression

The design started at 57 MHz and reached 79 MHz through four targeted critical path fixes. Each fix was identified by reading the Vivado timing report, understanding the root cause in the RTL, making a minimal change, and re-running implementation to verify the improvement.

| Step | Fix | WNS | Fmax |
|------|-----|-----|------|
| Start | — | -7.787 ns | ~57 MHz |
| 1 | `ex_addr_i = ex_alu_result` (removed SIMD/CSR from dcache prefetch path) | -4.467 ns | ~69 MHz |
| 2 | Removed `wb_csr_rd` combinational bypass (CSR decode fanout 34 into forwarding network) | -3.670 ns | ~73 MHz |
| 3 | Registered SIMD inputs + 2-cycle stall state machine (removed forwarding network from SIMD carry chain path) | -2.730 ns | ~79 MHz |

### Critical Path Analysis

**Starting critical path (57 MHz):** `ID_EX/ex_csr_addr_reg` → CSR address decode → mstatus fanout-33 → multiplier operand select → two cascaded DSP48E1 → 6-stage CARRY4 chain → forwarding mux → dcache distributed RAM → `cached_word_q`. 17.532 ns, 23 logic levels.

**Root cause:** `ex_result` mux included `simd_result` and `csr_rd` alongside `ex_alu_result`. This mux output was wired to `ex_addr_i` (dcache prefetch address). The SIMD unit has 12 carry stages deep. The CSR file read is keyed on `ex_csr_addr` with fanout 34. Both of these created long combinational paths that fed dcache's prefetch address.

**Fix 1 — ex_addr_i:** The dcache prefetch address only needs `ex_alu_result`. Load and store addresses are always `base + offset` computed by the ALU. SIMD and CSR instructions never access memory. Wiring `ex_result` to `ex_addr_i` pulled the entire result mux (including SIMD carry chain and CSR decode) into the dcache timing path for no reason.

**Fix 2 — wb_csr_rd:** The original `wb_data` mux used `wb_csr_rd = csr_rd` for CSR instructions at WB. `csr_rd` is a combinational read keyed on `ex_csr_addr` of whichever instruction is currently in EX — not the WB-stage CSR instruction. This is architecturally wrong (it re-reads the CSR file with a stale address) and creates a live combinational path from CSR address decode through the forwarding network into SIMD operands. Fix: use `wb_alu_result` for `wb_wb_sel == 2'b11`. The CSR result enters `ex_result` in EX, flows through EX/MEM into `mem_alu_result`, then through MEM/WB into `wb_alu_result`. It is already in the pipeline.

**Fix 3 — registered SIMD inputs:** The SIMD ALU is a 12-stage carry chain (four 8×8 multiplies plus a four-term adder for PDOT). With 10 ns budget and setup overhead, the forwarding network feeding SIMD operands had only ~1.5 ns for everything outside SIMD — not achievable. Fix: register `ex_fwd_a/b/acc` into `simd_a_q/b_q/acc_q` gated on `simd_stall`, and register `simd_result` into `simd_result_q` gated on the second stall cycle. The `simd_busy` state machine (IDLE → WAIT1 → WAIT2) gives two stall cycles: one for input registers to capture correct forwarded values, one for SIMD to compute from clean registered inputs. The forwarding network is completely absent from the SIMD timing path.

**Final critical path (79 MHz):** `EX_MEM/mem_rd_addr_reg` → forward unit (`forward_b`, fanout 40) → `ex_fwd_b` → ALU → `ex_alu_zero` → hazard unit → icache `valid_reg[68]`. 13.476 ns, 17 logic levels. Root cause: branch predictor BHT is a 64-entry flip-flop array read combinationally via a 64:1 mux tree. The mux tree plus BTB tag comparison feeds `predict_taken`, which feeds `pc_next`, which feeds the icache prefetch address. Known fix: register `predict_taken` and `predict_target` with a one-cycle validity gate suppressing stale predictions after any of the five `pc_next` override conditions (trap, mret, jump mispredict, branch mispredict, icache stall). Expected gain: 4–8 MHz. Not implemented due to high correctness risk from the validity gate interacting with five override conditions and three stall types.

### BRAM Inference

icache data[] successfully inferred as 1 RAMB36E1 tile (1024×32 SDP). dcache data[] failed inference — maps to RAM64M×176 distributed RAM. Root cause: dcache Port B always_ff requires a conditional bypass for write-hit coherence (`cached_word_q <= write_merge`). Vivado requires unconditional synchronous read for BRAM inference. Removing the bypass creates a combinational loop through `write_merge → cached_word_q → write_merge`. All attempted fixes either broke simulation (LBU/LHU returning 0, pmacc_pipeline returning half the expected value) or failed inference. Documented in KNOWN_LIMITATIONS.md.

### What Synthesis Taught

The critical path analysis revealed a subtle architectural mistake: `wb_csr_rd = csr_rd` was re-reading the CSR file combinationally at WB using the address of whatever instruction was currently in EX, not the WB-stage instruction. This was functionally correct by accident (the forwarding unit never forwarded from this path because it bypassed `ex_result`) but created a live combinational path visible in the timing report. The fix — routing CSR read data through `ex_result` like any other result — also fixed a latent forwarding correctness issue: if a CSR instruction was followed immediately by an instruction that read the same register, the forwarding unit could not forward the CSR result because it never appeared in `mem_alu_result` or `wb_alu_result`. After the fix, CSR results forward correctly.

Synthesis is not just about getting a number. It is about having the tool show you paths that your simulation never exercises in ways that expose timing and the structural mistakes that create timing problems are often the same mistakes that create correctness problems under corner-case scheduling.

### How to Reproduce

Vivado 2025.2, target xc7a200tsbg484-2, add all `src/*.sv` sources, constraint:
```
create_clock -period 10.000 [get_ports clk]
```
Synthesis: `-flatten_hierarchy none`. Run implementation. See `SYNTHESIS.md` for full details.

---

## 26. What to Build Next

### What Is Already Done (Update from Original Guide)

Several items listed as future work in earlier versions of this guide are now complete:

- **FPGA synthesis and timing closure** — 79 MHz on Artix-7 xc7a200t-2, documented in SYNTHESIS.md
- **BTB tag anti-aliasing** — `btb_tag[31:8]` implemented, prevents aliasing between PCs that share the same 6-bit index
- **RV32M extension** — combinational MUL mapping to DSP48, 32-cycle restoring divider, full spec corner cases
- **AXI4-Lite fabric** — 5M/5S crossbar fully implemented and verified
- **Custom SIMD** — 7 instructions, complete INT8 inference primitive set
- **Hardware accelerators** — parallel MAC (13.48×) and output-stationary systolic array (12.24×)

### Immediate Priorities

**Hardware validation on physical FPGA.** The design synthesizes and routes. Getting it running on a physical board (Arty A7-35T used, or similar) requires a constraints file (.xdc) mapping ports to pins, a test program sending output over UART, and confirming the CPU executes correctly on silicon. This transforms the project from "synthesized and timed" to "hardware-verified" — a meaningful credibility upgrade for applications.

**Branch predictor output register.** The final critical path at 79 MHz is the BHT combinational read. Registering `predict_taken` and `predict_target` with a validity gate would push Fmax to ~83–87 MHz. The validity gate must suppress stale predictions for the one cycle after any of five `pc_next` override conditions. High correctness risk — requires careful verification of interactions with all stall types.

**dcache BRAM inference.** The write-hit forwarding combinational loop (`write_merge → cached_word_q → write_merge`) is the blocker. The correct fix is accepting one extra stall cycle on write-hit loads to allow the BRAM registered output to serve as the merge base. This requires a new pipeline state in the dcache FSM and verification of the LHU/LBU paths that previously broke.

### Architecture Upgrades (6–12 months)

**2-way set-associative cache.** Direct-mapped causes thrashing when two frequently-used addresses map to the same cache line. 2-way SA with pseudo-LRU replacement eliminates most conflict misses. The FSM complexity roughly doubles but the cache design is otherwise the same. The direct-mapped aliasing behavior is already observable in the waveforms — addresses 0x0000 and 0x1000 share cache index 0 and repeatedly evict each other.

**Larger caches.** Scale to 16 KB or 32 KB by increasing `NUM_LINES`. The FSM and logic are unchanged — only the arrays grow. With BRAM inference working, larger caches cost BRAMs, not LUTs.

**Registered branch predictor outputs.** Already described above as an immediate priority. After fixing correctness, this closes the final known timing gap.

### Research-Grade Extensions (12+ months)

**Out-of-order execution.** The fundamental architectural leap from in-order pipelines. Instructions execute when their operands are ready, not in program order. Requires a reorder buffer (ROB), reservation stations, and register renaming. This is what modern high-performance cores (Apple M-series, AMD Zen, ARM Cortex-X) all implement.

**Superscalar.** Fetch, decode, and execute multiple instructions per clock cycle. Requires multiple ALUs and careful dependency checking across parallel instruction streams.

**Hardware prefetching.** Predict future memory accesses and fetch cache lines before they are needed, hiding cache miss latency entirely.

**Scratchpad memory architecture.** Tenstorrent's Tensix architecture and most ML accelerators use software-managed scratchpad memory instead of hardware caches. The performance argument: caches handle irregular access patterns automatically at the cost of unpredictable latency. Scratchpads require the compiler or programmer to manage data movement explicitly but give deterministic latency and higher bandwidth utilization for regular access patterns (like matrix multiply). Designing a scratchpad-based memory system for the accelerators would directly mirror what ML hardware companies are building.

---

### Final Thoughts

This project implements the same fundamental architecture taught in Patterson and Hennessy's *Computer Organization and Design* — the most widely-used computer architecture textbook — but in a complete, verified, benchmarked RTL implementation rather than a pedagogical diagram.

Every bug documented in Section 23 was found by building, testing, breaking, and fixing. That process — not the final working design — is what produces engineering judgment. The working design is the byproduct of the process.

The next step is FPGA synthesis. After that, the world of custom silicon design opens up.

---

*Repository: [github.com/abishekmatevannan-afk/rv32i-core-cpu](https://github.com/abishekmatevannan-afk/rv32i-core-cpu)*
*Tools: Icarus Verilog, Wavetrace, Vivado 2025.2, GNU Make, SystemVerilog*
*Language: SystemVerilog (.sv throughout)*
