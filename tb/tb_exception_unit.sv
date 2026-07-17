`timescale 1ns/1ps

module tb_exception_unit;

    logic [31:0] ex_pc;
    logic        ex_valid;
    logic        ex_illegal;
    logic        ex_ecall;
    logic        ex_mem_re, ex_mem_we;
    logic [2:0]  ex_funct3;
    logic [31:0] ex_alu_result;
    logic        ext_irq, mie_global, meie;
    logic        trap;
    logic [31:0] trap_cause, trap_epc;

    exception_unit dut (
        .ex_pc        (ex_pc),
        .ex_valid     (ex_valid),
        .ex_illegal   (ex_illegal),
        .ex_ecall     (ex_ecall),
        .ex_mem_re    (ex_mem_re),
        .ex_mem_we    (ex_mem_we),
        .ex_funct3    (ex_funct3),
        .ex_alu_result(ex_alu_result),
        .ext_irq      (ext_irq),
        .mie_global   (mie_global),
        .meie         (meie),
        .trap         (trap),
        .trap_cause   (trap_cause),
        .trap_epc     (trap_epc)
    );

    task automatic check(
        input string name,
        input logic exp_trap,
        input [31:0] exp_cause
    );
        #1;
        if (trap !== exp_trap || (exp_trap && trap_cause !== exp_cause)) begin
            $display("FAIL: %s | trap=%b cause=0x%08h | exp trap=%b cause=0x%08h",
                     name, trap, trap_cause, exp_trap, exp_cause);
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $display("========== EXCEPTION UNIT TESTBENCH ==========");

        // defaults — no trap conditions
        ex_pc = 32'h100; ex_valid = 1;
        ex_illegal = 0; ex_ecall = 0;
        ex_mem_re = 0; ex_mem_we = 0;
        ex_funct3 = 3'b010; ex_alu_result = 32'd0;
        ext_irq = 0; mie_global = 0; meie = 0;

        // TEST 1: no trap baseline
        check("no trap baseline", 0, 32'd0);

        // TEST 2: illegal instruction
        ex_illegal = 1;
        check("illegal instruction", 1, 32'd2);
        ex_illegal = 0;

        // TEST 3: ECALL
        ex_ecall = 1;
        check("ECALL", 1, 32'd11);
        ex_ecall = 0;

        // TEST 4: load word misaligned (addr=3, LW needs 4-byte align)
        ex_mem_re = 1; ex_funct3 = 3'b010; ex_alu_result = 32'd3;
        check("LW misaligned", 1, 32'd4);
        ex_mem_re = 0;

        // TEST 5: load word aligned (addr=4) — no trap
        ex_mem_re = 1; ex_funct3 = 3'b010; ex_alu_result = 32'd4;
        check("LW aligned no trap", 0, 32'd0);
        ex_mem_re = 0;

        // TEST 6: load halfword misaligned (addr=3, LH needs 2-byte align)
        ex_mem_re = 1; ex_funct3 = 3'b001; ex_alu_result = 32'd3;
        check("LH misaligned", 1, 32'd4);
        ex_mem_re = 0;

        // TEST 7: load halfword aligned (addr=2) — no trap
        ex_mem_re = 1; ex_funct3 = 3'b001; ex_alu_result = 32'd2;
        check("LH aligned no trap", 0, 32'd0);
        ex_mem_re = 0;

        // TEST 8: store word misaligned
        ex_mem_we = 1; ex_funct3 = 3'b010; ex_alu_result = 32'd1;
        check("SW misaligned", 1, 32'd6);
        ex_mem_we = 0;

        // TEST 9: store halfword misaligned
        ex_mem_we = 1; ex_funct3 = 3'b001; ex_alu_result = 32'd5;
        check("SH misaligned", 1, 32'd6);
        ex_mem_we = 0;

        // TEST 10: external interrupt — MIE and MEIE both must be set
        ext_irq = 1; mie_global = 0; meie = 1;
        check("ext_irq MIE=0 no trap", 0, 32'd0);

        ext_irq = 1; mie_global = 1; meie = 0;
        check("ext_irq MEIE=0 no trap", 0, 32'd0);

        ext_irq = 1; mie_global = 1; meie = 1;
        check("ext_irq MIE=MEIE=1 trap", 1, 32'h8000000B);
        ext_irq = 0; mie_global = 0; meie = 0;

        // TEST 11: interrupt priority over illegal instruction
        ex_illegal = 1; ext_irq = 1; mie_global = 1; meie = 1;
        check("interrupt beats illegal", 1, 32'h8000000B);
        ex_illegal = 0; ext_irq = 0; mie_global = 0; meie = 0;

        // TEST 12: ex_valid=0 — only interrupt fires, not illegal
        ex_valid = 0; ex_illegal = 1;
        check("bubble: illegal suppressed", 0, 32'd0);
        ext_irq = 1; mie_global = 1; meie = 1;
        check("bubble: interrupt still fires", 1, 32'h8000000B);
        ex_valid = 1; ex_illegal = 0; ext_irq = 0; mie_global = 0; meie = 0;

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule