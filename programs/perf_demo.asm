# Runs loop, reads counters, sends low byte of each over UART

# setup
lui  x10, 0xFFFF0        # UART TX
addi x11, x10, 4         # UART STATUS
lui  x12, 0xFFFF2        # PERF base

# run loop
addi x1, x0, 0           # accumulator
addi x2, x0, 10          # loop counter
addi x3, x0, 15          # increment

loop:
add  x1, x1, x3
addi x2, x2, -1
bne  x2, x0, loop

# read counters
lw   x20, 0(x12)         # cycles
lw   x21, 4(x12)         # instructions
lw   x22, 8(x12)         # branches
lw   x23, 12(x12)        # mispredictions

# send low byte of each counter + newline between each

# send cycles low byte
poll1: lw x7, 0(x11)
       andi x7, x7, 1
       beq  x7, x0, poll1
       sw   x20, 0(x10)

# send instructions low byte
poll2: lw x7, 0(x11)
       andi x7, x7, 1
       beq  x7, x0, poll2
       sw   x21, 0(x10)

# send branches low byte
poll3: lw x7, 0(x11)
       andi x7, x7, 1
       beq  x7, x0, poll3
       sw   x22, 0(x10)

# send mispredictions low byte
poll4: lw x7, 0(x11)
       andi x7, x7, 1
       beq  x7, x0, poll4
       sw   x23, 0(x10)

# send newline
addi x24, x0, 10
poll5: lw x7, 0(x11)
       andi x7, x7, 1
       beq  x7, x0, poll5
       sw   x24, 0(x10)

# done
done: beq x0, x0, done