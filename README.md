# RV32I RISC-V CPU Core

A fully functional RV32I RISC-V processor core implemented in SystemVerilog from scratch.

## Architecture
- Single-cycle implementation (pipelined version in progress)
- Supports full RV32I base integer instruction set (37 instructions)
- Verified through comprehensive testbenches using Icarus Verilog and GTKWave

## Tools
- Simulator: Icarus Verilog
- Waveform viewer: GTKWave
- HDL: SystemVerilog

## Project Structure
- `src/` - RTL source files
- `tb/` - Testbenches
- `programs/` - Assembly test programs
- `sim/` - Simulation outputs (gitignored)

## Modules
- ALU
- Register File
- Program Counter
- Instruction Memory
- Control Unit
- Data Memory
- Top-level integration

## Status
- [ ] ALU
- [ ] Register File
- [ ] Program Counter
- [ ] Instruction Memory
- [ ] Control Unit
- [ ] Data Memory
- [ ] Top-level integration
