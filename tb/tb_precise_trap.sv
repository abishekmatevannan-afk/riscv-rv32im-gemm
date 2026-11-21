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
//
// Two more sections run after it, each on its own DUT held in reset until then:
//
// clint_timer on its own (TIMER_DUT): mtime/mtimecmp reads and writes, and the
//   exact one-cycle latency of the registered MTIP, including the 64-bit compare.
//
// programs/timer_irq.s on a second top_pipeline (cpu_timer):
//   - CSR immediate forms (CSRRWI/CSRRSI/CSRRCI) write the 5-bit constant,
//     not the register the rs1 field names;
//   - a trap that lands on a load-use stall still reaches its handler
//     (Known_limitations §26), both for a misaligned load and for timer
//     interrupts taken on a load with a dependent instruction behind it;
//   - every timer interrupt the CSR file commits is handled (a lost one would
//     leave MIE cleared and stop all further interrupts);
//   - the interrupted loop still computes exact results.
//   Coverage counters fail the test if the program stops producing the
//   trap + load-use overlap it was written for.

module tb_precise_trap;

    logic clk, rst;

    top_pipeline #(.HEX_FILE("programs/precise_trap.hex")) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(),
        .uart_rx_pin(1'b1)
    );

    // ── Timer DUTs ───────────────────────────────────────────────────────
    logic        rst_timer = 1'b1;     // cpu_timer
    logic        rst_clint = 1'b1;     // TIMER_DUT
    logic        clint_we;
    logic [31:0] clint_addr, clint_wd, clint_rd;
    logic        clint_irq;

    top_pipeline #(.HEX_FILE("programs/timer_irq.hex")) cpu_timer (
        .clk(clk), .rst(rst_timer), .uart_tx_pin(), .uart_rx_pin(1'b1)
    );

    clint_timer TIMER_DUT (
        .clk(clk), .rst(rst_clint), .we(clint_we), .addr(clint_addr),
        .wd(clint_wd), .rd(clint_rd), .timer_irq(clint_irq)
    );

    // Traps cpu_timer's CSR file commits (the same gating top_pipeline uses),
    // split by cause, and how many of them landed on a load-use stall.
    integer committed_timer = 0, committed_exc = 0;
    integer timer_on_load_use = 0, exc_on_load_use = 0;
    always @(posedge clk) begin
        if (!rst_timer && cpu_timer.trap && !cpu_timer.ex_mem_stall) begin
            if (cpu_timer.trap_cause == 32'h80000007) begin
                committed_timer++;
                if (cpu_timer.HU.load_use_hazard) timer_on_load_use++;
            end else begin
                committed_exc++;
                if (cpu_timer.HU.load_use_hazard) exc_on_load_use++;
            end
        end
    end

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

    task automatic check_eq(input string name, input [31:0] got, input [31:0] exp);
        if (got === exp) begin
            $display("PASS: %-44s 0x%08h", name, got); pass++;
        end else begin
            $display("FAIL: %-44s 0x%08h, expected 0x%08h", name, got, exp); fail++;
        end
    endtask

    task automatic check_true(input string name, input bit cond);
        if (cond) begin $display("PASS: %s", name); pass++; end
        else      begin $display("FAIL: %s", name); fail++; end
    endtask

    // One-cycle store into TIMER_DUT, like mem_mmio_we from the pipeline
    task automatic clint_store(input [31:0] a, input [31:0] d);
        @(negedge clk); clint_we = 1; clint_addr = a; clint_wd = d;
        @(negedge clk); clint_we = 0;
    endtask

    task automatic clint_load(input [31:0] a, output [31:0] d);
        @(negedge clk); clint_addr = a; #1; d = clint_rd;
    endtask

    logic [31:0] v, v2;
    integer timeout, handled;

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

        // ── clint_timer on its own ────────────────────────────────────────
        $display("--- machine timer (clint_timer) ---");
        clint_we = 0; clint_addr = 32'hFFFF4000; clint_wd = 0;
        repeat (3) @(posedge clk);
        @(negedge clk); rst_clint = 0;

        clint_load(32'hFFFF4008, v);  check_eq("mtimecmp lo resets to all ones", v, 32'hFFFFFFFF);
        clint_load(32'hFFFF400C, v);  check_eq("mtimecmp hi resets to all ones", v, 32'hFFFFFFFF);
        check_eq("no interrupt after reset", clint_irq, 0);

        clint_load(32'hFFFF4000, v);
        repeat (10) @(negedge clk);
        clint_load(32'hFFFF4000, v2);
        check_eq("mtime advances 11 in 11 cycles", v2 - v, 11);

        // A write to an mtime half replaces it; the low half keeps counting
        clint_store(32'hFFFF4004, 32'h0000_0001);
        clint_load(32'hFFFF4004, v);  check_eq("mtime hi written", v, 32'h0000_0001);
        clint_store(32'hFFFF4000, 32'h0000_1000);
        clint_load(32'hFFFF4000, v);  check_eq("mtime lo written, then +1", v, 32'h0000_1001);

        // Arm mtimecmp with the safe 3-store sequence (low word to all ones first)
        clint_store(32'hFFFF4000, 32'd0);              // mtime = {1, 0}
        clint_store(32'hFFFF4008, 32'hFFFF_FFFF);
        clint_store(32'hFFFF400C, 32'h0000_0001);
        clint_store(32'hFFFF4008, 32'd20);             // mtimecmp = {1, 20}
        check_eq("no interrupt before mtimecmp", clint_irq, 0);

        // In the cycle where mtime first equals mtimecmp the registered irq
        // still holds the previous compare; it rises at the next edge.
        wait (TIMER_DUT.mtime == 64'h0000_0001_0000_0014); #1;
        check_eq("mtime == mtimecmp, irq not yet registered", clint_irq, 0);
        @(posedge clk); #1;
        check_eq("irq one cycle after mtime == mtimecmp", clint_irq, 1);
        repeat (5) @(posedge clk); #1;
        check_eq("irq stays high while mtime >= mtimecmp", clint_irq, 1);

        clint_store(32'hFFFF4008, 32'h0000_1000);      // move mtimecmp ahead
        check_eq("irq still high the cycle after the store", clint_irq, 1);
        @(posedge clk); #1;
        check_eq("irq clears one cycle later", clint_irq, 0);

        clint_store(32'hFFFF4008, 32'd0);              // high word compares too
        clint_store(32'hFFFF400C, 32'h0000_0002);
        repeat (5) @(posedge clk); #1;
        check_eq("mtimecmp hi > mtime hi: no irq", clint_irq, 0);

        // ── timer interrupts in the pipeline (programs/timer_irq.s) ──────
        $display("--- timer interrupts (programs/timer_irq.s) ---");
        @(negedge clk); rst_timer = 0;
        timeout = 20000;
        while (timeout > 0 && cpu_timer.RF.regs[24] !== 32'd1) begin   // s8 = done
            @(posedge clk); timeout--;
        end
        // Sample at a clock edge; a timer trap may be between commit and the
        // handler's first instruction, so allow committed = handled + 1.
        @(posedge clk); #1;
        handled = cpu_timer.RF.regs[26];                                // s10

        check_true("program finished (s8 = 1)", cpu_timer.RF.regs[24] === 32'd1);

        // 0: CSR immediate forms (CSRRWI/CSRRSI/CSRRCI on mie)
        check_eq("csrrwi 21, csrrsi 10, csrrci 5 -> mie", cpu_timer.RF.regs[19], 26);   // s3

        // 1: directed §26 case
        check_eq("misaligned lw + dependent: handler ran", cpu_timer.RF.regs[23], 1);   // s7
        check_eq("misaligned lw cause",                    cpu_timer.RF.regs[22], 4);   // s6
        check_eq("exceptions committed",                   committed_exc, 1);
        check_eq("that exception sat on a load-use stall", exc_on_load_use, 1);

        // 2: timer interrupts
        $display("timer interrupts: %0d committed, %0d handled, %0d on a load-use stall",
                 committed_timer, handled, timer_on_load_use);
        check_true("at least 10 timer interrupts handled", handled >= 10);
        check_true("every committed timer interrupt was handled",
                   committed_timer == handled || committed_timer == handled + 1);
        check_eq("last interrupt cause (s9)", cpu_timer.RF.regs[25], 32'h80000007);
        check_true("MIE still enabled (no interrupt lost)", cpu_timer.CSRS.mstatus[3] === 1'b1);
        check_true("a timer interrupt landed on a load-use stall", timer_on_load_use > 0);

        // 3: the interrupted loop's results are exact
        check_eq("s0 = 150 x 6",  cpu_timer.RF.regs[8],  900);
        check_eq("s1 = 150 x 42", cpu_timer.RF.regs[9],  6300);
        check_eq("s2 = 150",      cpu_timer.RF.regs[18], 150);

        $display("--- %0d passed  %0d failed ---", pass, fail);
        $display("========== DONE ==========");
        $finish;
    end

endmodule
