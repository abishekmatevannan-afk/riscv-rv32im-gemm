# div_pipeline.s — RV32M divide/remainder through the full pipeline
# Each result is checked by tb/tb_div_pipeline.sv from the register file.
    li   a0, 100
    li   a1, 7
    div  a2, a0, a1       # 14
    rem  a3, a0, a1       # 2
    li   a1, -3
    div  a4, a0, a1       # -33
    rem  a5, a0, a1       # 1
    li   t0, -100
    div  a6, t0, a1       # 33
    rem  a7, t0, a1       # -1
    divu s2, a0, a1       # 100 / 0xFFFFFFFD = 0
    remu s3, a0, a1       # 100
    div  s4, a0, zero     # divide by zero: -1
    rem  s5, a0, zero     # remainder by zero: dividend (100)
    div  s6, a0, a1       # back-to-back divides on dependent data
    div  s7, s6, a1       # -33 / -3 = 11
    add  s8, s7, s7       # result used right away: 22
done:
    j    done
