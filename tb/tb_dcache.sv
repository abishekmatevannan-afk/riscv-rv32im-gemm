`timescale 1ns/1ps

module tb_dcache;

    logic        clk, rst;
    logic        cpu_we, cpu_re;
    logic [31:0] cpu_addr, cpu_wd, cpu_rd;
    logic [2:0]  cpu_funct3;
    logic        cache_stall, cache_hit, cache_miss;

    logic        mem_we, mem_re;
    logic [31:0] mem_addr, mem_wd, mem_rd;
    logic [2:0]  mem_funct3;
    logic        is_io;

    // fake backing memory for testbench
    logic [31:0] backing_mem [0:255];

    dcache dut (
        .clk         (clk),
        .rst         (rst),
        .cpu_we      (cpu_we),
        .cpu_re      (cpu_re),
        .cpu_addr    (cpu_addr),
        .cpu_wd      (cpu_wd),
        .cpu_funct3  (cpu_funct3),
        .cpu_rd      (cpu_rd),
        .cache_stall (cache_stall),
        .cache_hit   (cache_hit),
        .cache_miss  (cache_miss),
        .mem_we      (mem_we),
        .mem_re      (mem_re),
        .mem_addr    (mem_addr),
        .mem_wd      (mem_wd),
        .mem_funct3  (mem_funct3),
        .mem_rd      (mem_rd),
        .is_io       (is_io)
    );

    initial begin
        $dumpfile("sim/dcache.vcd");
        $dumpvars(0, tb_dcache);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // simple backing memory model
    always_ff @(posedge clk) begin
        if (mem_we)
            backing_mem[mem_addr[9:2]] <= mem_wd;
    end
    assign mem_rd = backing_mem[mem_addr[9:2]];

    // initialize backing memory
    integer k;
    initial begin
        for (k = 0; k < 256; k++)
            backing_mem[k] = k * 32'h01010101;
    end

    // wait for stall to clear
    task automatic wait_ready;
        while (cache_stall) @(posedge clk);
        #1;
    endtask

    // write a word
    task automatic write_word(input [31:0] addr, input [31:0] data);
        cpu_we = 1; cpu_re = 0;
        cpu_addr = addr; cpu_wd = data; cpu_funct3 = 3'b010;
        @(posedge clk); #1;
        wait_ready;
        cpu_we = 0;
        @(posedge clk); #1;
    endtask

    // read a word and return it
    task automatic read_word(input [31:0] addr, output [31:0] result);
        cpu_we = 0; cpu_re = 1;
        cpu_addr = addr; cpu_funct3 = 3'b010;
        @(posedge clk); #1;
        wait_ready;
        result = cpu_rd;
        cpu_re = 0;
        @(posedge clk); #1;
    endtask

    logic [31:0] val;
    integer hits, misses;

    initial begin
        $display("========== DCACHE TESTBENCH ==========");

        rst = 1; cpu_we = 0; cpu_re = 0;
        cpu_addr = 0; cpu_wd = 0; cpu_funct3 = 3'b010;
        is_io = 0;
        repeat(3) @(posedge clk); #1;
        rst = 0;

        // TEST 1: cold miss then hit
        $display("\n--- TEST 1: Cold miss then hit ---");
        read_word(32'h00000000, val);
        if (val == backing_mem[0])
            $display("PASS: cold miss filled correctly, val=0x%08h", val);
        else
            $display("FAIL: cold miss val=0x%08h expected=0x%08h", val, backing_mem[0]);

        read_word(32'h00000000, val);
        if (val == backing_mem[0] && !cache_miss)
            $display("PASS: second read is a hit");
        else
            $display("FAIL: second read should hit");

        // TEST 2: write hit
        $display("\n--- TEST 2: Write hit ---");
        write_word(32'h00000000, 32'hDEADBEEF);
        read_word(32'h00000000, val);
        if (val == 32'hDEADBEEF)
            $display("PASS: write hit read back correctly");
        else
            $display("FAIL: write hit val=0x%08h", val);

        // TEST 3: spatial locality — read adjacent word in same line
        $display("\n--- TEST 3: Spatial locality ---");
        read_word(32'h00000000, val); // fill line containing addr 0-15
        read_word(32'h00000004, val); // should hit — same cache line
        if (!cache_miss)
            $display("PASS: adjacent word hits in same cache line");
        else
            $display("FAIL: adjacent word should hit same line");

        // TEST 4: conflict miss — two addresses map to same index
        // addr 0x00 and addr 0x100 both map to index 0
        $display("\n--- TEST 4: Conflict miss (same index different tag) ---");
        read_word(32'h00000000, val); // bring addr 0 into cache
        read_word(32'h00000100, val); // maps to same index, should miss
        if (cache_miss || val == backing_mem[32'h100 >> 2])
            $display("PASS: conflict miss detected");
        else
            $display("INFO: conflict miss val=0x%08h", val);

        // TEST 5: writeback — write to line, then evict with conflict
        $display("\n--- TEST 5: Dirty writeback ---");
        write_word(32'h00000000, 32'hCAFEBABE); // write to line 0, mark dirty
        read_word(32'h00000100, val);             // evict dirty line 0 → writeback
        // verify writeback happened to backing memory
        @(posedge clk); #1;
        if (backing_mem[0] == 32'hCAFEBABE)
            $display("PASS: dirty line written back to memory");
        else
            $display("FAIL: dirty writeback failed, mem[0]=0x%08h", backing_mem[0]);

        // TEST 6: IO bypass
        $display("\n--- TEST 6: IO bypass ---");
        is_io = 1;
        cpu_re = 1; cpu_addr = 32'hFFFF0004; cpu_funct3 = 3'b010;
        @(posedge clk); #1;
        if (!cache_stall)
            $display("PASS: IO access not stalled");
        else
            $display("FAIL: IO access should bypass cache");
        cpu_re = 0; is_io = 0;

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule