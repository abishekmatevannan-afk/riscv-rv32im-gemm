`timescale 1ns/1ps

// RV32M MUL/DIV unit testbench
// Covers all 8 operations plus RISC-V spec corner cases

module tb_mul_div;

    logic        clk, rst;
    logic [31:0] a, b;
    logic [2:0]  funct3;
    logic        start;
    logic [31:0] result;
    logic        busy;
    logic        freeze;

    mul_div_unit dut (.*);

    always #5 clk = ~clk;

    int pass_count, fail_count;

    task automatic check_mul(
        input [31:0] in_a, in_b,
        input [2:0]  f3,
        input [31:0] expected,
        input string name
    );
        a = in_a; b = in_b; funct3 = f3; start = 1;
        @(posedge clk); #1;
        start = 0;
        while (busy) @(posedge clk);
        #1;
        // Operands were captured on the edge above; mul_wait=1 and the
        // registered product is valid now (busy already 0).
        if (result !== expected) begin
            $display("FAIL: %s  got=%08h exp=%08h", name, result, expected);
            fail_count++;
        end else begin
            $display("PASS: %s", name);
            pass_count++;
        end
        @(posedge clk); #1; // let mul_wait clear, or the next MUL skips its capture
    endtask

    task automatic check_div(
        input [31:0] in_a, in_b,
        input [2:0]  f3,
        input [31:0] expected,
        input string name
    );
        a = in_a; b = in_b; funct3 = f3; start = 1;
        @(posedge clk); #1;
        start = 0;
        // Wait for divider to finish
        while (busy) @(posedge clk);
        #1;
        if (result !== expected) begin
            $display("FAIL: %s  got=%08h exp=%08h", name, result, expected);
            fail_count++;
        end else begin
            $display("PASS: %s", name);
            pass_count++;
        end
        @(posedge clk); #1; // let DONE→IDLE transition
    endtask

    task automatic expect32(input string name, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL: %s  got=%08h exp=%08h", name, got, exp);
            fail_count++;
        end else begin
            $display("PASS: %s", name);
            pass_count++;
        end
    endtask

    initial begin
        clk = 0; rst = 1; start = 0; freeze = 0;
        a = 0; b = 0; funct3 = 0;
        pass_count = 0; fail_count = 0;
        repeat(3) @(posedge clk);
        rst = 0; @(posedge clk); #1;

        $display("=== MUL/MULH/MULHSU/MULHU ===");
        // MUL: lower 32 bits
        check_mul(32'd6,          32'd7,          3'b000, 32'd42,         "MUL 6*7");
        check_mul(32'hFFFFFFFF,   32'd2,          3'b000, 32'hFFFFFFFE,   "MUL -1*2 lower");
        check_mul(32'h80000000,   32'd2,          3'b000, 32'd0,          "MUL INT_MIN*2 lower");

        // MULH: upper 32 bits, signed*signed
        check_mul(32'hFFFFFFFF,   32'hFFFFFFFF,   3'b001, 32'd0,          "MULH -1*-1 upper");
        check_mul(32'h7FFFFFFF,   32'h7FFFFFFF,   3'b001, 32'h3FFFFFFF,   "MULH MAX*MAX upper");
        check_mul(32'hFFFFFFFF,   32'd2,          3'b001, 32'hFFFFFFFF,   "MULH -1*2 upper");

        // MULHSU: upper 32 bits, signed*unsigned
        // -1 * (2^32-1) = -(2^32-1) = 0xFFFFFFFF_00000001, so the upper word is 0xFFFFFFFF.
        // (This used to expect 0xFFFFFFFE, the unsigned*unsigned answer, which hid
        // the MULHSU signedness bug; riscv-tests rv32um-mulhsu case 33 checks it.)
        check_mul(32'hFFFFFFFF,   32'hFFFFFFFF,   3'b010, 32'hFFFFFFFF,   "MULHSU -1*UINT_MAX upper");
        check_mul(32'h80000000,   32'hFFFF8000,   3'b010, 32'h80004000,   "MULHSU INT_MIN*0xFFFF8000 upper");

        // MULHU: upper 32 bits, unsigned*unsigned
        check_mul(32'hFFFFFFFF,   32'hFFFFFFFF,   3'b011, 32'hFFFFFFFE,   "MULHU UINT_MAX^2 upper");

        $display("=== DIV / DIVU ===");
        check_div(32'd20,         32'd6,          3'b100, 32'd3,          "DIV 20/6");
        check_div(32'hFFFFFFEC,   32'd6,          3'b100, 32'hFFFFFFFD,   "DIV -20/6");   // truncates toward 0: -3
        check_div(32'd20,         32'hFFFFFFFA,   3'b100, 32'hFFFFFFFD,   "DIV 20/-6");   // truncates toward 0: -3
        check_div(32'hFFFFFFEC,   32'hFFFFFFFA,   3'b100, 32'd3,          "DIV -20/-6");

        check_div(32'd20,         32'd6,          3'b101, 32'd3,          "DIVU 20/6");
        check_div(32'hFFFFFFFF,   32'd2,          3'b101, 32'h7FFFFFFF,   "DIVU UINT_MAX/2");

        $display("=== REM / REMU ===");
        check_div(32'd20,         32'd6,          3'b110, 32'd2,          "REM 20%6");
        check_div(32'hFFFFFFEC,   32'd6,          3'b110, 32'hFFFFFFFE,   "REM -20%6");
        check_div(32'd20,         32'hFFFFFFFA,   3'b110, 32'd2,          "REM 20%-6");

        check_div(32'd20,         32'd6,          3'b111, 32'd2,          "REMU 20%6");

        $display("=== Corner cases (spec §M.2) ===");
        // Divide by zero
        check_div(32'd5,          32'd0,          3'b100, 32'hFFFFFFFF,   "DIV x/0 quotient");
        check_div(32'd5,          32'd0,          3'b110, 32'd5,          "REM x/0 remainder");
        check_div(32'd5,          32'd0,          3'b101, 32'hFFFFFFFF,   "DIVU x/0 quotient");
        check_div(32'd5,          32'd0,          3'b111, 32'd5,          "REMU x/0 remainder");
        // Signed overflow INT_MIN / -1
        check_div(32'h80000000,   32'hFFFFFFFF,   3'b100, 32'h80000000,   "DIV INT_MIN/-1 overflow q");
        check_div(32'h80000000,   32'hFFFFFFFF,   3'b110, 32'd0,          "REM INT_MIN/-1 overflow r");

        // ── freeze: a D$ miss freezes EX while a MUL/DIV is in it ─────────
        // In the pipeline, start, a, b and funct3 stay constant for as long as
        // the instruction sits in EX, so each case below holds them steady.
        $display("=== MUL/DIV under freeze ===");

        // F1: MUL arrives while frozen. Nothing may be captured and busy must
        // stay high until freeze drops; then the normal 2-cycle MUL runs.
        a = 32'd1234; b = 32'd5678; funct3 = 3'b000; start = 1; freeze = 1;
        #1;
        expect32("F1 busy high on frozen arrival",     busy,         1'b1);
        repeat (3) @(posedge clk); #1;
        expect32("F1 mul_wait held at 0 while frozen", dut.mul_wait, 1'b0);
        expect32("F1 busy still high while frozen",    busy,         1'b1);
        freeze = 0;
        @(posedge clk); #1;                               // capture edge
        expect32("F1 busy drops after capture",        busy,         1'b0);
        expect32("F1 MUL 1234*5678",                   result,       32'd7006652);
        @(posedge clk); #1;                               // MUL leaves EX
        start = 0;
        expect32("F1 mul_wait cleared",                dut.mul_wait, 1'b0);

        // F2: freeze rises in the wait cycle (product already valid). The
        // product must stay valid and busy low for the whole freeze, and
        // mul_wait must not clear until EX actually advances.
        a = 32'h80000000; b = 32'h80000000; funct3 = 3'b001; start = 1;
        @(posedge clk); #1;                               // capture edge
        freeze = 1;
        repeat (3) @(posedge clk); #1;
        expect32("F2 mul_wait held at 1 while frozen", dut.mul_wait, 1'b1);
        expect32("F2 busy stays low while frozen",     busy,         1'b0);
        expect32("F2 MULH INT_MIN^2 held",             result,       32'h40000000);
        freeze = 0;
        @(posedge clk); #1;                               // MUL leaves EX

        // F3: back-to-back MUL right after the freeze ends. start stays high
        // with new operands; the second MUL must stall and capture its own
        // operands, not reuse F2's.
        a = 32'd9; b = 32'd9; funct3 = 3'b000;
        #1;
        expect32("F3 next MUL stalls on arrival",      busy,         1'b1);
        @(posedge clk); #1;
        expect32("F3 MUL 9*9",                         result,       32'd81);
        @(posedge clk); #1;
        start = 0;

        // F4: divider finishes (DONE) while EX is frozen. DONE must hold with
        // the result valid and busy low; dropping to IDLE would restart the
        // divide because start is still high.
        a = 32'd100; b = 32'd7; funct3 = 3'b100; start = 1;
        do begin @(posedge clk); #1; end while (busy);    // now in DONE
        freeze = 1;
        repeat (3) @(posedge clk); #1;
        expect32("F4 DIV holds DONE while frozen",     dut.state,    2'b10);
        expect32("F4 busy stays low (no restart)",     busy,         1'b0);
        expect32("F4 DIV 100/7 held",                  result,       32'd14);
        freeze = 0;
        @(posedge clk); #1;                               // DIV leaves EX
        start = 0;
        expect32("F4 back to IDLE",                    dut.state,    2'b00);

        $display("=================================================");
        $display("  %0d passed   %0d failed", pass_count, fail_count);
        $display("=================================================");
        $finish;
    end

endmodule
