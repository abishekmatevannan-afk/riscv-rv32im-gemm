`timescale 1ns/1ps
// Testbench: RV32M DIV/REM inside the full pipeline
//
// tb_mul_div tests the divider on its own; this one runs programs/div_pipeline.s
// on top_pipeline so the stall/forwarding around the 32-cycle divider is
// exercised too (source in programs/div_pipeline.s, built with blackhole/rvasm.py).

module tb_div_pipeline;

    logic clk, rst;

    top_pipeline #(.HEX_FILE("programs/div_pipeline.hex")) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(),
        .uart_rx_pin(1'b1)
    );

    initial begin
        $dumpfile("sim/div_pipeline.vcd");
        $dumpvars(0, tb_div_pipeline);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;

    task automatic check(input string name, input [4:0] r, input [31:0] exp);
        if (cpu.RF.regs[r] === exp) begin
            $display("PASS: %-28s x%0d = %0d", name, r, $signed(exp)); pass++;
        end else begin
            $display("FAIL: %-28s x%0d = %0d, expected %0d", name, r,
                     $signed(cpu.RF.regs[r]), $signed(exp)); fail++;
        end
    endtask

    initial begin
        $display("========== DIV/REM PIPELINE TESTBENCH ==========");
        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (1500) @(posedge clk);

        check("div 100 / 7",            12, 14);
        check("rem 100 % 7",            13, 2);
        check("div 100 / -3",           14, -33);
        check("rem 100 % -3",           15, 1);
        check("div -100 / -3",          16, 33);
        check("rem -100 % -3",          17, -1);
        check("divu 100 / 0xFFFFFFFD",  18, 0);
        check("remu 100 % 0xFFFFFFFD",  19, 100);
        check("div by zero",            20, 32'hFFFFFFFF);
        check("rem by zero",            21, 100);
        check("dependent div chain",    23, 11);
        check("div result used next",   24, 22);

        $display("--- %0d passed  %0d failed ---", pass, fail);
        $display("========== DONE ==========");
        $finish;
    end

endmodule
