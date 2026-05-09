`timescale 1ns/1ps

module tb_perf_counters;

    logic        clk, rst, re;
    logic [31:0] addr, rd;
    logic        instr_retired, branch_exec, mispredict;

    perf_counters dut (
        .clk           (clk),
        .rst           (rst),
        .re            (re),
        .addr          (addr),
        .rd            (rd),
        .instr_retired (instr_retired),
        .branch_exec   (branch_exec),
        .mispredict    (mispredict)
    );

    initial begin
        $dumpfile("sim/perf_counters.vcd");
        $dumpvars(0, tb_perf_counters);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic read_counter(
        input  [31:0] a,
        output [31:0] val,
        input  string name
    );
        re = 1; addr = a; #10;
        val = rd;
        re = 0;
        $display("%s = %0d", name, val);
    endtask

    logic [31:0] cycles, instrs, branches, mispredicts;

    initial begin
        $display("========== PERF COUNTERS TESTBENCH ==========");

        rst = 1; re = 0;
        instr_retired = 0;
        branch_exec   = 0;
        mispredict    = 0;
        repeat(3) @(posedge clk); #1;
        rst = 0;

        // run 10 cycles
        repeat(10) @(posedge clk); #1;

        // read cycle counter
        read_counter(32'hFFFF2000, cycles, "cycles");
        if (cycles >= 10)
            $display("PASS: cycle counter running");
        else
            $display("FAIL: cycle counter = %0d expected >= 10", cycles);

        // retire 5 instructions
        repeat(5) begin
            instr_retired = 1;
            @(posedge clk); #1;
            instr_retired = 0;
            @(posedge clk); #1;
        end

        read_counter(32'hFFFF2004, instrs, "instructions retired");
        if (instrs == 5)
            $display("PASS: instruction counter = 5");
        else
            $display("FAIL: instruction counter = %0d expected 5", instrs);

        // execute 4 branches, 2 mispredicted
        repeat(4) begin
            branch_exec = 1;
            @(posedge clk); #1;
            branch_exec = 0;
            @(posedge clk); #1;
        end

        mispredict = 1; @(posedge clk); #1;
        mispredict = 0; @(posedge clk); #1;
        mispredict = 1; @(posedge clk); #1;
        mispredict = 0; @(posedge clk); #1;

        read_counter(32'hFFFF2008, branches,    "branches");
        read_counter(32'hFFFF200C, mispredicts, "mispredictions");

        if (branches == 4)
            $display("PASS: branch counter = 4");
        else
            $display("FAIL: branch counter = %0d expected 4", branches);

        if (mispredicts == 2)
            $display("PASS: mispredict counter = 2");
        else
            $display("FAIL: mispredict counter = %0d expected 2", mispredicts);

        // verify CPI calculation
        read_counter(32'hFFFF2000, cycles, "final cycles");
        read_counter(32'hFFFF2004, instrs, "final instructions");
        $display("CPI = %0d / %0d = ~%0d", cycles, instrs, cycles/instrs);

        // test reset clears counters
        rst = 1; @(posedge clk); #1; rst = 0;
        read_counter(32'hFFFF2000, cycles, "cycles after reset");
        if (cycles <= 1)
            $display("PASS: reset clears counters");
        else
            $display("FAIL: reset did not clear counters");

        $display("========== DONE ==========");
        $finish;
    end

endmodule