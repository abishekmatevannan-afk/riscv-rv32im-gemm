# Known Limitations

This document tracks correctness gaps and architectural follow-ups that have been
identified, triaged, and consciously deferred. None of these affect the benchmarks,
demos, or numbers currently published in the README or resume — they were found
through code review after the relevant features shipped, not through any test
or benchmark failure.

Items are grouped by severity and include the fix approach for when there's time
to come back to them.

---

## High — RISC-V spec correctness gaps

### 1. CSRRWI / CSRRSI / CSRRCI write rs1's register value instead of zimm5
`csr_wd` is always the forwarded `rs1` register value (`top_pipeline.sv`). For the
immediate variants, the spec requires write data = `{27'b0, instr[19:15]}` (the
5-bit `rs1` field reinterpreted as an immediate, not a register address). There is
currently no zimm5 extraction path — `imm_sel` for CSR instructions reuses I-type
sign-extension, which is also wrong for this case.

**Fix:** add a dedicated immediate-decode path for CSR instructions that zero-extends
`instr[19:15]` directly, bypassing the normal `id_imm` mux for the three `*I` CSR
variants.

### 2. mtval CSR (0x343) not implemented
On misaligned-load, misaligned-store, and illegal-instruction traps, the spec
requires `mtval` to hold the faulting address or the bad instruction word. It
currently reads as 0. Any exception handler that calls `csrr a0, mtval` to report
the faulting address gets nothing useful.

**Fix:** add an `mtval` register to `csr_regfile.sv`, write the faulting address
(misaligned access) or raw instruction (illegal instruction) into it from
`exception_unit.sv` at trap time.

### 3. mtvec vectored mode bits not stripped
`pc_next = mtvec_out` uses the raw `mtvec` value. If software sets `mtvec.MODE=1`
(vectored mode), the low 2 bits are `01`, so the CPU jumps to a byte-unaligned
address mid-instruction, corrupting fetch.

**Fix:** use `mtvec_out & ~32'h3` for the direct-mode trap PC; full vectored-mode
support additionally needs `(mtvec_out & ~32'h3) + 4*cause_code`.

### 4. mcycle / minstret not accessible via standard CSR addresses
The PMU implements all the right counters, but they're only reachable through the
custom memory-mapped IO range. Standard CSR addresses `0xB00`/`0xC00` (mcycle) and
`0xB02`/`0xC02` (minstret) return 0 (default for unimplemented CSRs). The
`rdcycle`/`rdinstret` pseudo-instructions that real toolchains emit don't work.

**Fix:** wire the existing PMU cycle/instruction counters into `csr_regfile.sv` as
read-only CSRs at the standard addresses, in addition to the existing memory-mapped
path.

### 5. No Return Address Stack (RAS)
`JALR` (including function returns) is predicted via the BTB, indexed by the
return instruction's own PC. A function called from two or more call sites stores
different return addresses under the *same* BTB entry (they share the function's
single `ret` instruction as the index), so the second call site onward constantly
mispredicts. A small RAS (4–8 entries) pushed on `jal`-to-link-register and popped
on `jalr`-from-link-register would fix this — this is the standard architectural
solution and a common interview topic.

**Fix:** add an N-entry RAS register array in `branch_predictor.sv`; push the
return address on any `jal x1, ...` (call), pop and use as the prediction target
on any `jalr` where `rs1 == x1` (return). Needs to interact correctly with
misprediction recovery (don't push/pop on a squashed instruction).

---

## Medium — edge cases that can produce silent wrong results

### 6. Instruction-address-misalignment (cause 0) not detected
`JALR` clears bit 0 of its target (`& ~32'd1`) per spec, but does nothing about
bit 1. A `JALR` that lands on a 2-byte-aligned (but not 4-byte-aligned) address
fetches garbage instead of raising `mcause=0` (instruction address misaligned).

**Fix:** add a check in `exception_unit.sv` on the branch/jump target PC —
`target[1] != 0` → raise misalignment trap before the fetch happens.

### 7. CSR WAR hazard: stale value when read immediately after write
`CSRRW x1, csr, x2` immediately followed by `CSRR x3, csr` — the second
instruction reads the CSR combinationally in EX, but the first instruction's
write only commits to the CSR register at the next clock edge after it reaches
WB. There's no forwarding or stall path for this, so the second instruction sees
the *pre-write* value. This is architecturally the same hazard class as the
register-file load-use hazard already solved elsewhere in the pipeline, just
applied to CSR state instead of GPRs.

**Fix:** either forward the in-flight CSR write value (mirroring the existing
register-file forwarding paths), or stall one cycle on detected CSR-after-CSR
same-address hazards — the forwarding approach is lower cost since the
infrastructure pattern already exists for GPRs.

### 8. Only 64 BTB entries (PC[7:2] index = 256-byte code window)
Programs larger than 256 bytes alias BTB entries by PC. The existing tag check
(added earlier this project) prevents *wrong* predictions on aliased entries, but
causes a cold-miss-equivalent penalty (prediction suppressed, correct target still
resolved in EX) whenever two branches in different 256-byte windows share an
index. Low impact on the current benchmark programs (small, fit within one
window); would show up as a measurably higher misprediction rate on larger
compiled programs.

**Fix:** widen the BTB index (more entries) and/or add a global history register
(GHR) for correlated prediction, discussed earlier in this project's design
process — deferred for the same reason as the RAS.

---

## Low — missing hardware features relevant to real OS/runtime software

### 9. Unimplemented-CSR accesses are silently legal
Reading or writing a CSR address that isn't implemented (`mhartid` 0xF14, `misa`
0x301, `marchid` 0x302, `mvendorid` 0xF11, etc.) returns 0 and silently drops the
write, rather than raising an illegal-instruction trap. This is spec-legal
behavior in the strictest sense (CSR space is large and sparse), but some OS/ABI
environments rely on accesses to genuinely nonexistent CSRs trapping, since that's
how they probe for hardware feature support at boot.

