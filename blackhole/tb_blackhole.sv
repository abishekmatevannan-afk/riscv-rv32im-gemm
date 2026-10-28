`timescale 1ns/1ps
// Testbench: black hole renderer on the full pipeline
//
// Runs blackhole.hex on top_pipeline, receives the 64x64 image over the real
// UART TX pin (8N1), writes it to out/blackhole_cpu.hex, and compares it byte
// for byte with expected.hex from the bit-exact Python model.

module tb_blackhole;

    localparam CLKS_PER_BIT = 4;
    localparam NPIX         = 64 * 64;
    localparam MAX_CYCLES   = 40_000_000;

    logic clk, rst;
    logic uart_tx_pin;

    top_pipeline #(
        .HEX_FILE    ("blackhole.hex"),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(1'b1)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    longint cycles = 0;
    always @(posedge clk) cycles++;

    // receive one 8N1 byte from the TX pin
    task automatic recv_byte(output logic [7:0] data, output logic ok);
        ok = 0; data = 0;
        while (uart_tx_pin == 1) begin
            @(posedge clk);
            if (cycles > MAX_CYCLES) return;
        end
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx_pin;
        end
        repeat (CLKS_PER_BIT) @(posedge clk);
        ok = 1;
    endtask

    logic [7:0] expected [0:NPIX-1];
    logic [7:0] image    [0:NPIX-1];

    initial begin
        logic [7:0] b;
        logic       ok;
        integer     n, mismatches, fd;

        $readmemh("expected.hex", expected);
        $display("========== BLACK HOLE RENDER ==========");
        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;

        for (n = 0; n < NPIX; n++) begin
            recv_byte(b, ok);
            if (!ok) begin
                $display("TIMEOUT: only %0d of %0d pixels received after %0d cycles", n, NPIX, cycles);
                $finish;
            end
            image[n] = b;
            if (n == 0)
                $display("  ray table done, first pixel at cycle %0d", cycles);
            if (n % 1024 == 1023)
                $display("  %0d / %0d pixels  (cycle %0d)", n + 1, NPIX, cycles);
        end

        fd = $fopen("out/blackhole_cpu.hex", "w");
        for (n = 0; n < NPIX; n++) $fdisplay(fd, "%02h", image[n]);
        $fclose(fd);

        mismatches = 0;
        for (n = 0; n < NPIX; n++)
            if (image[n] !== expected[n]) begin
                if (mismatches < 5)
                    $display("  mismatch at pixel (%0d, %0d): cpu=%0d model=%0d",
                             n % 64, n / 64, image[n], expected[n]);
                mismatches++;
            end

        $display("cycles: %0d   instructions retired: %0d   CPI: %0.3f",
                 cycles, cpu.PERF.instr_count, real'(cycles) / cpu.PERF.instr_count);
        $display("branches: %0d   mispredicts: %0d (%0.2f%%)",
                 cpu.PERF.branch_count, cpu.PERF.mispredict_count,
                 100.0 * cpu.PERF.mispredict_count / cpu.PERF.branch_count);
        $display("D$ hits/misses: %0d / %0d   I$ hits/misses: %0d / %0d",
                 cpu.PERF.cache_hit_count, cpu.PERF.cache_miss_count,
                 cpu.PERF.icache_hit_count, cpu.PERF.icache_miss_count);
        if (mismatches == 0)
            $display("PASS: all %0d pixels match the bit-exact model", NPIX);
        else
            $display("FAIL: %0d of %0d pixels differ from the model", mismatches, NPIX);
        $display("========== DONE ==========");
        $finish;
    end

endmodule
