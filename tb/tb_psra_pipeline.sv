`timescale 1ns/1ps
// Pipeline integration test for PSRA and PRELU instructions.
// Runs programs/psra_prelu_test.hex through the full top_pipeline and verifies
// that rs1 forwarding paths work correctly for both instructions:
//
//   x11 = 0xC0000000  test 1: PSRA, rs1 from register file (4 NOPs, no forwarding)
//   x12 = 0xFF3F00FF  test 2: PSRA, EX/MEM forward on rs1 (addi→PSRA back-to-back)
//   x13 = 0x00000001  test 3: PRELU, MEM/WB forward on rs1 (1 NOP between addi and PRELU)
//   x14 = 0x007F0000  test 4: PRELU, EX/MEM forward on rs1 (addi→PRELU back-to-back)
//
// Data:
//   0x80000001 bytes [lo→hi]: [0x01=+1, 0x00=0, 0x00=0, 0x80=-128]
//   0xFF7F00FF bytes [lo→hi]: [0xFF=-1, 0x00=0, 0x7F=+127, 0xFF=-1]
//
// PSRA(0x80000001, 1): [-128>>1=-64=C0, 0>>1=0, 0>>1=0, 1>>1=0]  = 0xC0000000
// PSRA(0xFF7F00FF, 1): [-1>>1=-1=FF,    0>>1=0, 127>>1=63=3F, -1>>1=-1=FF] = 0xFF3F00FF
// PRELU(0x80000001):   [max(0,-128)=0,  max(0,0)=0,  max(0,0)=0,  max(0,1)=1]  = 0x00000001
// PRELU(0xFF7F00FF):   [max(0,-1)=0,    max(0,0)=0,  max(0,127)=127=7F, max(0,-1)=0] = 0x007F0000
//
// Results are read from the register file directly (cpu.RF.regs[]) to avoid
// dcache write-back timing issues.

module tb_psra_pipeline;

    logic clk, rst;

    top_pipeline #(
        .HEX_FILE("programs/psra_prelu_test.hex")
    ) cpu (
        .clk        (clk),
        .rst        (rst),
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
            $display("FAIL: %s | x%0d expected=0x%08h got=0x%08h",
                     name, reg_addr, expected, cpu.RF.regs[reg_addr]);
            fail_cnt++;
        end else begin
            $display("PASS: %s | x%0d = 0x%08h", name, reg_addr, expected);
            pass_cnt++;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    integer timeout;

    initial begin
        $dumpfile("sim/tb_psra_pipeline.vcd");
        $dumpvars(0, tb_psra_pipeline);

        pass_cnt = 0; fail_cnt = 0;

        // Reset for 5 cycles
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;

        // Run until halt (jal x0,0 at PC=0x54) or timeout.
        // 22 instructions + icache fill + pipeline drain — 500 cycles is generous.
        timeout = 500;
        while (timeout > 0 && cpu.if_pc !== 32'h0000_0054) begin
            @(posedge clk); #1;
            timeout--;
        end

        if (timeout == 0 && cpu.if_pc !== 32'h0000_0054) begin
            $display("TIMEOUT: program did not reach halt at 0x54 (if_pc=0x%08h)",
                     cpu.if_pc);
            fail_cnt++;
        end

        // Let halt retire
        repeat(10) @(posedge clk); #1;

        $display("\n========== PSRA / PRELU PIPELINE INTEGRATION TEST ==========");

        $display("\n--- Test 1: PSRA rs1 from register file (4 NOPs, no forwarding) ---");
        check(5'd11, 32'hC0000000, "RF path: PSRA(0x80000001, shamt=1) = 0xC0000000");

        $display("\n--- Test 2: PSRA EX/MEM forwarding on rs1 (addi→PSRA back-to-back) ---");
        check(5'd12, 32'hFF3F00FF, "EX/MEM: PSRA(0xFF7F00FF, shamt=1) = 0xFF3F00FF");

        $display("\n--- Test 3: PRELU MEM/WB forwarding on rs1 (1 NOP) ---");
        check(5'd13, 32'h00000001, "MEM/WB: PRELU(0x80000001) = 0x00000001");

        $display("\n--- Test 4: PRELU EX/MEM forwarding on rs1 (addi→PRELU back-to-back) ---");
        check(5'd14, 32'h007F0000, "EX/MEM: PRELU(0xFF7F00FF) = 0x007F0000");

        $display("\n========== RESULTS: %0d passed, %0d failed ==========",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL PASS");
        $finish;
    end

endmodule
