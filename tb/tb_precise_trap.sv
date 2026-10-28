`timescale 1ns/1ps
// Testbench: precise traps
//
// A trap must stop the faulting instruction from committing, and mepc must
// point at a real instruction so MRET resumes exactly where the program was.
//
// programs/precise_trap.hex:
//   0x00  setup: mtvec=0x80, x30++ (start marker), MIE=1, MEIE=1, x1=0
//   0x20  16x addi x1,x1,1             <- external interrupt raised on a bubble here
//   0x60  sw 0x11111111 -> [0x100]
//         sw 0xDEADBEEF -> [0x102]      <- misaligned store, traps with mcause=6
//         lw x7, [0x100]                <- must still read 0x11111111
//   0x7C  spin
//   0x80  handler: interrupt -> x31++, mret
//                  exception -> x29++, mepc += 4, mret
//
// Before the fix: an interrupt on a bubble saved mepc=0 (program restarted), and
// the misaligned store still wrote memory.

module tb_precise_trap;

    logic clk, rst;

    top_pipeline #(.HEX_FILE("programs/precise_trap.hex")) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(),
        .uart_rx_pin(1'b1)
    );

    initial begin
        $dumpfile("sim/precise_trap.vcd");
        $dumpvars(0, tb_precise_trap);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;
    logic   irq_raised = 0;

    task automatic check(input string name, input logic ok, input [31:0] got);
        if (ok) begin $display("PASS: %s (0x%08h)", name, got); pass++; end
        else    begin $display("FAIL: %s (got 0x%08h)", name, got); fail++; end
    endtask

    // Raise the interrupt on the first bubble in EX after interrupts are enabled,
    // then drop it once the trap has been taken (handler entry clears MIE).
    initial begin : irq
        integer t;
        @(negedge rst);
        for (t = 0; t < 2000 && !irq_raised; t++) begin
            @(negedge clk);
            if (cpu.CSRS.mstatus[3] && cpu.CSRS.mie_reg[11] && !cpu.ex_valid) begin
                force cpu.ext_irq = 1'b1;
                irq_raised = 1;
            end
        end
        for (t = 0; t < 300 && cpu.CSRS.mstatus[3]; t++) @(negedge clk);
        release cpu.ext_irq;
    end

    initial begin
        $display("========== PRECISE TRAP TESTBENCH ==========");
        rst = 1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 0;
        repeat (2000) @(posedge clk);

        check("interrupt raised on a bubble",           irq_raised,                       irq_raised);
        check("program did not restart (x30 == 1)",     cpu.RF.regs[30] == 32'd1,         cpu.RF.regs[30]);
        check("interrupt handler ran once (x31 == 1)",  cpu.RF.regs[31] == 32'd1,         cpu.RF.regs[31]);
        check("each addi ran exactly once (x1 == 16)",  cpu.RF.regs[1]  == 32'd16,        cpu.RF.regs[1]);
        check("misaligned store trapped (x29 == 1)",    cpu.RF.regs[29] == 32'd1,         cpu.RF.regs[29]);
        check("mcause = 6 (store misaligned)",          cpu.CSRS.mcause == 32'd6,         cpu.CSRS.mcause);
        check("memory unchanged (x7 == 0x11111111)",    cpu.RF.regs[7]  == 32'h11111111,  cpu.RF.regs[7]);

        $display("--- %0d passed  %0d failed ---", pass, fail);
        $display("========== DONE ==========");
        $finish;
    end

endmodule
