# exception_test.asm
# Sets up trap handler, fires ECALL, handler transmits mcause over UART, MRET returns

# Setup
lui  x10, 0xFFFF0        # x10 = UART_TX base
addi x11, x10, 4         # x11 = UART_STATUS

# Write trap handler address to mtvec (handler is at PC=0x20)
addi x1, x0, 0x20        # x1 = handler address (instruction 8 = PC 0x20)
csrrw x0, mtvec, x1      # mtvec = 0x20

# Enable interrupts in mstatus (MIE bit 3)
addi x2, x0, 8
csrrw x0, mstatus, x2    # mstatus.MIE = 1

# Enable external interrupt in mie (MEIE bit 11)
addi x3, x0, 0x800
csrrw x0, mie, x3        # mie.MEIE = 1

# Fire ECALL — jumps to mtvec
ecall

# Return landing point (MRET brings us here via mepc+4 in handler)
# Send 'D' for Done over UART
poll_done:
    lw   x5, 0(x11)
    andi x5, x5, 1
    beq  x5, x0, poll_done
    addi x6, x0, 0x44    # 'D'
    sw   x6, 0(x10)

done: beq x0, x0, done   # infinite loop

# Trap handler at 0x20
# Read mcause, send low byte over UART, then MRET
handler:
    csrrs x20, mcause, x0  # read mcause into x20
    # poll UART ready
poll_h:
    lw    x21, 0(x11)
    andi  x21, x21, 1
    beq   x21, x0, poll_h
    sw    x20, 0(x10)       # send mcause low byte
    # advance mepc past the ECALL (mepc + 4)
    csrrs x22, mepc, x0
    addi  x22, x22, 4
    csrrw x0, mepc, x22
    mret