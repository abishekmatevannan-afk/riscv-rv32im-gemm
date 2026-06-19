`timescale 1ns/1ps

module tb_icache;

    logic        clk, rst, flush;
    logic        cpu_re;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_rd;
    logic        icache_stall;
    logic        icache_hit;
    logic        icache_miss;
    logic        mem_re;
    logic [31:0] mem_addr;
    logic [31:0] mem_rd;

    // Prefetch port wires — testbench drives same-cycle address (conservative)
    logic [31:0] pc_next_tb;
    logic        pc_stall_tb;
    assign pc_next_tb  = cpu_addr;
    assign pc_stall_tb = icache_stall;

    icache DUT (
        .clk         (clk),
        .rst         (rst),
        .flush       (flush),
        .cpu_re      (cpu_re),
        .cpu_addr    (cpu_addr),
        .cpu_rd      (cpu_rd),
        .icache_stall(icache_stall),
        .icache_hit  (icache_hit),
        .icache_miss (icache_miss),
        .pc_next_i   (pc_next_tb),
        .pc_stall_i  (pc_stall_tb),
        .mem_re      (mem_re),
        .mem_addr    (mem_addr),
        .mem_rd      (mem_rd)
    );

    // =========================================================
    // Fake instruction memory — combinational, word addressed
    // mem[i] = 0xAA000000 | i so every word is distinguishable
    // =========================================================
    logic [31:0] fake_imem [0:255];
    integer fi;
    initial begin
        for (fi = 0; fi < 256; fi++)
            fake_imem[fi] = 32'hAA000000 | fi;
    end
    assign mem_rd = fake_imem[mem_addr[31:2]];

    // =========================================================
    // Clock
    // =========================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================
    // Helpers
    // =========================================================
    int pass_count, fail_count;

    task tick;
        @(posedge clk); #1;
    endtask

    task expect_stall(input string label);
        if (!icache_stall)
            $display("FAIL [%s]: expected icache_stall=1 got 0", label);
        // stall is expected -- silent pass, checked by draining loop
    endtask

    task check(
        input string   label,
        input logic [31:0] got,
        input logic [31:0] expected
    );
        if (got !== expected) begin
            $display("FAIL [%s]: expected=0x%08h got=0x%08h", label, expected, got);
            fail_count++;
        end else begin
            $display("PASS [%s]: 0x%08h", label, got);
            pass_count++;
        end
    endtask

    task check1(
        input string label,
        input logic got,
        input logic expected
    );
        if (got !== expected) begin
            $display("FAIL [%s]: expected=%0b got=%0b", label, expected, got);
            fail_count++;
        end else begin
            $display("PASS [%s]: %0b", label, got);
            pass_count++;
        end
    endtask

    // Drain icache stall for a given address.
    // Drives cpu_re=1 and cpu_addr=addr every cycle until stall drops.
    // Returns the instruction seen when stall deasserts.
    task automatic drain(
        input  logic [31:0] addr,
        output logic [31:0] instr_out
    );
        int timeout;
        timeout = 0;
        cpu_re   = 1;
        cpu_addr = addr;
        @(posedge clk); #1;
        while (icache_stall) begin
            timeout++;
            if (timeout > 50) begin
                $display("FAIL [drain timeout]: addr=0x%08h stall never cleared", addr);
                fail_count++;
                instr_out = 32'hXXXXXXXX;
                return;
            end
            @(posedge clk); #1;
        end
        instr_out = cpu_rd;
    endtask

    // =========================================================
    // Test body
    // =========================================================
    initial begin
        $dumpfile("sim/tb_icache.vcd");
        $dumpvars(0, tb_icache);

        pass_count = 0;
        fail_count = 0;

        cpu_re   = 0;
        cpu_addr = 32'd0;
        flush    = 0;

        rst = 1;
        repeat(2) @(posedge clk); #1;
        rst = 0;

        // =====================================================
        // TEST 1: Cold miss — fetch word 0 (addr 0x00000000)
        // Line 0 covers bytes 0x00-0x0F (words 0-3)
        // Expected instruction: fake_imem[0] = 0xAA000000
        // =====================================================
        $display("\n--- TEST 1: cold miss, addr=0x00000000 ---");
        cpu_re   = 1;
        cpu_addr = 32'h00000000;
        @(posedge clk); #1;

        // First cycle after presenting addr: IDLE sees miss, transitions to FILL.
        // icache_miss should be high this cycle.
        check1("T1 miss flagged", icache_miss, 1'b1);
        check1("T1 stall asserted", icache_stall, 1'b1);

        begin
            logic [31:0] result;
            drain(32'h00000000, result);
            check("T1 instr word 0", result, 32'hAA000000);
        end

        check1("T1 stall cleared", icache_stall, 1'b0);
        check1("T1 hit after fill", icache_hit, 1'b1);

        // =====================================================
        // TEST 2: Hit on same line — word 1 (addr 0x00000004)
        // Line 0 still valid. Should hit with zero stall cycles.
        // =====================================================
        $display("\n--- TEST 2: hit, same line, addr=0x00000004 ---");
        cpu_addr = 32'h00000004;
        @(posedge clk); #1;
        check1("T2 no stall",   icache_stall, 1'b0);
        check1("T2 hit",        icache_hit,   1'b1);
        check ("T2 instr word 1", cpu_rd, 32'hAA000001);

        // =====================================================
        // TEST 3: Hit on same line — word 3 (addr 0x0000000C)
        // Exercises word_off=3 path.
        // =====================================================
        $display("\n--- TEST 3: hit, word 3, addr=0x0000000C ---");
        cpu_addr = 32'h0000000C;
        @(posedge clk); #1;
        check1("T3 no stall",   icache_stall, 1'b0);
        check1("T3 hit",        icache_hit,   1'b1);
        check ("T3 instr word 3", cpu_rd, 32'hAA000003);

        // =====================================================
        // TEST 4: Miss on a different line — addr 0x00000010
        // Line 1 covers bytes 0x10-0x1F (words 4-7)
        // Expected: fake_imem[4] = 0xAA000004 for word_off=0
        // =====================================================
        $display("\n--- TEST 4: cold miss, new line, addr=0x00000010 ---");
        cpu_addr = 32'h00000010;
        @(posedge clk); #1;
        check1("T4 miss", icache_miss, 1'b1);
        check1("T4 stall", icache_stall, 1'b1);

        begin
            logic [31:0] result;
            drain(32'h00000010, result);
            check("T4 instr word 0 of line 1", result, 32'hAA000004);
        end

        // =====================================================
        // TEST 5: Previously filled line 0 still valid
        // Return to addr 0x00000008 — should hit, no fill
        // =====================================================
        $display("\n--- TEST 5: re-access line 0, addr=0x00000008 ---");
        cpu_addr = 32'h00000008;
        @(posedge clk); #1;
        check1("T5 hit",     icache_hit,   1'b1);
        check1("T5 no stall",icache_stall, 1'b0);
        check ("T5 instr",   cpu_rd,       32'hAA000002);

        // =====================================================
        // TEST 6: Flush mid-fill
        // Start a fetch for a cold line (line 2, addr 0x20).
        // Assert flush after one fill cycle to abort.
        // Then present a different address (line 3, addr 0x30).
        // Verify line 2 is NOT marked valid after the flush.
        // Verify line 3 fills and returns correct data.
        // =====================================================
        $display("\n--- TEST 6: flush mid-fill ---");
        cpu_re   = 1;
        cpu_addr = 32'h00000020;   // line 2 — cold
        @(posedge clk); #1;
        check1("T6 stall before flush", icache_stall, 1'b1);

        // let one fill cycle run then flush
        @(posedge clk); #1;
        flush    = 1;
        cpu_addr = 32'h00000030;   // redirect to line 3
        @(posedge clk); #1;
        flush    = 0;

        // line 2 must NOT be valid — partial fill was abandoned
        if (DUT.valid[2] !== 1'b0)
            $display("FAIL [T6 line 2 not valid]: valid[2]=%0b should be 0",
                     DUT.valid[2]);
        else begin
            $display("PASS [T6 line 2 invalid after flush]");
            pass_count++;
        end

        // now drain the miss for line 3
        begin
            logic [31:0] result;
            cpu_addr = 32'h00000030;
            // might already be in IDLE after flush reset, check stall first
            @(posedge clk); #1;
            if (icache_stall) begin
                drain(32'h00000030, result);
            end else begin
                result = cpu_rd;
            end
            // line 3 word 0 = fake_imem[0x30>>2] = fake_imem[12] = 0xAA00000C
            check("T6 line 3 word 0 after flush redirect", result, 32'hAA00000C);
        end

        // line 2 stays invalid -- confirm no ghost fill occurred
        if (DUT.valid[2] !== 1'b0)
            $display("FAIL [T6 line 2 still invalid after line 3 fill]: valid=%0b",
                     DUT.valid[2]);
        else begin
            $display("PASS [T6 line 2 still invalid]");
            pass_count++;
        end

        // =====================================================
        // TEST 7: cpu_re=0 — no fetch, no stall, no miss
        // Even for a cold line, icache should not react
        // =====================================================
        $display("\n--- TEST 7: cpu_re=0, cold address ---");
        cpu_re   = 0;
        cpu_addr = 32'h00000100;   // definitely cold
        @(posedge clk); #1;
        check1("T7 no stall when re=0",  icache_stall, 1'b0);
        check1("T7 no miss when re=0",   icache_miss,  1'b0);
        check1("T7 no hit when re=0",    icache_hit,   1'b0);
        cpu_re = 1;

        // =====================================================
        // TEST 8: All four words of a newly filled line
        // Fill line 4 (addr 0x40-0x4F) and read back words
        // 0, 1, 2, 3 in successive cycles — all must hit
        // =====================================================
        $display("\n--- TEST 8: verify all 4 words after fill ---");
        begin
            logic [31:0] result;
            // trigger fill
            cpu_addr = 32'h00000040;
            @(posedge clk); #1;
            if (icache_stall)
                drain(32'h00000040, result);
            else
                result = cpu_rd;
            check("T8 word 0", result, 32'hAA000010);

            cpu_addr = 32'h00000044;
            @(posedge clk); #1;
            check1("T8 w1 no stall", icache_stall, 1'b0);
            check ("T8 word 1", cpu_rd, 32'hAA000011);

            cpu_addr = 32'h00000048;
            @(posedge clk); #1;
            check ("T8 word 2", cpu_rd, 32'hAA000012);

            cpu_addr = 32'h0000004C;
            @(posedge clk); #1;
            check ("T8 word 3", cpu_rd, 32'hAA000013);
        end

        // =====================================================
        // Summary
        // =====================================================
        $display("\n========== tb_icache: %0d passed, %0d failed ==========",
                 pass_count, fail_count);
        $finish;
    end

endmodule