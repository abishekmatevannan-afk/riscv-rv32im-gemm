#!/usr/bin/env python3
"""Reference models for the RV32IM black hole renderer (blackhole.s).

  python3 blackhole_ref.py expected          write expected.hex + run physics checks
  python3 blackhole_ref.py png IN.hex OUT.png render a 64x64 byte image (one hex byte
                                              per line) as an 8x upscaled PNG

Two models of the same scene:
  fixed_image()  bit-exact copy of what blackhole.s computes (Q8.24 fixed point,
                 RISC-V div/rem/shift semantics). The CPU must match it exactly.
  float_image()  the same physics in float64 with a fine RK4 integrator, used to
                 measure how much the fixed-point version loses.

Physics: Schwarzschild black hole, units G = c = M = 1 (horizon at r = 2).
A photon moves in a plane and obeys  u'' = 3u^2 - u,  with u = 1/r, ' = d/dphi.
"""
import math
import re
import sys
import zlib
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ---------------------------------------------------------------- scene
R_CAM = 30.0          # camera radius
FOCAL = 118           # pinhole focal length, in half-pixel units
N = 64                # image is N x N; pixel centers at odd half-pixel coords -63..63
SQUARE = 0.1          # checker square size on the sky plane (tan-angle units)
R_FAR = 1000.0        # a ray counts as escaped once r > R_FAR and moving outward
COLOR = {"black": 0, "rear": 100, "light": 230, "dark": 40}

# ---------------------------------------------------------------- Q8.24 constants
Q = 24
ONE = 1 << Q
H_SHIFT = 10                                   # step h = 2^-10 rad
N_ITER = 24                                    # CORDIC iterations


def q(x):
    return int(round(x * ONE))


def s32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x


def fmul(a, b):                                # mul + mulh + shifts in blackhole.s
    return s32((a * b) >> Q)


def rv_div(a, b):                              # RISC-V DIV: truncate toward zero
    if b == 0:
        return -1
    qt = abs(a) // abs(b)
    return s32(qt if (a < 0) == (b < 0) else -qt)


def rv_rem(a, b):                              # RISC-V REM: sign follows dividend
    if b == 0:
        return a
    return s32(a - rv_div(a, b) * b)


U0 = ONE // int(R_CAM)                         # 1/r_cam
CS = q(math.sqrt(1 - 2 / R_CAM))               # sqrt(1 - 2M/r_cam): static-observer factor
UF = fmul(U0, CS) * FOCAL                      # u'0 = UF / rho
CONST = {
    "ONE": ONE,
    "U0": U0,
    "UF": UF,
    "HALF": ONE // 2,                          # u >= 1/2  <=>  r <= 2M: captured
    "UFAR": q(1 / R_FAR),
    "NMAX": int(4 * math.pi * (1 << H_SHIFT)), # give up after ~2 orbits (photon ring)
    "PI": q(math.pi),
    "TWO_PI": q(2 * math.pi),
    "HALF_PI": q(math.pi / 2),
    "CORDIC_K": q(math.prod(1 / math.sqrt(1 + 4.0 ** -i) for i in range(N_ITER))),
    "SQ": q(SQUARE),
}
ATAN = [q(math.atan(2.0 ** -i)) for i in range(N_ITER)]
RHO_MAX = math.isqrt((N - 1) ** 2 * 2) + 1     # 89: largest rounded pixel radius


# ---------------------------------------------------------------- fixed-point model
def trace_fixed(rho):
    """Return (sin, den) for one table entry; den 0 = captured, -1 = rear sky."""
    u = U0
    v = rv_div(UF, rho)
    a = fmul(u, u + u + u - ONE)
    v = v + (a >> (H_SHIFT + 1))               # leapfrog: initial half kick
    n = 0
    while True:
        u = u + (v >> H_SHIFT)
        n += 1
        if u >= CONST["HALF"]:
            return 0, 0
        if u < CONST["UFAR"] and v < 0:
            break
        if n >= CONST["NMAX"]:
            return 0, 0
        a = fmul(u, u + u + u - ONE)
        v = v + (a >> H_SHIFT)
    # escaped: extrapolate the last bit of the straight-line asymptote to u = 0
    d = rv_div(u << 14, (-v) >> 10)
    beta = CONST["PI"] - ((n << 14) + d)       # angle from the axis behind the hole
    while beta <= -CONST["PI"]:
        beta += CONST["TWO_PI"]
    if beta >= CONST["HALF_PI"] or beta <= -CONST["HALF_PI"]:
        return 0, -1
    x, y, z = CONST["CORDIC_K"], 0, beta       # CORDIC rotation: (x, y) -> (cos, sin)
    for i in range(N_ITER):
        if z >= 0:
            x, y, z = x - (y >> i), y + (x >> i), z - ATAN[i]
        else:
            x, y, z = x + (y >> i), y - (x >> i), z + ATAN[i]
    den = fmul(x, CONST["SQ"]) * rho
    if den <= 0:
        return 0, -1
    return y, den


def build_table():
    table = [(0, 0)]                           # rho = 0 never occurs (pixels are off-center)
    for rho in range(1, RHO_MAX + 1):
        table.append(trace_fixed(rho))
    return table


def isqrt_round(qv):                           # digit-by-digit isqrt, then round
    res, bit = 0, 1 << 12
    while bit:
        if qv >= res + bit:
            qv -= res + bit
            res = (res >> 1) + bit
        else:
            res >>= 1
        bit >>= 2
    return res + 1 if qv > res else res


def floor_div(a, b):                           # div, rem, and a fix-up for negatives
    qt, r = rv_div(a, b), rv_rem(a, b)
    return qt - 1 if r < 0 else qt


