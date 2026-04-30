`timescale 1ns/1ps

module tb_top;

    // ---- TEST 1 SIGNALS ----
    logic clk1, rst1;
    top #(.HEX_FILE("programs/test1.hex")) cpu1 (
        .clk (clk1),
        .rst (rst1)
    );

    // ---- TEST 2 SIGNALS ----
    logic clk2, rst2;
    top #(.HEX_FILE("programs/test2.hex")) cpu2 (
        .clk (clk2),
        .rst (rst2)
    );

    initial begin
        $dumpfile("sim/top.vcd");
        $dumpvars(0, tb_top);
    end

    // independent clocks for each CPU instance
    initial clk1 = 0;
    always #5 clk1 = ~clk1;

    initial clk2 = 0;
    always #5 clk2 = ~clk2;

    // check task for cpu1
    task automatic check1(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string test_name
    );
        if (cpu1.RF.regs[reg_addr] !== expected)
            $display("FAIL [TEST1]: %s | x%0d expected=0x%08h got=0x%08h",
                     test_name, reg_addr, expected,
                     cpu1.RF.regs[reg_addr]);
        else
            $display("PASS [TEST1]: %s | x%0d = 0x%08h",
                     test_name, reg_addr, expected);
    endtask

    // check task for cpu2
    task automatic check2(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string test_name
    );
        if (cpu2.RF.regs[reg_addr] !== expected)
            $display("FAIL [TEST2]: %s | x%0d expected=0x%08h got=0x%08h",
                     test_name, reg_addr, expected,
                     cpu2.RF.regs[reg_addr]);
        else
            $display("PASS [TEST2]: %s | x%0d = 0x%08h",
                     test_name, reg_addr, expected);
    endtask

    initial begin
        $display("========== CPU INTEGRATION TESTBENCH ==========");

        // reset both CPUs
        rst1 = 1; rst2 = 1;
        @(posedge clk1); #1;
        rst1 = 0; rst2 = 0;
        repeat(5) @(posedge clk2); #1;
$display("TEST2 debug: x20=0x%08h mem[0]=0x%02h mem[1]=0x%02h mem[2]=0x%02h mem[3]=0x%02h pc=0x%08h",
         cpu2.RF.regs[20],
         cpu2.DMEM.mem[0],
         cpu2.DMEM.mem[1],
         cpu2.DMEM.mem[2],
         cpu2.DMEM.mem[3],
         cpu2.pc);
         $display("IMEM[0]=0x%08h IMEM[1]=0x%08h IMEM[2]=0x%08h",
         cpu2.IMEM.mem[0],
         cpu2.IMEM.mem[1],
         cpu2.IMEM.mem[2]);

        
        // run both simultaneously
        repeat(200) @(posedge clk1);
        #1;

        // ---- TEST 1 RESULTS ----
        $display("\n--- TEST 1: Arithmetic + Branch + Loop ---");
        check1(5'd1, 32'd5,   "addi x1=5");
        check1(5'd2, 32'd10,  "addi x2=10");
        check1(5'd3, 32'd15,  "add  x3=x1+x2");
        check1(5'd4, 32'd5,   "addi x4=5");
        check1(5'd5, 32'd150, "loop x5=15*10");
        check1(5'd6, 32'd0,   "loop x6=0 counter exhausted");

        // ---- TEST 2 RESULTS ----
        $display("\n--- TEST 2: Memory + Logic + LUI ---");
        check2(5'd1,  32'h000000FF, "LBU byte load");
        check2(5'd2,  32'h000007FF, "LHU halfword unsigned");
        check2(5'd3,  32'h000007FF, "LH halfword positive");
        check2(5'd4,  32'd1,        "SLT 5 < 10");
        check2(5'd5,  32'hABCDE000, "LUI upper immediate");
        check2(5'd6,  32'd0,        "XOR same = 0");
        check2(5'd7,  32'd255,      "OR 0xF0|0x0F");
        check2(5'd8,  32'd100,      "AND result");

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule