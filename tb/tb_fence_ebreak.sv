`timescale 1ns/1ps

// Integration test for FENCE (NOP) and EBREAK (breakpoint, mcause=3).
//
// Program layout (fence_ebreak.hex):
//   0x00: addi x5, x0, 0x30     # x5 = handler address
//   0x04: csrrw x0, mtvec, x5   # mtvec = 0x30
//   0x08: fence                  # NOP — must not trap
//   0x0C: addi x1, x0, 1        # x1 = 1 (fence succeeded without trapping)
//   0x10: ebreak                 # breakpoint trap: mcause=3, mepc=0x10
//   0x14: addi x2, x0, 2        # x2 = 2 (mret returned here)
//   0x18: jal x0, 0              # halt
//   0x1C-0x2C: nops (padding)
//   0x30: csrrs x10, mcause, x0 # x10 = mcause (read-only — tests csrr semantics)
//   0x34: csrrs x6,  mepc,   x0 # x6  = mepc  (= 0x10)
//   0x38: addi x6, x6, 4        # x6  = 0x14  (skip past ebreak on return)
//   0x3C: csrrw x0, mepc, x6    # mepc = 0x14
//   0x40: mret                   # return to 0x14

module tb_fence_ebreak;

    logic clk, rst;

    top_pipeline #(.HEX_FILE("programs/fence_ebreak.hex")) cpu (
        .clk (clk),
        .rst (rst)
    );

    initial begin
        $dumpfile("sim/fence_ebreak.vcd");
        $dumpvars(0, tb_fence_ebreak);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic check(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string name
    );
        if (cpu.RF.regs[reg_addr] !== expected)
            $display("FAIL: %s | x%0d expected=0x%08h got=0x%08h",
                     name, reg_addr, expected, cpu.RF.regs[reg_addr]);
        else
            $display("PASS: %s | x%0d = 0x%08h", name, reg_addr, expected);
    endtask

    initial begin
        $display("========== FENCE / EBREAK TEST ==========");
        rst = 1;
        repeat(5) @(posedge clk); #1;
        rst = 0;

        // allow enough cycles for: setup(2) + fence(1) + addi(1) + ebreak trap(5)
        // + handler(5) + mret(3) + addi(1) + halt + pipeline drain
        repeat(80) @(posedge clk); #1;

        $display("--- FENCE: execution continues after FENCE ---");
        check(5'd1, 32'd1, "x1=1 (fence did not trap)");

        $display("--- EBREAK: handler ran, mcause=3 ---");
        check(5'd10, 32'd3, "x10=mcause=3 (breakpoint)");

        $display("--- EBREAK: MRET returned to instruction after ebreak ---");
        check(5'd2, 32'd2, "x2=2 (mret returned correctly)");

        $display("========== DONE ==========");
        $finish;
    end

endmodule