def shade_fixed(table, x, y):
    rho = isqrt_round(x * x + y * y)
    sin, den = table[rho]
    if den == 0:
        return COLOR["black"]
    if den < 0:
        return COLOR["rear"]
    cx, cy = floor_div(x * sin, den), floor_div(y * sin, den)
    return COLOR["light"] if (cx + cy) & 1 == 0 else COLOR["dark"]


def fixed_image(table=None):
    table = table or build_table()
    return [shade_fixed(table, 2 * px - (N - 1), 2 * py - (N - 1))
            for py in range(N) for px in range(N)]


# ---------------------------------------------------------------- float64 model
def trace_float(rho, h=1e-4):
    """Same physics as trace_fixed, in float64 with RK4. Returns beta or None."""
    u = 1 / R_CAM
    v = (1 / R_CAM) * math.sqrt(1 - 2 / R_CAM) * FOCAL / rho
    acc = lambda uu: 3 * uu * uu - uu
    phi = 0.0
    while phi < 4 * math.pi:
        k1u, k1v = v, acc(u)
        k2u, k2v = v + h / 2 * k1v, acc(u + h / 2 * k1u)
        k3u, k3v = v + h / 2 * k2v, acc(u + h / 2 * k2u)
        k4u, k4v = v + h * k3v, acc(u + h * k3u)
        u += h / 6 * (k1u + 2 * k2u + 2 * k3u + k4u)
        v += h / 6 * (k1v + 2 * k2v + 2 * k3v + k4v)
        phi += h
        if u >= 0.5:
            return None
        if u < 1 / R_FAR and v < 0:
            beta = math.pi - (phi + math.atan(u / -v))
            return math.atan2(math.sin(beta), math.cos(beta))
    return None


def float_image():
    betas = {rho: trace_float(rho) for rho in range(1, RHO_MAX + 1)}
    img = []
    for py in range(N):
        for px in range(N):
            x, y = 2 * px - (N - 1), 2 * py - (N - 1)
            beta = betas[isqrt_round(x * x + y * y)]
            if beta is None:
                img.append(COLOR["black"])
            elif abs(beta) >= math.pi / 2:
                img.append(COLOR["rear"])
            else:
                k = math.tan(beta) / (math.hypot(0, isqrt_round(x * x + y * y)) * SQUARE)
                cx, cy = math.floor(x * k), math.floor(y * k)
                img.append(COLOR["light"] if (cx + cy) % 2 == 0 else COLOR["dark"])
    return img


# ---------------------------------------------------------------- consistency + output
def check_asm_constants():
    """blackhole.s must use exactly these constants (it is the single program source)."""
    text = (HERE / "blackhole.s").read_text()
    equ = {m.group(1): int(m.group(2), 0)
           for m in re.finditer(r"^\s*\.equ\s+(\w+)\s*,\s*(-?\w+)", text, re.M)}
    bad = [k for k, v in CONST.items() if equ.get(k) != v]
    atan_s = [int(v, 0) for v in re.findall(r"li\s+t0,\s*(\w+)\s*#\s*atan", text)]
    if atan_s != ATAN:
        bad.append("ATAN table")
    for k in bad:
        print(f"MISMATCH: {k} — blackhole.s has {equ.get(k)}, model expects {CONST.get(k)}")
    return not bad


def write_png(pixels, path, scale=8):
    w = h = N * scale
    rows = b"".join(b"\x00" + bytes(pixels[(y // scale) * N + (x // scale)] for x in range(w))
                    for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def cmd_expected():
    ok = check_asm_constants()
    table = build_table()
    img = fixed_image(table)
    (HERE / "expected.hex").write_text("".join(f"{p:02X}\n" for p in img))
    out = HERE / "out"
    out.mkdir(exist_ok=True)
    write_png(img, out / "blackhole_model.png")

    # physics check: GR predicts the shadow edge from the critical impact parameter
    b_c = 3 * math.sqrt(3)
    alpha = math.asin(b_c * math.sqrt(1 - 2 / R_CAM) / R_CAM)
    rho_sh = FOCAL * math.tan(alpha)
    first_lit = next(r for r in range(1, RHO_MAX + 1) if table[r][1] != 0)
    print(f"shadow edge: GR predicts rho = {rho_sh:.2f} half-px -> first lit entry "
          f"{math.floor(rho_sh) + 1}; fixed-point table gives {first_lit}")
    edge_ok = abs(first_lit - (math.floor(rho_sh) + 1)) <= 1

    ref = float_image()
    diff = sum(a != b for a, b in zip(img, ref))
    print(f"fixed vs float64: {diff} / {N * N} pixels differ ({100 * diff / (N * N):.2f}%)")
    print(f"wrote expected.hex and out/blackhole_model.png")
    print("constants:", "ok" if ok else "MISMATCH", "| shadow edge:", "ok" if edge_ok else "FAIL")
    return 0 if ok and edge_ok else 1


def cmd_png(src, dst):
    vals = [int(t, 16) for t in Path(src).read_text().split()]
    if len(vals) != N * N:
        print(f"{src}: expected {N * N} bytes, got {len(vals)}")
        return 1
    write_png(vals, dst)
    print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["expected"]:
        sys.exit(cmd_expected())
    if sys.argv[1:2] == ["png"] and len(sys.argv) == 4:
        sys.exit(cmd_png(sys.argv[2], sys.argv[3]))
    if sys.argv[1:2] == ["constants"]:
        for k, v in CONST.items():
            print(f".equ {k}, {v}")
        for i, v in enumerate(ATAN):
            print(f"atan(2^-{i}) = {v}")
        sys.exit(0)
    print(__doc__)
    sys.exit(2)
