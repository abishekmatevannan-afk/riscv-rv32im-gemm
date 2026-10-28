/* Linker script for riscv-tests on this Harvard core.
 *
 * ISRAM and DSRAM are separate address spaces that both start at 0, but the
 * linker needs one address space, so code and data get disjoint ranges here:
 *   code  0x0000 - 0x1FFF  -> ISRAM words 0x000 - 0x7FF
 *   data  0x2000 - 0x3FFB  -> DSRAM words 0x800 - 0xFFE
 *   TOHOST 0x3FFC          (see env/riscv_test.h)
 * scripts/build_riscv_tests.sh splits the ELF into one hex file per memory.
 * tb_riscv_tests sizes DSRAM at 4096 words so 0x2000+ maps without aliasing.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x0000, LENGTH = 0x2000
    DMEM (rw)  : ORIGIN = 0x2000, LENGTH = 0x1FFC
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > IMEM

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        *(.bss .bss.*)
        *(.sbss .sbss.*)
    } > DMEM

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) }
}
