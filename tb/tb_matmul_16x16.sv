`timescale 1ns/1ps
// Pipeline integration test: 16x16 tiled INT8 matmul via systolic array accumulate mode.
//
// A = B = all-1s (16x16). Tiled as 16 output tiles of 4x4, each with 4 K-passes.
// The program exercises CTRL bit[1] (accumulate mode) — first K-pass clears c_acc,
// subsequent K-passes accumulate. One K-pass gives C[i][j]=4; four passes give 16.
//
// Expected: cpu.RF.regs[11] === 32'd16  (C_INT32[0][0] from last tile)
// Result 16 proves accumulate mode chained all four K-passes correctly.
// (A single K-pass without accumulate would give 4, not 16.)
//
// Testbench polls if_pc for the halt at 0xD4, then checks x11.

module tb_matmul_16x16;

    logic clk, rst;

    top_pipeline #(
        .HEX_FILE("programs/matmul_16x16_systolic.hex")
    ) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin()
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    integer pass_cnt, fail_cnt, timeout;

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

    initial begin
        $dumpfile("sim/tb_matmul_16x16.vcd");
        $dumpvars(0, tb_matmul_16x16);

        pass_cnt = 0; fail_cnt = 0;

        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;

        // 16 tiles × 4 K-passes × ~30 cycles/pass (AXI + 11-cycle compute + poll)
        // + loop overhead + icache fill. 15000 cycles is very generous.
        //
        // IMPORTANT: check BOTH if_pc==0xD4 AND x14==0.
        // The BNE at 0xCC mispredicts on each of the first 15 iterations, causing the
        // pipeline to speculatively fetch 0xD4 for one cycle before flushing.
        // x14==0 only after all 16 tiles complete, uniquely identifying the true halt.
        timeout = 15000;
        while (timeout > 0 &&
               !(cpu.if_pc === 32'h0000_00D4 && cpu.RF.regs[14] === 32'd0)) begin
            @(posedge clk); #1;
            timeout--;
        end

        if (timeout == 0 &&
            !(cpu.if_pc === 32'h0000_00D4 && cpu.RF.regs[14] === 32'd0)) begin
            $display("TIMEOUT: did not reach halt (if_pc=0x%08h, x14=%0d)",
                     cpu.if_pc, cpu.RF.regs[14]);
            fail_cnt++;
        end

        // Wait 50 cycles: lw x11 (at 0xD0) needs to fully retire through the
        // systolic AXI manager and WB stage before x11 is readable.
        repeat(50) @(posedge clk); #1;

        $display("\n========== 16x16 TILED SYSTOLIC MATMUL (ACCUMULATE MODE) ==========");
        $display("A = B = all-1s (16x16), 4 K-passes per output tile");
        $display("Expected: C_INT32[0][0] = 4 (one K-pass) x 4 (K-passes) = 16");

        check(5'd11, 32'd16,
              "accumulate mode: 4 K-passes x dot(all-1s,all-1s)=4 -> 16");

        $display("\n========== RESULTS: %0d passed, %0d failed ==========",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL PASS");
        $finish;
    end

endmodule
