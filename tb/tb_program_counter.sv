`timescale 1ns/1ps

module tb_program_counter;

    logic        clk, rst, pc_we;
    logic [31:0] pc_next;
    logic [31:0] pc;

    program_counter dut (
        .clk     (clk),
        .rst     (rst),
        .pc_we   (pc_we),
        .pc_next (pc_next),
        .pc      (pc)
    );

    initial begin
        $dumpfile("sim/program_counter.vcd");
        $dumpvars(0, tb_program_counter);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("========== PROGRAM COUNTER TESTBENCH ==========");

        // initialize
        rst = 1; pc_we = 0; pc_next = 0;
        @(posedge clk); #1;

        // test 1: reset holds PC at 0
        if (pc !== 32'd0)
            $display("FAIL: reset | expected 0 got 0x%08h", pc);
        else
            $display("PASS: reset to 0");

        // release reset
        rst = 0;
        @(posedge clk); #1;

        // test 2: sequential increment by 4
        if (pc !== 32'd4)
            $display("FAIL: increment | expected 4 got 0x%08h", pc);
        else
            $display("PASS: increment to 4");

        @(posedge clk); #1;
        if (pc !== 32'd8)
            $display("FAIL: increment | expected 8 got 0x%08h", pc);
        else
            $display("PASS: increment to 8");

        @(posedge clk); #1;
        if (pc !== 32'd12)
            $display("FAIL: increment | expected 12 got 0x%08h", pc);
        else
            $display("PASS: increment to 12");

        // test 3: branch/jump to arbitrary address
        pc_we = 1;
        pc_next = 32'h00000040;
        @(posedge clk); #1;
        pc_we = 0;

        if (pc !== 32'h00000040)
            $display("FAIL: jump | expected 0x40 got 0x%08h", pc);
        else
            $display("PASS: jump to 0x40");

        // test 4: continues incrementing from jumped address
        @(posedge clk); #1;
        if (pc !== 32'h00000044)
            $display("FAIL: post-jump increment | expected 0x44 got 0x%08h", pc);
        else
            $display("PASS: post-jump increment to 0x44");

        // test 5: reset works from non-zero address
        rst = 1;
        @(posedge clk); #1;
        rst = 0;

        if (pc !== 32'd0)
            $display("FAIL: re-reset | expected 0 got 0x%08h", pc);
        else
            $display("PASS: re-reset to 0");

        $display("========== DONE ==========");
        $finish;
    end

endmodule