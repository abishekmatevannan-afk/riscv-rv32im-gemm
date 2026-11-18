`timescale 1ns/1ps
// Testbench: RV32M MUL inside the full pipeline, around D-cache misses
//
// tb_mul_div tests the registered multiplier's freeze input on its own; this
// one runs programs/mul_pipeline.s on top_pipeline so real D$ misses freeze a
// MUL in EX (source in programs/mul_pipeline.s, built with blackhole/rvasm.py).
// It also counts how often that happened, so the test fails if the program
// stops producing the overlap it was written for.

module tb_mul_pipeline;

    logic clk, rst;

    top_pipeline #(.HEX_FILE("programs/mul_pipeline.hex")) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(),
        .uart_rx_pin(1'b1)
    );

    initial begin
        $dumpfile("sim/mul_pipeline.vcd");
        $dumpvars(0, tb_mul_pipeline);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;

    // Cycles where a MUL sat in EX while a D$ miss froze it, split by
    // whether it was frozen on arrival (mul_wait=0) or in its wait cycle.
    integer frozen_arrival = 0, frozen_wait = 0;
    always @(posedge clk) begin
        if (!rst && cpu.MULDIV.freeze && cpu.MULDIV.start && !cpu.MULDIV.funct3[2]) begin
            if (cpu.MULDIV.mul_wait) frozen_wait++;
            else                     frozen_arrival++;
        end
    end

    task automatic check(input string name, input [4:0] r, input [31:0] exp);
        if (cpu.RF.regs[r] === exp) begin
            $display("PASS: %-34s x%0d = 0x%08h", name, r, exp); pass++;
        end else begin
            $display("FAIL: %-34s x%0d = 0x%08h, expected 0x%08h", name, r,
                     cpu.RF.regs[r], exp); fail++;
        end
    endtask

    initial begin
        $display("========== MUL PIPELINE TESTBENCH ==========");
        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (1500) @(posedge clk);

        check("load after dirty-evict refill",   9, 32'd1000);
        check("mul during load miss",           18, 32'd42);
        check("mulh during load miss",          20, 32'hFFFFFFFF);
        check("back-to-back mul (first)",       22, 32'd42);
        check("back-to-back mul (dependent)",   23, 32'd294);
        check("load-use mul after miss",        25, 32'd7000);
        check("mulhu after store miss",         26, 32'hFFFFFFFA);
        check("mul results used afterwards",    27, 32'd7294);

        $display("MUL frozen in EX: %0d cycles on arrival, %0d in wait cycle",
                 frozen_arrival, frozen_wait);
        if (frozen_arrival > 0) begin
            $display("PASS: a D$ miss froze a MUL on arrival"); pass++;
        end else begin
            $display("FAIL: no MUL was frozen by a D$ miss; the test lost its coverage"); fail++;
        end

        $display("--- %0d passed  %0d failed ---", pass, fail);
        $display("========== DONE ==========");
        $finish;
    end

endmodule
