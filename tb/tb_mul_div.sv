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
        // Multiplier is combinational — result available immediately
        if (result !== expected) begin
            $display("FAIL: %s  got=%08h exp=%08h", name, result, expected);
            fail_count++;
        end else begin
            $display("PASS: %s", name);
            pass_count++;
        end
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

    initial begin
        clk = 0; rst = 1; start = 0;
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
        check_mul(32'hFFFFFFFF,   32'hFFFFFFFF,   3'b010, 32'hFFFFFFFE,   "MULHSU -1*UINT_MAX upper");

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

        $display("=================================================");
        $display("  %0d passed   %0d failed", pass_count, fail_count);
        $display("=================================================");
        $finish;
    end

endmodule
