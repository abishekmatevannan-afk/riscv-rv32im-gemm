# blackhole.s — Schwarzschild black hole ray tracer for the RV32IM core
#
# Renders a 64x64 grayscale image of a non-spinning black hole in front of a
# checkerboard sky, and sends it over the UART one byte per pixel (row-major).
#
# Physics (units G = c = M = 1, horizon at r = 2):
#   A light ray moves in a plane and obeys  u'' = 3u^2 - u,  u = 1/r, ' = d/dphi.
#   Every pixel at the same distance rho from the image center follows the same
#   path (rotated), so the program traces 89 rays (rho = 1..89) once, stores the
#   result in a table, then shades all 4096 pixels from the table.
#
# Number format: Q8.24 fixed point (1.0 = 2^24). A product is mul + mulh + shifts.
# blackhole_ref.py is a bit-exact Python copy of this program; the CPU's output
# must match it byte for byte. Constants below are checked against it.
#
# Memory (data SRAM):
#   0x000-0x05C  CORDIC angle table atan(2^-i), i = 0..23
#   0x100 + 8*rho     sin of the ray's final angle          (per table entry)
#   0x104 + 8*rho     den = cos * SQ * rho, 0 = captured, -1 = rear sky

.equ ONE, 16777216        # 1.0
.equ U0, 559240           # 1/r_cam, camera at r = 30
.equ UF, 63752686         # u'(0) * rho = U0 * sqrt(1 - 2/30) * focal(118)
.equ HALF, 8388608        # u >= 1/2 means r <= 2: the ray fell in
.equ UFAR, 16777          # u < 1/1000 and moving outward: the ray escaped
.equ NMAX, 12867          # step limit, ~2 orbits (rays skimming the photon sphere)
.equ PI, 52707179
.equ TWO_PI, 105414357
.equ HALF_PI, 26353589
.equ CORDIC_K, 10188014   # CORDIC gain correction, prod 1/sqrt(1 + 4^-i)
.equ SQ, 1677722          # checker square size 0.1 on the sky plane

.equ UART, 0xFFFF0000     # TX data at +0, TX status at +4 (bit 0 = FIFO not full)
.equ TABLE, 0x100
.equ RHO_END, 90          # table entries rho = 1..89
.equ NPIX, 64

# ============================================================================
# 1. CORDIC angle table: atan(2^-i) in Q8.24, written to data memory
# ============================================================================
start:
    li   t0, 13176795    # atan(2^-0)
    sw   t0, 0(zero)
    li   t0, 7778716     # atan(2^-1)
    sw   t0, 4(zero)
    li   t0, 4110060     # atan(2^-2)
    sw   t0, 8(zero)
    li   t0, 2086331     # atan(2^-3)
    sw   t0, 12(zero)
    li   t0, 1047214     # atan(2^-4)
    sw   t0, 16(zero)
    li   t0, 524117      # atan(2^-5)
    sw   t0, 20(zero)
    li   t0, 262123      # atan(2^-6)
    sw   t0, 24(zero)
    li   t0, 131069      # atan(2^-7)
    sw   t0, 28(zero)
    li   t0, 65536       # atan(2^-8)
    sw   t0, 32(zero)
    li   t0, 32768       # atan(2^-9)
    sw   t0, 36(zero)
    li   t0, 16384       # atan(2^-10)
    sw   t0, 40(zero)
    li   t0, 8192        # atan(2^-11)
    sw   t0, 44(zero)
    li   t0, 4096        # atan(2^-12)
    sw   t0, 48(zero)
    li   t0, 2048        # atan(2^-13)
    sw   t0, 52(zero)
    li   t0, 1024        # atan(2^-14)
    sw   t0, 56(zero)
    li   t0, 512         # atan(2^-15)
    sw   t0, 60(zero)
    li   t0, 256         # atan(2^-16)
    sw   t0, 64(zero)
    li   t0, 128         # atan(2^-17)
    sw   t0, 68(zero)
    li   t0, 64          # atan(2^-18)
    sw   t0, 72(zero)
    li   t0, 32          # atan(2^-19)
    sw   t0, 76(zero)
    li   t0, 16          # atan(2^-20)
    sw   t0, 80(zero)
    li   t0, 8           # atan(2^-21)
    sw   t0, 84(zero)
    li   t0, 4           # atan(2^-22)
    sw   t0, 88(zero)
    li   t0, 2           # atan(2^-23)
    sw   t0, 92(zero)

# ============================================================================
# 2. Trace one ray per radius rho and fill the table
#    s1 = TABLE  s2 = ONE  s3 = HALF  s4 = UFAR  s5 = NMAX  s6 = rho  s7 = RHO_END
#    per ray: t2 = u  t1 = v (= du/dphi)  a0 = step count n  a1 = entry address
# ============================================================================
    li   s1, TABLE
    li   s2, ONE
    li   s3, HALF
    li   s4, UFAR
    li   s5, NMAX
    li   s6, 1
    li   s7, RHO_END

trace:
    slli a1, s6, 3
    add  a1, a1, s1           # a1 = &table[rho]
    li   t0, UF
    div  t1, t0, s6           # v = u'(0) = UF / rho  (ray aimed inward)
    li   t2, U0               # u = 1/r_cam

    # leapfrog: v += (h/2) * a(u),  a(u) = u * (3u - 1),  h = 2^-10
    add  t3, t2, t2
    add  t3, t3, t2
    sub  t3, t3, s2           # 3u - 1
    mul  t4, t2, t3
    mulh t5, t2, t3
    srli t4, t4, 24
    slli t5, t5, 8
    or   t4, t4, t5           # a = u * (3u - 1) in Q8.24
    srai t4, t4, 11           # * h/2
    add  t1, t1, t4
    li   a0, 0

