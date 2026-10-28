"""Convert a flat little-endian binary to a $readmemh word file.

usage: bin2hex.py <in.bin> <out.hex> <byte_base_address>

Writes one 32-bit word per line, preceded by an @<word_index> directive so the
words land at byte_base_address in the SRAM (word index = address / 4).
"""
import sys


def main() -> None:
    src, dst, base = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
    if base % 4:
        sys.exit(f"base address {base:#x} is not word aligned")
    data = open(src, "rb").read()
    data += b"\0" * (-len(data) % 4)
    with open(dst, "w") as f:
        f.write(f"@{base // 4:x}\n")
        for i in range(0, len(data), 4):
            f.write(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n")


if __name__ == "__main__":
    main()
