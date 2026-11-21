# mmio_once.s — an MMIO store held in MEM by a back-end stall must write once
# Checked by tb/tb_axi4_lite.sv, T8 (register values plus write counts at the
# UART and parallel MAC). Each store is followed by a MUL or DIV, so it sits
# in MEM while the multiplier or divider stalls the pipeline.
    li   t0, 0xFFFF0000   # UART TX
    li   t1, 0xFFFE0000   # parallel MAC base
    li   t2, 100
    li   t3, 7
    # 1: UART TX store, then DIV: the store waits in MEM for the whole divide
    li   a0, 0x41
    sw   a0, 0(t0)
    div  s0, t2, t3       # 14
    # 2: load A = B = all ones into the parallel MAC
    li   a1, 0x01010101
    sw   a1, 0x10(t1)
    sw   a1, 0x14(t1)
    sw   a1, 0x18(t1)
    sw   a1, 0x1C(t1)
    sw   a1, 0x20(t1)
    sw   a1, 0x24(t1)
    sw   a1, 0x28(t1)
    sw   a1, 0x2C(t1)
    # 3: CTRL start in accumulate mode, then DIV. Every repeated CTRL write
    #    would restart the k loop on top of the kept accumulator, so
    #    C[0][0] ends up above 4 if the store fires more than once.
    li   a2, 3
    sw   a2, 0(t1)
    div  s1, t2, t3       # 14
    # 4: UART TX store, then MUL (a 1-cycle stall)
    li   a0, 0x42
    sw   a0, 0(t0)
    mul  s2, t2, t3       # 700
    # 5: wait for the accelerator, read back C[0][0]
poll:
    lw   a3, 4(t1)
    beqz a3, poll
    lw   s3, 0x80(t1)     # C_INT32[0][0] = 4
done:
    j    done
