#!/usr/bin/env bash
# Build the official riscv-tests (rv32ui + rv32um) for this core.
#
# Output: programs/riscv-tests/<suite>-<test>.imem.hex and .dmem.hex,
# loaded by tb/tb_riscv_tests.sv. The hex files are committed, so
# `make riscv-tests` runs without a RISC-V toolchain. Run this script
# (or `make riscv-tests-build`) only to regenerate them.
#
# Toolchain: xPack riscv-none-elf-gcc. Override with RISCV_PREFIX, e.g.
#   RISCV_PREFIX=riscv64-unknown-elf- scripts/build_riscv_tests.sh
set -euo pipefail

cd "$(dirname "$0")/.."

RISCV_TESTS_REPO=https://github.com/riscv-software-src/riscv-tests.git
RISCV_TESTS_COMMIT=7b68f7b91f827f8d94cc1c57ff123752c5c8f704   # pinned for reproducibility
SRC=third_party/riscv-tests
OUT=programs/riscv-tests

if [ -z "${RISCV_PREFIX:-}" ]; then
    RISCV_PREFIX=$(ls -d "$HOME"/tools/xpack-riscv-none-elf-gcc-*/bin 2>/dev/null | tail -1)/riscv-none-elf-
fi
CC=${RISCV_PREFIX}gcc
OBJCOPY=${RISCV_PREFIX}objcopy
command -v "$CC" >/dev/null || { echo "error: $CC not found (set RISCV_PREFIX)"; exit 1; }

if [ ! -d "$SRC/.git" ]; then
    git clone -q "$RISCV_TESTS_REPO" "$SRC"
fi
git -C "$SRC" checkout -q "$RISCV_TESTS_COMMIT"

# Excluded, see README "ISA compliance":
#   fence_i  self-modifying code needs a writable instruction memory (ISRAM is read-only)
#   ma_data  misaligned loads/stores are optional in the spec and not implemented
EXCLUDE="fence_i ma_data"

CFLAGS="-march=rv32im_zicsr_zifencei -mabi=ilp32 -static -nostdlib -nostartfiles \
        -T tests/riscv/link.ld -I tests/riscv/env -I $SRC/isa/macros/scalar"

rm -rf "$OUT"
mkdir -p "$OUT"
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

count=0
for suite in rv32ui rv32um; do
    for src in "$SRC"/isa/$suite/*.S; do
        name=$(basename "$src" .S)
        case " $EXCLUDE " in *" $name "*) continue ;; esac
        elf="$build_dir/$suite-$name.elf"
        $CC $CFLAGS -I "$SRC/isa/$suite" "$src" -o "$elf"
        $OBJCOPY -O binary -j .text "$elf" "$build_dir/$suite-$name.imem.bin"
        $OBJCOPY -O binary -j .data "$elf" "$build_dir/$suite-$name.dmem.bin"
        python3 scripts/bin2hex.py "$build_dir/$suite-$name.imem.bin" "$OUT/$suite-$name.imem.hex" 0
        python3 scripts/bin2hex.py "$build_dir/$suite-$name.dmem.bin" "$OUT/$suite-$name.dmem.hex" 0x2000
        count=$((count + 1))
    done
done
echo "Built $count tests into $OUT (riscv-tests @ ${RISCV_TESTS_COMMIT:0:12})"
