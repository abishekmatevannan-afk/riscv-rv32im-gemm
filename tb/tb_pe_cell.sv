`timescale 1ns/1ps
// Standalone verification for pe_cell.sv.
// Confirms extraction from parallel_mac_sub's compute loop is correct
// before the module goes into OpenLane.
//
// Cross-validation anchor: PDOT([1,2,3,4],[5,6,7,8]) = 70, which
// matches the verified result from tb_pmacc_pipeline and tb_parallel_mac.
//
// Test 7 is a signed/unsigned discriminator: a=0xFF, b=0x02.
//   Unsigned (correct): 255*2 = 510
//   Signed (wrong):     -1 *2 = -2 (0xFFFFFFFE)
// Passing 510 proves the zero-extension in pe_cell.sv matches
// the {24'd0, a_byte} zero-extension in parallel_mac_sub.sv line 198.

module tb_pe_cell;

    logic        clk, rst, en;
    logic [7:0]  a, b;
    logic [31:0] acc;

    pe_cell dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    int pass_cnt, fail_cnt;

    task automatic check(input string name, input [31:0] exp);
        #1;
        if (acc !== exp) begin
            $display("FAIL: %s | acc=0x%08h expected=0x%08h", name, acc, exp);
            fail_cnt++;
        end else begin
            $display("PASS: %s | acc=%0d", name, acc);
            pass_cnt++;
        end
    endtask

    task automatic tick(input [7:0] ta, tb_v, input logic ten = 1);
        a = ta; b = tb_v; en = ten;
        @(posedge clk); #1;
    endtask

    initial begin
        $dumpfile("sim/pe_cell.vcd");
        $dumpvars(0, tb_pe_cell);

        pass_cnt = 0; fail_cnt = 0;
        rst = 1; en = 0; a = 0; b = 0;
        repeat(3) @(posedge clk); #1;
        rst = 0;

        $display("========== PE CELL TESTBENCH ==========");

        // --- Test 1: reset zeroes acc ---
        check("reset clears acc", 32'd0);

        // --- Test 2: en=0 holds value ---
        tick(8'd3, 8'd5);              // acc = 15
        a = 8'd99; b = 8'd99; en = 0;
        @(posedge clk); #1;
        check("en=0 holds", 32'd15);

        // --- Test 3: PDOT([1,2,3,4],[5,6,7,8]) == 70 ---
        // Matches c_acc[0][0] from tb_parallel_mac baseline test
        rst = 1; @(posedge clk); #1; rst = 0;
        tick(8'd1, 8'd5);              // acc = 5
        tick(8'd2, 8'd6);              // acc = 17
        tick(8'd3, 8'd7);              // acc = 38
        tick(8'd4, 8'd8);              // acc = 70
        check("PDOT([1,2,3,4],[5,6,7,8]) == 70", 32'd70);

        // --- Test 4: second pass accumulates (mirrors K-tile chaining) ---
        tick(8'd1, 8'd5);
        tick(8'd2, 8'd6);
        tick(8'd3, 8'd7);
        tick(8'd4, 8'd8);
        check("two PDOT passes == 140", 32'd140);

        // --- Test 5: mid-run reset clears ---
        tick(8'd10, 8'd10);            // acc = 240
        rst = 1; @(posedge clk); #1; rst = 0;
        check("reset mid-run clears", 32'd0);

        // --- Test 6: max INT8 × 4 stays within 32-bit acc ---
        // 255*255 = 65025; ×4 = 260100 — fits comfortably in 32 bits
        tick(8'd255, 8'd255);
        tick(8'd255, 8'd255);
        tick(8'd255, 8'd255);
        tick(8'd255, 8'd255);
        check("4x(255*255) = 260100, no overflow", 32'd260100);

        // --- Test 7: signed/unsigned discriminator ---
        // 0xFF = 255 unsigned, -1 signed. Unsigned: 255*2=510. Signed: -1*2=-2.
        // Checks that extraction preserved {24'd0,...} zero-extension, not sign-extension.
        rst = 1; @(posedge clk); #1; rst = 0;
        tick(8'hFF, 8'h02);
        check("unsigned: 0xFF*2 = 510 not -2", 32'd510);

        $display("\n========== RESULTS: %0d passed, %0d failed ==========",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL PASS");
        $finish;
    end

endmodule
