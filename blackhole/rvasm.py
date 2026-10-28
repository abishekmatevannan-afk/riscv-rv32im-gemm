#!/usr/bin/env python3
"""rvasm — a small two-pass RV32IM assembler for this core.

Usage:
    python3 rvasm.py blackhole.s -o blackhole.hex
    python3 rvasm.py --self-test

Output is one 32-bit word per line in hex, the format $readmemh expects.

Supported:
    RV32I + RV32M, CSRRW/CSRRS/CSRRC (+ immediate forms), MRET, ECALL, EBREAK
    labels ("name:"), comments ("#"), ".equ NAME, expr"
    pseudo-ops: li mv j jr call ret nop neg not
                beqz bnez bltz bgez blez bgtz bgt ble bgtu bleu
Expressions may use integers, hex, + - * / << >> & | and .equ names.
li takes 1 instruction when the value fits in 12 bits, else 2 (lui + addi);
its value must be known in pass 1 (a literal or an earlier .equ).
"""
import re
import sys

ABI = {"zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4, "t0": 5, "t1": 6, "t2": 7,
       "s0": 8, "fp": 8, "s1": 9, "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14,
       "a5": 15, "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
       "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27, "t3": 28,
       "t4": 29, "t5": 30, "t6": 31}
CSRS = {"mstatus": 0x300, "mie": 0x304, "mtvec": 0x305, "mepc": 0x341,
        "mcause": 0x342, "mip": 0x344}

R_OPS = {  # name: (funct7, funct3)
    "add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
    "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or": (0x00, 6), "and": (0x00, 7),
    "mul": (0x01, 0), "mulh": (0x01, 1), "mulhsu": (0x01, 2), "mulhu": (0x01, 3),
    "div": (0x01, 4), "divu": (0x01, 5), "rem": (0x01, 6), "remu": (0x01, 7)}
I_ALU = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFTS = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
CSR_OPS = {"csrrw": 1, "csrrs": 2, "csrrc": 3, "csrrwi": 5, "csrrsi": 6, "csrrci": 7}


class AsmError(Exception):
    pass


def reg(tok):
    tok = tok.strip()
    if tok in ABI:
        return ABI[tok]
    m = re.fullmatch(r"x(\d+)", tok)
    if m and int(m.group(1)) < 32:
        return int(m.group(1))
    raise AsmError(f"bad register '{tok}'")


def evaluate(expr, syms):
    expr = expr.strip()
    if not re.fullmatch(r"[\w\s+\-*/()<>&|~]+", expr):
        raise AsmError(f"bad expression '{expr}'")
    try:
        return int(eval(expr.replace("/", "//"), {"__builtins__": {}}, dict(syms)))
    except NameError as e:
        raise AsmError(f"undefined symbol in '{expr}' ({e})")


def fits12(v):
    return -2048 <= v <= 2047


def split_hi_lo(v):
    v &= 0xFFFFFFFF
    lo = v & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((v - lo) >> 12) & 0xFFFFF
    return hi, lo


# ---- encoders -------------------------------------------------------------
def enc_r(f7, f3, rd, rs1, rs2, op=0x33):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    if not fits12(imm):
        raise AsmError(f"immediate {imm} out of 12-bit range")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3):
    if not fits12(imm):
        raise AsmError(f"store offset {imm} out of range")
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23


def enc_b(off, rs2, rs1, f3):
    if off % 2 or not -4096 <= off <= 4094:
        raise AsmError(f"branch offset {off} out of range")
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63