step:
    srai t4, t1, 10
    add  t2, t2, t4           # u += h * v
    addi a0, a0, 1            # phi = n * h
    bge  t2, s3, captured     # r <= 2: inside the horizon
    bge  t2, s4, keep_going
    bltz t1, escaped          # far away and moving outward
keep_going:
    bge  a0, s5, captured     # orbiting the photon sphere too long: call it dark
    add  t3, t2, t2
    add  t3, t3, t2
    sub  t3, t3, s2           # 3u - 1
    mul  t4, t2, t3
    mulh t5, t2, t3
    srli t4, t4, 24
    slli t5, t5, 8
    or   t4, t4, t5           # a = u * (3u - 1)
    srai t4, t4, 10
    add  t1, t1, t4           # v += h * a
    j    step

escaped:
    # The rest of the path is almost a straight line: it reaches u = 0 after
    # another u/|v| radians. Final angle phi = n*h + u/|v|.
    neg  t4, t1
    srai t4, t4, 10
    slli t5, t2, 14
    div  t5, t5, t4           # u/|v| in Q8.24
    slli t6, a0, 14           # n * h in Q8.24
    add  t6, t6, t5           # phi
    li   t0, PI
    sub  a2, t0, t6           # beta = pi - phi: angle from the axis behind the hole
    li   a3, TWO_PI
    neg  a4, t0               # -pi
wrap:
    blt  a4, a2, wrapped      # bring beta into (-pi, pi]
    add  a2, a2, a3
    j    wrap
wrapped:
    li   t0, HALF_PI
    bge  a2, t0, rear         # |beta| >= 90 deg: the ray heads back past the camera
    neg  t0, t0
    ble  a2, t0, rear

    # CORDIC rotation: start at (K, 0), rotate by beta -> (cos beta, sin beta)
    li   a5, CORDIC_K         # x
    li   a6, 0                # y
    li   a7, 0                # i
    li   t3, 0                # &atan[i]
    li   s8, 24
cordic:
    sra  t4, a6, a7           # y >> i
    sra  t5, a5, a7           # x >> i
    lw   t6, 0(t3)            # atan(2^-i)
    bltz a2, cordic_neg
    sub  a5, a5, t4
    add  a6, a6, t5
    sub  a2, a2, t6
    j    cordic_next
cordic_neg:
    add  a5, a5, t4
    sub  a6, a6, t5
    add  a2, a2, t6
cordic_next:
    addi a7, a7, 1
    addi t3, t3, 4
    blt  a7, s8, cordic

    # den = cos * SQ * rho, so a pixel's checker cell is x * sin / den
    li   t0, SQ
    mul  t4, a5, t0
    mulh t5, a5, t0
    srli t4, t4, 24
    slli t5, t5, 8
    or   t4, t4, t5
    mul  t4, t4, s6
    blez t4, rear
    sw   a6, 0(a1)
    sw   t4, 4(a1)
    j    next_ray

captured:
    sw   zero, 0(a1)
    sw   zero, 4(a1)          # den = 0: black
    j    next_ray
rear:
    li   t0, -1
    sw   t0, 4(a1)            # den = -1: rear sky
next_ray:
    addi s6, s6, 1
    blt  s6, s7, trace

# ============================================================================
# 3. Shade every pixel from the table and send it over the UART
#    s0 = UART  s8 = py  s9 = px  s10 = NPIX  s11 = y  gp = y*y
#    pixel centers are at odd half-pixel coordinates x, y = -63, -61, ..., 63
# ============================================================================
    li   s0, UART
    li   s10, NPIX
    li   s8, 0
row:
    slli s11, s8, 1
    addi s11, s11, -63        # y = 2*py - 63
    mul  gp, s11, s11
    li   s9, 0
pixel:
    slli t0, s9, 1
    addi t0, t0, -63          # x = 2*px - 63
    mul  t1, t0, t0
    add  t1, t1, gp           # q = x^2 + y^2

    # rho = round(sqrt(q)), digit-by-digit square root
    li   a2, 0                # result
    li   a3, 4096             # bit
isqrt:
    add  t2, a2, a3
    blt  t1, t2, isqrt_zero
    sub  t1, t1, t2
    srli a2, a2, 1
    add  a2, a2, a3
    j    isqrt_next
isqrt_zero:
    srli a2, a2, 1
isqrt_next:
    srli a3, a3, 2
    bnez a3, isqrt
    bge  a2, t1, rounded      # remainder > result means sqrt(q) >= result + 0.5
    addi a2, a2, 1
rounded:
    slli t2, a2, 3
    add  t2, t2, s1           # &table[rho]
    lw   a4, 4(t2)            # den
    beqz a4, black
    bltz a4, rear_pixel
    lw   a5, 0(t2)            # sin

    # checker cell (cx, cy) = floor(x * sin / den), floor(y * sin / den)
    mul  t3, t0, a5
    div  a6, t3, a4
    rem  a7, t3, a4
    bgez a7, cx_done
    addi a6, a6, -1           # RISC-V div truncates; floor needs one less for negatives
cx_done:
    mul  t3, s11, a5
    div  t4, t3, a4
    rem  t5, t3, a4
    bgez t5, cy_done
    addi t4, t4, -1
cy_done:
    add  a6, a6, t4
    andi a6, a6, 1
    li   a0, 230              # light square
    beqz a6, send
    li   a0, 40               # dark square
    j    send
black:
    li   a0, 0
    j    send
rear_pixel:
    li   a0, 100

send:
    lw   t6, 4(s0)            # wait until the TX FIFO has room
    andi t6, t6, 1
    beqz t6, send
    sw   a0, 0(s0)
    addi s9, s9, 1
    blt  s9, s10, pixel
    addi s8, s8, 1
    blt  s8, s10, row

done:
    j    done
