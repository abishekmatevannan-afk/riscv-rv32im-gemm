// Full CPU integration testbench
// Runs assembly programs and checks register state

`timescale 1ns/1ps

module tb_top;

    logic clk, rst;

    top dut (
        .clk (clk),
        .rst (rst)
    );

    initial begin
        $dumpfile("sim/top.vcd");
        $dumpvars(0, tb_top);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // task to check a register value
    task automatic check_reg(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string test_name
    );
        // directly peek at register file contents
        if (dut.RF.regs[reg_addr] !== expected)
            $display("FAIL: %s | x%0d expected=0x%08h got=0x%08h",
                     test_name, reg_addr, expected,
                     dut.RF.regs[reg_addr]);
        else
            $display("PASS: %s | x%0d = 0x%08h",
                     test_name, reg_addr, expected);
    endtask

    // run N clock cycles
    task automatic run_cycles(input integer n);
        repeat(n) @(posedge clk);
        #1;
    endtask

    initial begin
        $display("========== CPU INTEGRATION TESTBENCH ==========");

        // reset
        rst = 1;
        @(posedge clk); #1;
        rst = 0;

        // run enough cycles for the program to complete
        run_cycles(100);

        // check results — these match what test.hex computes
        // we'll update these after writing the test program
        $display("--- Register State After Execution ---");
        $display("x1  = 0x%08h", dut.RF.regs[1]);
        $display("x2  = 0x%08h", dut.RF.regs[2]);
        $display("x3  = 0x%08h", dut.RF.regs[3]);
        $display("x4  = 0x%08h", dut.RF.regs[4]);
        $display("x5  = 0x%08h", dut.RF.regs[5]);
        $display("x6  = 0x%08h", dut.RF.regs[6]);
        $display("x7  = 0x%08h", dut.RF.regs[7]);
        $display("x8  = 0x%08h", dut.RF.regs[8]);
        $display("x11 = 0x%08h", dut.RF.regs[11]);
        $display("x12 = 0x%08h", dut.RF.regs[12]);
        $display("x13 = 0x%08h", dut.RF.regs[13]);
        $display("x14 = 0x%08h", dut.RF.regs[14]);
        $display("x15 = 0x%08h", dut.RF.regs[15]);
        $display("x16 = 0x%08h", dut.RF.regs[16]);
        $display("x17 = 0x%08h", dut.RF.regs[17]);
        $display("x20 = 0x%08h", dut.RF.regs[20]);
        $display("x21 = 0x%08h", dut.RF.regs[21]);

        check_reg(5'd1, 32'd5,   "addi x1=5");
        check_reg(5'd2, 32'd10,  "addi x2=10");
        check_reg(5'd3, 32'd15,  "add  x3=x1+x2");
        check_reg(5'd4, 32'd5,   "addi x4=5");
        check_reg(5'd5, 32'd150, "loop x5=15*10");
        check_reg(5'd6, 32'd0,   "loop x6=0");
        check_reg(5'd1,  32'h000000FF, "LBU byte load");
        check_reg(5'd2,  32'h0000ABCD, "LHU halfword unsigned");
        check_reg(5'd3,  32'hFFFFABCD, "LH halfword signed");
        check_reg(5'd4,  32'd1,        "SLT 5 < 10");
        check_reg(5'd5,  32'hABCDE000, "LUI upper immediate");
        check_reg(5'd6,  32'd0,        "XOR same = 0");
        check_reg(5'd7,  32'd255,      "OR 0xF0|0x0F");
        check_reg(5'd8,  32'd100,      "AND result");

        $display("========== DONE ==========");
        $finish;
    end

endmodule

        