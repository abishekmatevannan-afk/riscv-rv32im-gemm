`timescale 1ns/1ps

module tb_perf_counters;

    logic        clk, rst, re;
    logic [31:0] addr, rd;
    logic        instr_retired, branch_exec, mispredict;
    logic        cache_hit, cache_miss, icache_hit, icache_miss;

    perf_counters dut (
        .clk           (clk),
        .rst           (rst),
        .re            (re),
        .addr          (addr),
        .rd            (rd),
        .instr_retired (instr_retired),
        .branch_exec   (branch_exec),
        .mispredict    (mispredict),
        .cache_hit     (cache_hit),
        .cache_miss    (cache_miss),
        .icache_hit    (icache_hit),
        .icache_miss   (icache_miss)
    );

    initial begin
        $dumpfile("sim/perf_counters.vcd");
        $dumpvars(0, tb_perf_counters);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic check(input [31:0] a, input [31:0] expected,
                         input string name, input string op);
        logic [31:0] val;
        re = 1; addr = a; #10;
        val = rd; re = 0;
        if (op == "==" && val == expected)
            $display("PASS: %-20s = %0d", name, val);
        else if (op == ">=" && val >= expected)
            $display("PASS: %-20s = %0d (>= %0d)", name, val, expected);
        else
            $display("FAIL: %-20s = %0d (expected %s %0d)", name, val, op, expected);
    endtask

    logic [31:0] cycles;

    initial begin
        $display("========== PERF COUNTERS TESTBENCH ==========");

        rst = 1; re = 0;
        instr_retired = 0; branch_exec = 0; mispredict = 0;
        cache_hit = 0; cache_miss = 0; icache_hit = 0; icache_miss = 0;
        repeat(3) @(posedge clk); #1;
        rst = 0;

        // --- cycle counter ---
        repeat(10) @(posedge clk); #1;
        check(32'hFFFF2000, 10, "cycles", ">=");

        // --- instruction counter ---
        repeat(5) begin
            instr_retired = 1; @(posedge clk); #1;
            instr_retired = 0; @(posedge clk); #1;
        end
        check(32'hFFFF2004, 5, "instructions", "==");

        // --- branch counter ---
        repeat(4) begin
            branch_exec = 1; @(posedge clk); #1;
            branch_exec = 0; @(posedge clk); #1;
        end
        check(32'hFFFF2008, 4, "branches", "==");

        // --- mispredict counter ---
        mispredict = 1; @(posedge clk); #1;
        mispredict = 0; @(posedge clk); #1;
        mispredict = 1; @(posedge clk); #1;
        mispredict = 0; @(posedge clk); #1;
        check(32'hFFFF200C, 2, "mispredicts", "==");

        // --- dcache hit counter ---
        repeat(6) begin
            cache_hit = 1; @(posedge clk); #1;
            cache_hit = 0; @(posedge clk); #1;
        end
        check(32'hFFFF2010, 6, "dcache hits", "==");

        // --- dcache miss counter ---
        repeat(3) begin
            cache_miss = 1; @(posedge clk); #1;
            cache_miss = 0; @(posedge clk); #1;
        end
        check(32'hFFFF2014, 3, "dcache misses", "==");

        // --- icache hit counter ---
        repeat(8) begin
            icache_hit = 1; @(posedge clk); #1;
            icache_hit = 0; @(posedge clk); #1;
        end
        check(32'hFFFF2018, 8, "icache hits", "==");

        // --- icache miss counter ---
        repeat(2) begin
            icache_miss = 1; @(posedge clk); #1;
            icache_miss = 0; @(posedge clk); #1;
        end
        check(32'hFFFF201C, 2, "icache misses", "==");

        // --- reset clears all counters ---
        rst = 1; @(posedge clk); #1; rst = 0;
        check(32'hFFFF2000, 1, "cycles after reset", "==");
        check(32'hFFFF2004, 0, "instrs after reset",  "==");
        check(32'hFFFF2010, 0, "dcache hits after reset", "==");
        check(32'hFFFF2018, 0, "icache hits after reset", "==");

        $display("========== DONE ==========");
        $finish;
    end

endmodule