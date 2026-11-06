# UVM Testbench for the ALU

> *"Program testing can be used to show the presence of bugs, but never to show their absence!"*
> — Edsger W. Dijkstra

A UVM verification environment for the core's ALU ([`src/alu.sv`](../../src/alu.sv)), built with UVM 2020.3.1 and run on Verilator. Constrained-random stimulus goes in through an agent, a scoreboard checks every result against an independent reference model, and functional coverage measures what was actually exercised.

## Why I built this

The directed testbenches I wrote have an issue of writer's bias where the 'expected result' is something I wrote to be. I pick the inputs and work out the expected answer by hand, so it can only check the cases I thought of. My original ALU testbench even prints `FAIL` without ever failing the run. Industry verification teams use UVM to close that gap. Random stimulus finds cases nobody wrote down, a reference model judges every one of them, and coverage says when you have tested enough. I wanted to learn it by building one.

I picked the ALU on purpose. It is the simplest block in the core, so the hard part would be the methodology and not the design. 

## Results

| Test | Transactions | Mismatches | Functional coverage |
|------|--------------|------------|---------------------|
| `alu_smoke_test` | 20 | 0 | 11.8% |
| `alu_rand_test`, seed 1 | 10,000 | 0 | 99.00% |
| `alu_rand_test`, seed 2 | 10,000 | 0 | 98.50% |
| `alu_rand_test`, seed 3 | 10,000 | 0 | 98.17% |

A 10,000-transaction run takes about 45 s. Removing `$signed` from the RTL's SRA in a scratch copy made the scoreboard report 99 mismatches in 3,000 transactions, so the checker does catch real bugs.

## How it fits together

<p align="center">
  <img src="../../docs/uvm/uvm_alu_tb.png" alt="UVM testbench for the ALU: test, env, agent, scoreboard, coverage, interface, DUT" width="560">
</p>

The sequencer hands each `seq_item` to the driver through its export (○ to □). The driver drives the pins through the interface, and the monitor rebuilds every transaction from those pins. Its analysis port (◇) broadcasts each one to both the scoreboard and coverage. Source: [`uvm_alu_tb.drawio`](../../docs/uvm/uvm_alu_tb.drawio), editable in draw.io.

| Component | Job |
|-----------|-----|
| `alu_item` | One operation: random `a`, `b`, `alu_ctrl`, weighted toward corner values (0, 1, `0x7FFFFFFF`, `0x80000000`, all-ones, checkerboards), with about 5% illegal opcodes and shift amounts weighted to 0, 1 and 31 |
| `alu_driver` | Drives one operation per clock through a clocking block and pulses `valid` |
| `alu_monitor` | Rebuilds each operation from the pins, publishing only when `valid` is high |
| `alu_scoreboard` | Reference model written from the RV32I spec, not from `alu.sv`: SRA from a sign-fill mask instead of `>>>`, SLT from the sign bits instead of `$signed`. Errors if it checked zero transactions |
| `alu_coverage` | 3 crosses (533 bins) plus 11 coverpoints, described below |
| `alu_if` | Testbench clock, driver and monitor clocking blocks, and an assertion that `zero == (result == 0)` |

## Coverage

| Cross | Bins | Covers |
|-------|------|--------|
| Register ops (ADD, SUB, AND, OR, XOR, SLT, SLTU) × `a` class × `b` class | 343 | Sign and overflow corners, strict compares |
| Shift ops × `a` class × shift amount × upper bits of `b` set or clear | 168 | Only `b[4:0]` is used; SRA vs SRL sign fill |
| Every legal op × `zero` flag | 22 | `zero` is correct for every op, not just SUB |

Illegal opcodes (`0xB`–`0xF`) and LUI's `b`-only behavior have their own coverpoints. On seed 1 the crosses reach 340/343, 165/168 and 22/22.

## Verilator limits found along the way

| Limitation | Measured | Workaround |
|------------|----------|------------|
| `soft` does not make a `dist` yield to an inline `randomize() with {}` | 11 of 200 randomizations succeeded | Non-rand knobs (`ctrl_dist_en`, `ab_dist_en`) that a sequence clears first: 300/300 |
| Two `dist`s on overlapping bits of `b` | 25% of `randomize()` calls failed | Guard them so only one applies per op: 0 failures in 2,000 |
| `ignore_bins ... binsof()` inside a `cross` is ignored | Coverage capped at about 40% by bins that could never be hit | Per-op-group coverpoints restricted with `iff`: 99% |
| Type-level `get_coverage()` always returns 0 | — | Report `get_inst_coverage()` |
| `$error` in an assertion stops the simulation before the UVM summary | — | `` `uvm_error `` in the assertion, counted like any mismatch |
| The simulator exits 0 even when UVM reports errors | — | `make uvm-alu` reads the UVM summary and fails on any error |

## Run it

```bash
make uvm-alu                              # alu_smoke_test, seed 1
make uvm-alu TEST=alu_rand_test SEED=7    # 10,000 transactions
```

Each run prints PASS or FAIL and writes `sim/uvm_alu_<test>_<seed>.log` plus coverage data in `.dat`. The first compile takes about 40 s.

Requires Verilator 5.x with the z3 solver, and UVM 2020.3.1 at `UVM_HOME` (default `~/tools/uvm-core-2020.3.1/src`).

## Files

| File | What |
|------|------|
| `alu/alu_if.sv` | Interface, clocking blocks, zero-flag assertion |
| `alu/alu_pkg.sv` | Transaction, driver, monitor, agent, scoreboard, coverage, env, sequence, tests |
| `alu/tb_alu_uvm.sv` | Top module: clock, DUT, `run_test()` |
