`timescale 1ns/1ps
// Integration test: runs perf_demo.hex in the full pipeline and captures
// all 8 PMU counter bytes transmitted over UART.
// Checks: cycles > 0, instructions > 0, branches == 10 (loop ran 10x),
//         mispredicts <= branches, all cache counters received.

module tb_perf_demo;

    localparam CLKS_PER_BIT = 10;

    logic clk, rst;
    logic uart_tx_pin;

    top_pipeline #(
        .HEX_FILE    ("programs/perf_demo.hex"),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(1'b1)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/tb_perf_demo.vcd");
        $dumpvars(0, tb_perf_demo);
    end

    task automatic capture_byte(output logic [7:0] data, output logic ok);
        integer timeout;
        timeout = 0; ok = 0; data = 0;
        while (uart_tx_pin == 1 && timeout < 2000000) begin
            @(posedge clk); timeout++;
        end
        if (timeout >= 2000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            repeat(CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx_pin;
        end
        repeat(CLKS_PER_BIT) @(posedge clk);
        ok = 1;
    endtask

    logic [7:0] cycles, instrs, branches, mispredicts;
    logic [7:0] dcache_hits, dcache_misses, icache_hits, icache_misses;
    logic ok;

    initial begin
        $display("========== PMU ALL-8-COUNTERS TESTBENCH ==========");

        rst = 1;
        repeat(5) @(posedge clk); #1;
        rst = 0;

        capture_byte(cycles,       ok); if (!ok) begin $display("TIMEOUT cycles");       $finish; end
        capture_byte(instrs,       ok); if (!ok) begin $display("TIMEOUT instrs");       $finish; end
        capture_byte(branches,     ok); if (!ok) begin $display("TIMEOUT branches");     $finish; end
        capture_byte(mispredicts,  ok); if (!ok) begin $display("TIMEOUT mispredicts");  $finish; end
        capture_byte(dcache_hits,  ok); if (!ok) begin $display("TIMEOUT dcache_hits");  $finish; end
        capture_byte(dcache_misses,ok); if (!ok) begin $display("TIMEOUT dcache_misses");$finish; end
        capture_byte(icache_hits,  ok); if (!ok) begin $display("TIMEOUT icache_hits");  $finish; end
        capture_byte(icache_misses,ok); if (!ok) begin $display("TIMEOUT icache_misses");$finish; end

        $display("  cycles        = %0d", cycles);
        $display("  instructions  = %0d", instrs);
        $display("  branches      = %0d", branches);
        $display("  mispredicts   = %0d", mispredicts);
        $display("  dcache hits   = %0d", dcache_hits);
        $display("  dcache misses = %0d", dcache_misses);
        $display("  icache hits   = %0d", icache_hits);
        $display("  icache misses = %0d", icache_misses);

        if (cycles > 0)
            $display("PASS: cycles > 0");
        else
            $display("FAIL: cycles = 0");

        if (instrs > 0)
            $display("PASS: instructions > 0");
        else
            $display("FAIL: instructions = 0");

        if (branches == 10)
            $display("PASS: branches = 10 (loop ran exactly 10 times)");
        else
            $display("FAIL: branches = %0d (expected 10)", branches);

        if (mispredicts <= branches)
            $display("PASS: mispredicts (%0d) <= branches (%0d)", mispredicts, branches);
        else
            $display("FAIL: mispredicts > branches");

        if (icache_hits > 0)
            $display("PASS: icache hits > 0");
        else
            $display("FAIL: icache hits = 0");

        $display("========== DONE ==========");
        $finish;
    end

endmodule