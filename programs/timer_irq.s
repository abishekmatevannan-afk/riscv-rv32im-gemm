# timer_irq.s — machine timer interrupts through the full pipeline
# Checked by tb/tb_precise_trap.sv (cpu_timer section) from the register file and CSRs.
#
#   1. Directed Known_limitations §26 case: a misaligned lw traps while the
#      instruction behind it depends on it (trap and load-use stall in the
#      same cycle). The handler must run.
#   2. The timer fires every PERIOD cycles while a loop runs loads with
#      dependent instructions, MULs and stores. Every interrupt must reach the
#      handler, and the loop's results must be exact (precise interrupts:
#      the interrupted instruction re-executes after mret).
#
# Register use: main uses t0-t4, a0-a3, s0-s3, s8. The handler only touches
# t5, t6, s6, s7, s9, s10 (no stack needed). tp = timer base.
    .equ PERIOD, 61
    .equ ITERS, 150

    j    main

# Trap handler: interrupts re-arm the timer, exceptions skip the instruction
handler:
    csrrs t5, mcause, x0
    blt   t5, x0, h_irq          # mcause bit 31 set: interrupt
    addi  s7, s7, 1              # exception count
    mv    s6, t5                 # last exception cause
    csrrs t6, mepc, x0
    addi  t6, t6, 4              # skip the faulting instruction
    csrrw x0, mepc, t6
    mret
h_irq:
    addi  s10, s10, 1            # interrupt count
    mv    s9, t5                 # last interrupt cause
    lw    t6, 8(tp)              # mtimecmp lo += PERIOD (hi stays 0)
    addi  t6, t6, PERIOD
    sw    t6, 8(tp)
    mret

main:
    li    tp, 0xFFFF4000
    li    t0, handler
    csrrw x0, mtvec, t0

    # 0: CSR immediate forms take the rs1 field as a constant, not a register
    csrrwi x0, mie, 21           # mie = 0b10101
    csrrsi x0, mie, 10           # mie = 0b11111
    csrrci x0, mie, 5            # mie = 0b11010 = 26
    csrrs  s3, mie, x0           # s3 = 26
    csrrwi x0, mie, 0

    # 1: misaligned load with a dependent instruction right behind it
    li    a0, 0x101
    lw    t1, 0(a0)              # traps, mcause 4; handler resumes at the add
    add   t2, t1, t1             # load-use on t1, same cycle as the trap

    # 2: arm the timer PERIOD cycles out (low word to all ones first)
    li    t0, -1
    sw    t0, 8(tp)
    sw    x0, 12(tp)             # mtimecmp hi = 0
    lw    t0, 0(tp)              # mtime lo
    addi  t0, t0, PERIOD
    sw    t0, 8(tp)
    li    t0, 0x80
    csrrs x0, mie, t0            # MTIE
    csrrsi x0, mstatus, 8        # MIE

    # 3: work loop, interrupted many times
    li    a1, 0x200
    li    t0, 3
    sw    t0, 0(a1)
    li    s0, 0
    li    s1, 0
    li    s2, 0
    li    a2, ITERS
    li    a3, 7
loop:
    lw    t1, 0(a1)              # 3
    add   t2, t1, t1             # 6, load-use on t1
    add   s0, s0, t2             # s0 += 6
    mul   t3, t2, a3             # 42
    add   s1, s1, t3             # s1 += 42
    sw    s2, 4(a1)              # store the old count
    lw    t4, 4(a1)
    addi  s2, t4, 1              # s2 = count + 1, load-use on t4
    blt   s2, a2, loop

    li    s8, 1                  # done
done:
    j     done