**Fix:** add an explicit "is this CSR address implemented" decode in
`csr_regfile.sv`; route a miss to the illegal-instruction trap path instead of
silently returning 0.

### 10. mstatus only implements the MIE bit
Standard fields like `MPP` (bits 12:11), `MPIE` (bit 7), and others required for a
real M-mode OS or runtime are not stored — only the single global interrupt-enable
bit. `MRET` currently sets `MIE` unconditionally rather than the spec-correct
behavior of restoring `MIE ← MPIE` and setting `MPIE ← 1`. Sufficient for the
exception handler demo built for this project (single trap level, no nested
interrupts), insufficient for anything resembling a real privileged-mode runtime.

**Fix:** extend `csr_regfile.sv`'s `mstatus` storage to the full field set needed,
update the `MRET` path in `csr_regfile.sv`/`exception_unit.sv` to perform the
correct MPIE/MIE swap.

---

## How to use this document

When picking up the project again: items in **High** are the ones most likely to
matter if real compiled C code or a more thorough RISC-V compliance test is run
against this core. **Medium** items are real but narrow — they require a specific
instruction sequence to trigger. **Low** items only matter if the project grows
toward supporting an actual OS or runtime, which is out of scope for the current
goals.

None of these were caught by the existing test suite, which is itself worth noting:
the testbenches exercise the instructions and CSR operations the benchmark programs
actually use, but none of the benchmark programs exercise CSRRS/CSRRC,
CSRRWI/SI/CI, FENCE, EBREAK, mtval, vectored mtvec, or multi-callsite JALR returns
— which is exactly why a code review (rather than a failing test) is what surfaced
most of this list.

---

## Synthesis / Timing

### 11. dcache BRAM inference failure

`dcache data[]` maps to RAM64M×176 distributed RAM despite `(* ram_style = "block" *)` attribute. Root cause: Port B `always_ff` requires a conditional bypass (`write_merge` forwarding) for write-hit coherence. Vivado requires an unconditional synchronous read on the BRAM output register for inference. Removing the bypass creates a combinational loop: `write_merge` is computed from `cached_word_q`, and `cached_word_q` would be driven by `write_merge` in the forwarding branch, creating a zero-delay cycle. Separating the read into an unconditional `bram_rd_q` register and making `cached_word_q` a combinational wire broke simulation (`LBU`/`LHU` returning `0x00000000`, `pmacc_pipeline` returning half the expected value).

**Fix:** Accept one extra stall cycle on write-hit loads (to allow the merge base to come from a registered BRAM output), or restructure the write-hit forwarding path to avoid the feedback loop. Not implemented — distributed RAM at this size (1 KB) has acceptable timing impact and dcache is not on the critical path.

### 12. Branch predictor combinational read path (current critical path)

The BHT (64×2 flip-flop array) is read combinationally via a 64:1 mux tree. This mux tree plus BTB tag comparison feeds `predict_taken`, which drives the `pc_next` mux, which feeds the icache prefetch address register. This is the current critical path at 13.476 ns, limiting Fmax to ~79 MHz.

**Fix:** Register `predict_taken` and `predict_target` with a one-cycle validity gate suppressing stale predictions after any `pc_next` override (trap, mret, jump mispredict, branch mispredict). Expected gain: 4–8 MHz. Not implemented — the validity gate must interact correctly with all five override conditions and three stall types (cache stall, divider stall, SIMD stall); correctness risk outweighs the gain at this stage.

### 13. SIMD timing cost from registered inputs

Registered SIMD inputs (`simd_a_q`, `simd_b_q`, `simd_acc_q`) and a two-cycle stall state machine (`simd_busy` 3-state: IDLE→WAIT1→WAIT2) were added to remove the forwarding network from the SIMD carry-chain timing path. Cost: SIMD instructions take three pipeline cycles instead of one (2 stall + 1 advance). GEMM SIMD speedup degraded from 4.08× to 3.63× vs scalar (293 cycles vs 261 before the fix).

### 14. Achieved Fmax vs 100 MHz target

Design closes at ~79 MHz on xc7a200tsbg484-2 with a 10 ns constraint. Remaining WNS: -2.730 ns. The gap is entirely explained by the branch predictor combinational read path (item 12). No other paths are close to failing once that path is addressed.

---

## Fixed Bugs Worth Documenting

### 15. mcause for machine external interrupt (fixed in b728bd3)

`trap_cause` was `0x80000011` (17 decimal) instead of `0x8000000B` (11 decimal, RISC-V spec machine external interrupt code). Written as if 11 were hex. `tb_exception_unit.sv` was checking mcause but had the wrong expected value hardcoded, so the test passed while silently validating incorrect behavior. Both RTL and expected value corrected together. Lesson: a test that checks the wrong expected value is worse than no test — it creates false confidence.