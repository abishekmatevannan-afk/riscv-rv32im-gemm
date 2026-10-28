// Minimal machine-mode test environment for running riscv-tests on this core.
//
// Replaces riscv-tests' env/p, which assumes a unified memory, a tohost/fromhost
// host interface, and U/S-mode setup. This core is Harvard (separate ISRAM and
// DSRAM, both at address 0) and M-mode only, so a test here just runs from
// reset and reports by storing to TOHOST:
//   1                pass
//   (TESTNUM<<1)|1   fail in test case TESTNUM
// tb/tb_riscv_tests.sv watches the MEM-stage store to TOHOST.

#ifndef _RV32I_CORE_RISCV_TEST_H
#define _RV32I_CORE_RISCV_TEST_H

#define TOHOST 0x3FFC

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U
#define RVTEST_RV32M RVTEST_RV32U
#define RVTEST_RV64M RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  2;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        init;

#define RVTEST_CODE_END                                                 \
        unimp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li      t6, 1;                                                  \
        li      t5, TOHOST;                                             \
        sw      t6, 0(t5);                                              \
1:      j       1b;

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz    TESTNUM, 1b;                                            \
        sll     t6, TESTNUM, 1;                                         \
        or      t6, t6, 1;                                              \
        li      t5, TOHOST;                                             \
        sw      t6, 0(t5);                                              \
2:      j       2b;

#define RVTEST_DATA_BEGIN                                               \
        .pushsection .data;                                             \
        .align 4;

#define RVTEST_DATA_END                                                 \
        .popsection;

#endif