def enc_u(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def enc_j(off, rd):
    if off % 2 or not -(1 << 20) <= off < (1 << 20):
        raise AsmError(f"jump offset {off} out of range")
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) \
        | (((o >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def mem_operand(tok, syms):
    m = re.fullmatch(r"(.*)\((\w+)\)", tok.strip())
    if not m:
        raise AsmError(f"expected offset(reg), got '{tok}'")
    off = evaluate(m.group(1), syms) if m.group(1).strip() else 0
    return off, reg(m.group(2))


# ---- two passes -----------------------------------------------------------
def parse_lines(text):
    """Yield (lineno, labels, mnemonic, operands) with comments stripped."""
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        labels = []
        while True:
            m = re.match(r"^([A-Za-z_][\w.]*):\s*", line)
            if not m:
                break
            labels.append(m.group(1))
            line = line[m.end():]
        if not line:
            yield n, labels, None, []
            continue
        parts = line.split(None, 1)
        ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        yield n, labels, parts[0].lower(), ops


def size_of(mnem, ops, syms):
    if mnem == ".equ":
        return 0
    if mnem == "li":
        return 1 if fits12(evaluate(ops[1], syms)) else 2
    return 1


def assemble(text):
    lines = list(parse_lines(text))
    syms, pc = {}, 0
    for n, labels, mnem, ops in lines:          # pass 1: addresses and .equ
        try:
            for lab in labels:
                if lab in syms:
                    raise AsmError(f"duplicate symbol '{lab}'")
                syms[lab] = pc
            if mnem == ".equ":
                syms[ops[0]] = evaluate(ops[1], syms)
            elif mnem:
                pc += 4 * size_of(mnem, ops, syms)
        except AsmError as e:
            raise AsmError(f"line {n}: {e}") from None

    words, pc = [], 0
    for n, labels, mnem, ops in lines:          # pass 2: encode
        if not mnem or mnem == ".equ":
            continue
        try:
            out = encode(mnem, ops, syms, pc)
        except (AsmError, IndexError) as e:
            raise AsmError(f"line {n}: {mnem} {', '.join(ops)}: {e}") from None
        words += out
        pc += 4 * len(out)
    return words, syms


def encode(m, ops, syms, pc):
    ev = lambda t: evaluate(t, syms)
    rel = lambda t: ev(t) - pc

    # pseudo-ops
    if m == "nop":
        return [enc_i(0, 0, 0, 0, 0x13)]
    if m == "li":
        rd, v = reg(ops[0]), ev(ops[1])
        if fits12(v):
            return [enc_i(v, 0, 0, rd, 0x13)]
        hi, lo = split_hi_lo(v)
        return [enc_u(hi, rd, 0x37), enc_i(lo, rd, 0, rd, 0x13)]
    if m == "mv":
        return [enc_i(0, reg(ops[1]), 0, reg(ops[0]), 0x13)]
    if m == "neg":
        return [enc_r(0x20, 0, reg(ops[0]), 0, reg(ops[1]))]
    if m == "not":
        return [enc_i(-1, reg(ops[1]), 4, reg(ops[0]), 0x13)]
    if m == "j":
        return [enc_j(rel(ops[0]), 0)]
    if m == "call":
        return [enc_j(rel(ops[0]), 1)]
    if m == "jr":
        return [enc_i(0, reg(ops[0]), 0, 0, 0x67)]
    if m == "ret":
        return [enc_i(0, 1, 0, 0, 0x67)]
    zero_br = {"beqz": ("beq", False), "bnez": ("bne", False), "bltz": ("blt", False),
               "bgez": ("bge", False), "blez": ("bge", True), "bgtz": ("blt", True)}
    if m in zero_br:
        base, swap = zero_br[m]
        rs1, rs2 = (0, reg(ops[0])) if swap else (reg(ops[0]), 0)
        return [enc_b(rel(ops[1]), rs2, rs1, BRANCHES[base])]
    swap_br = {"bgt": "blt", "ble": "bge", "bgtu": "bltu", "bleu": "bgeu"}
    if m in swap_br:
        return [enc_b(rel(ops[2]), reg(ops[0]), reg(ops[1]), BRANCHES[swap_br[m]])]

    # real instructions
    if m in R_OPS:
        f7, f3 = R_OPS[m]
        return [enc_r(f7, f3, reg(ops[0]), reg(ops[1]), reg(ops[2]))]
    if m in I_ALU:
        return [enc_i(ev(ops[2]), reg(ops[1]), I_ALU[m], reg(ops[0]), 0x13)]
    if m in SHIFTS:
        f7, f3 = SHIFTS[m]
        sh = ev(ops[2])
        if not 0 <= sh < 32:
            raise AsmError(f"shift amount {sh} out of range")
        return [(f7 << 25) | (sh << 20) | (reg(ops[1]) << 15) | (f3 << 12) | (reg(ops[0]) << 7) | 0x13]
    if m in LOADS:
        off, rs1 = mem_operand(ops[1], syms)
        return [enc_i(off, rs1, LOADS[m], reg(ops[0]), 0x03)]
    if m in STORES:
        off, rs1 = mem_operand(ops[1], syms)
        return [enc_s(off, reg(ops[0]), rs1, STORES[m])]
    if m in BRANCHES:
        return [enc_b(rel(ops[2]), reg(ops[1]), reg(ops[0]), BRANCHES[m])]
    if m == "lui":
        return [enc_u(ev(ops[1]), reg(ops[0]), 0x37)]
    if m == "auipc":
        return [enc_u(ev(ops[1]), reg(ops[0]), 0x17)]
    if m == "jal":
        if len(ops) == 1:
            return [enc_j(rel(ops[0]), 1)]
        return [enc_j(rel(ops[1]), reg(ops[0]))]
    if m == "jalr":
        if len(ops) == 1:
            return [enc_i(0, reg(ops[0]), 0, 1, 0x67)]
        off, rs1 = mem_operand(ops[1], syms)
        return [enc_i(off, rs1, 0, reg(ops[0]), 0x67)]
    if m in CSR_OPS:
        csr = CSRS[ops[1]] if ops[1] in CSRS else ev(ops[1])
        src = ev(ops[2]) if m.endswith("i") else reg(ops[2])
        return [(csr << 20) | (src << 15) | (CSR_OPS[m] << 12) | (reg(ops[0]) << 7) | 0x73]
    if m == "mret":
        return [0x30200073]
    if m == "ecall":
        return [0x00000073]
    if m == "ebreak":
        return [0x00100073]
    raise AsmError(f"unknown mnemonic '{m}'")


def self_test():
    """Check encodings against words already in this repo's hex files."""
    cases = {
        "lui x10, 0xFFFF0": 0xFFFF0537,          # programs/exception_test.hex
        "addi x11, x10, 4": 0x00450593,
        "addi x1, x0, 0x40": 0x04000093,
        "csrrw x0, mtvec, x1": 0x30509073,
        "addi x2, x0, 8": 0x00800113,
        "sw x5, 0x100(x0)": 0x10502023,          # programs/precise_trap.hex
        "lw x7, 0x100(x0)": 0x10002383,
        "csrrs x28, mcause, x0": 0x34202E73,
        "mret": 0x30200073,
        "add x27, x27, x15": 0x00FD8DB3,         # fix_summary.txt (matmul_simd.hex)
        "slli x27, x16, 2": 0x00281D93,
        "sb x19, 0(x27)": 0x013D8023,
        "blt x17, x26, -48": 0xFDA8C8E3,
        "blt x16, x26, -60": 0xFDA842E3,
    }
    bad = 0
    for src, exp in cases.items():
        got, _ = assemble(src)
        if got != [exp]:
            print(f"FAIL: {src:28s} got {got[0]:08X} expected {exp:08X}")
            bad += 1
    # label resolution: backward branch and forward jump
    words, _ = assemble("top:\n nop\n beq x0, x0, top\n jal x0, end\n nop\nend:\n nop")
    for got, exp in zip(words[1:3], [0xFE000EE3, 0x0080006F]):
        if got != exp:
            print(f"FAIL: label offset got {got:08X} expected {exp:08X}")
            bad += 1
    # li must rebuild the exact value, including the addi sign-borrow case
    for v in [0, 2047, -2048, 0x12345678, 0xDEADBEEF, 0x7FFFF800, 0x800, -1]:
        words, _ = assemble(f"li t0, {v}")
        val = 0
        for w in words:
            if (w & 0x7F) == 0x37:
                val = w & 0xFFFFF000
            else:
                imm = w >> 20
                imm = imm - 4096 if imm & 0x800 else imm
                val = (val + imm) & 0xFFFFFFFF
        if val != v & 0xFFFFFFFF:
            print(f"FAIL: li {v:#x} produced {val:#x}")
            bad += 1
    print("rvasm self-test:", "ok" if not bad else f"{bad} failures")
    return bad == 0


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if len(argv) != 4 or argv[2] != "-o":
        print(__doc__)
        return 2
    try:
        words, _ = assemble(open(argv[1]).read())
    except AsmError as e:
        print(f"{argv[1]}: {e}", file=sys.stderr)
        return 1
    with open(argv[3], "w") as f:
        f.write("\n".join(f"{w:08X}" for w in words) + "\n")
    print(f"{argv[1]} -> {argv[3]}: {len(words)} words ({4 * len(words)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
