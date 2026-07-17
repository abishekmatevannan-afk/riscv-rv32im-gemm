`timescale 1ns/1ps
// Pipeline integration test for PMACC instruction.
// Runs programs/pmacc_test.hex through the full top_pipeline and verifies
// that all four forwarding paths for the accumulator port work correctly:
//
//   x11 = 70   test 1: acc from register file (4 NOPs, no forwarding)
//   x12 = 210  test 2: EX/MEM forwarding (3 back-to-back PMACCs)
//   x13 = 140  test 3: MEM/WB forwarding (1 NOP between PMACCs)
//   x14 = 140  test 4: load-use stall on acc port (LW immediately before PMACC)
//
// PDOT([1,2,3,4],[5,6,7,8]) = 70.  Each test accumulates on top of that.
// Results are checked by probing the register file directly (cpu.RF.regs[]),
// which avoids dcache write-back timing issues.

module tb_pmacc_pipeline;

    logic clk, rst;

    top_pipeline #(
        .HEX_FILE("programs/pmacc_test.hex")
    ) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_rx_pin(1'b1),
        .uart_tx_pin()
    );

    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ----------------------------------------------------------------
    // Counters
    // ----------------------------------------------------------------
    integer pass_cnt, fail_cnt;

    task automatic check(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string name
    );
        if (cpu.RF.regs[reg_addr] !== expected) begin
            $display("FAIL: %s | x%0d expected=%0d got=%0d",
                     name, reg_addr, expected, cpu.RF.regs[reg_addr]);
            fail_cnt++;
        end else begin
            $display("PASS: %s | x%0d = %0d", name, reg_addr, expected);
            pass_cnt++;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    integer timeout;

    initial begin
        $dumpfile("sim/pmacc_pipeline.vcd");
        $dumpvars(0, tb_pmacc_pipeline);

        pass_cnt = 0; fail_cnt = 0;

        // Reset for 5 cycles
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;

        // Run until the halt (jal x0,0 at PC=0x6C) or timeout.
        // Account for icache fills (~50 cycles), dcache miss on LW (~20 cycles),
        // and load-use stalls; 1500 cycles is a generous upper bound.
        timeout = 1500;
        while (timeout > 0 && cpu.if_pc !== 32'h0000_006C) begin
            @(posedge clk); #1;
            timeout--;
        end

        if (timeout == 0 && cpu.if_pc !== 32'h0000_006C) begin
            $display("TIMEOUT: program did not reach halt at 0x6C (if_pc=0x%08h)",
                     cpu.if_pc);
            fail_cnt++;
        end

        // Let the halt instruction fully retire
        repeat(10) @(posedge clk); #1;

        $display("\n========== PMACC PIPELINE INTEGRATION TEST ==========");

        $display("\n--- Test 1: acc from register file (no forwarding) ---");
        check(5'd11, 32'd70, "RF path: PMACC(acc=0) = PDOT = 70");

        $display("\n--- Test 2: EX/MEM forwarding (3 back-to-back PMACCs) ---");
        check(5'd12, 32'd210, "EX/MEM: PMACC chain 0→70→140→210");

        $display("\n--- Test 3: MEM/WB forwarding (1 NOP between PMACCs) ---");
        check(5'd13, 32'd140, "MEM/WB: PMACC NOP PMACC = 140");

        $display("\n--- Test 4: load-use stall on accumulator port ---");
        check(5'd14, 32'd140, "load-use: LW→PMACC stall, 70+70=140");

        $display("\n========== RESULTS: %0d passed, %0d failed ==========",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL PASS");
        $finish;
    end

endmodule
