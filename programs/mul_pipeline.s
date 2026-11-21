# mul_pipeline.s — RV32M multiply through the full pipeline, around D$ misses
# Each result is checked by tb/tb_mul_div.sv (cpu_mul section) from the register file.
# Most MULs here enter EX while the instruction ahead of them misses in the
# D-cache, so the registered multiplier must hold its state under freeze.
    li   t0, 6
    li   t1, 7
    li   t2, -3
    li   a1, 0x100        # line A
    li   a2, 0x1100       # same D$ index as 0x100, other tag; aliases 0x100 in DSRAM
    li   a3, 0x200        # cold lines B, C, D at 0x200, 0x210, 0x220
    li   s0, 1000
    sw   s0, 0(a1)        # cold store miss: line A allocated and dirty
    # 1: load miss with dirty writeback, then an independent MUL
    lw   s1, 0(a2)        # evicts line A (writes 1000 back), refills via alias: 1000
    mul  s2, t0, t1       # 42, enters EX during the miss
    # 2: load miss, then MULH (upper word)
    lw   s3, 0(a3)        # cold miss: 0
    mulh s4, t2, t1       # -21 -> upper word 0xFFFFFFFF
    # 3: load miss, then back-to-back dependent MULs
    lw   s5, 16(a3)       # cold miss: 0
    mul  s6, t0, t1       # 42
    mul  s7, s6, t1       # 294, s6 forwarded from the MUL in MEM
    # 4: load-use: the MUL needs the value the missing load brings in
    lw   s8, 0(a1)        # miss (line A was evicted): 1000
    mul  s9, s8, t1       # 7000
    # 5: store miss, then MULHU
    sw   t1, 32(a3)       # cold store miss
    mulhu s10, t2, t2     # 0xFFFFFFFD^2 -> upper word 0xFFFFFFFA
    add  s11, s9, s7      # results used afterwards: 7294
done:
    j    done
