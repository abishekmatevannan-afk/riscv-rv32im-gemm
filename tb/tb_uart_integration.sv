`timescale 1ns/1ps

// Runs HELLO UART test (cpu1) then perf-counter UART demo (cpu2).
// Note for Icarus Verilog: a task cannot sample a serial pin passed as `input logic`;
// the copy is sampled once — use tasks that reference uart_tx/clk nets directly.
// VCD is off by default. Pass `-DUART_INTEGRATION_DUMP_VCD` to iverilog to enable dumping.
module tb_uart_integration;

`ifdef UART_INTEGRATION_DUMP_VCD
    initial begin
        $dumpfile("sim/uart_integration.vcd");
        $dumpvars(0, tb_uart_integration);
    end
`endif

    localparam CLKS_PER_BIT = 10;

    // CPU 1 — HELLO (hold in reset after TEST 1 so the sim isn’t ticking two pipelines forever.)
    logic clk1;
    logic rst1 = 1;
    logic uart_tx1;
    logic freeze_cpu1 = 1'b0;
    logic rst1_to_cpu;

    assign rst1_to_cpu = rst1 | freeze_cpu1;

    top_pipeline #(
        .HEX_FILE("programs/uart_hello.hex"),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) cpu1 (
        .clk         (clk1),
        .rst         (rst1_to_cpu),
        .uart_tx_pin (uart_tx1)
    );

    // CPU 2 — perf demo
    logic clk2;
    logic rst2 = 1;
    logic uart_tx2;

    top_pipeline #(
        .HEX_FILE("programs/perf_demo.hex"),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) cpu2 (
        .clk         (clk2),
        .rst         (rst2),
        .uart_tx_pin (uart_tx2)
    );

    initial clk1 = 0;
    always #5 clk1 = ~clk1;

    initial clk2 = 0;
    always #5 clk2 = ~clk2;

    task automatic receive_byte_tx1(
        output logic [7:0] received,
        output logic       ok
    );
        integer i;
        integer wait_cycles;
        received = 8'd0;
        ok       = 0;

        wait_cycles = 0;
        while (uart_tx1 !== 1'b1 && wait_cycles < 1000000) begin
            @(posedge clk1);
            wait_cycles = wait_cycles + 1;
        end
        if (wait_cycles >= 1000000) begin
            $display("ERROR: UART idle timeout waiting for high (tx1)");
            ok = 0;
            return;
        end

        @(negedge uart_tx1);

        repeat (15) @(posedge clk1);
        for (i = 0; i < 8; i++) begin
            received[i] = uart_tx1;
            repeat (10) @(posedge clk1);
        end
        ok = 1;
    endtask

    task automatic receive_byte_tx2(
        output logic [7:0] received,
        output logic       ok
    );
        integer i;
        integer wait_cycles;
        received = 8'd0;
        ok       = 0;

        wait_cycles = 0;
        while (uart_tx2 !== 1'b1 && wait_cycles < 1000000) begin
            @(posedge clk2);
            wait_cycles = wait_cycles + 1;
        end
        if (wait_cycles >= 1000000) begin
            $display("ERROR: UART idle timeout waiting for high (tx2)");
            ok = 0;
            return;
        end

        @(negedge uart_tx2);

        repeat (15) @(posedge clk2);
        for (i = 0; i < 8; i++) begin
            received[i] = uart_tx2;
            repeat (10) @(posedge clk2);
        end
        ok = 1;
    endtask

    logic [7:0] ch;
    logic       ok;
    integer     i;

    initial begin
        $display("========== UART INTEGRATION TESTBENCH ==========");

        rst1 = 1;
        rst2 = 1;
        repeat (5) @(posedge clk1);

        rst1 = 0;
        @(posedge clk1);

        // ---- TEST 1: UART HELLO ----
        $display("--- TEST 1: UART HELLO ---");
        $display("Received:");
        for (i = 0; i < 6; i++) begin
            receive_byte_tx1(ch, ok);
            if (!ok) begin
                $display("ERROR: HELLO failed at char %0d", i);
                $finish;
            end
            if (ch == 8'h0A)
                $display("  char[%0d] = 0x%02h ('\\n')", i, ch);
            else
                $display("  char[%0d] = 0x%02h ('%c')", i, ch, ch);
        end
        $display("PASS: HELLO transmission complete");
        $display("");
        freeze_cpu1 = 1;

        rst2 = 0;
       

        // ---- TEST 2: PERFORMANCE COUNTERS ----
        $display("--- TEST 2: PERFORMANCE COUNTERS ---");
        $display("Counter readings:");

        for (i = 0; i < 4; i++) begin
            receive_byte_tx2(ch, ok);
            if (!ok) begin
                $display("ERROR: PERF failed at counter %0d", i);
                $finish;
            end
            case (i)
                0: $display("  cycles       = %0d", ch);
                1: $display("  instructions = %0d", ch);
                2: $display("  branches     = %0d", ch);
                3: $display("  mispredicts  = %0d", ch);
            endcase
        end

        receive_byte_tx2(ch, ok);
        if (!ok) begin
            $display("ERROR: PERF failed to receive newline");
            $finish;
        end
        if (ch == 8'h0A)
            $display("PASS: newline received");
        else
            $display("ERROR: PERF newline byte wrong: 0x%02h", ch);

        $display("PASS: performance counter transmission complete");

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule
