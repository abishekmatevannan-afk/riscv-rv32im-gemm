`timescale 1ns/1ps
// Testbench: exception handler stack
//
// Verifies that the trap handler correctly saves and restores registers.
//   1. Set x20=0xAA, x21=0xBB, x22=0xCC
//   2. ECALL → handler saves x20/x21/x22 on stack, sends mcause, restores, MRETs
//   3. After return: sends x20, x21, x22 over UART
//   4. Testbench checks all four bytes match expected values

module tb_exception_handler_stack;

    localparam CLKS_PER_BIT = 10;

    logic clk, rst;
    logic uart_tx_pin;

    top_pipeline #(
        .HEX_FILE    ("programs/exception_handler_stack.hex"),
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
        $dumpfile("sim/tb_exception_handler_stack.vcd");
        $dumpvars(0, tb_exception_handler_stack);
    end

    // capture one UART byte, 8N1, timeout after 1M cycles
    task automatic capture_byte(output logic [7:0] data, output logic ok);
        integer timeout;
        timeout = 0; ok = 0; data = 0;
        while (uart_tx_pin == 1 && timeout < 1000000) begin
            @(posedge clk); timeout++;
        end
        if (timeout >= 1000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            repeat(CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx_pin;
        end
        repeat(CLKS_PER_BIT) @(posedge clk);
        ok = 1;
    endtask

    logic [7:0] mcause_b, x20_b, x21_b, x22_b;
    logic       ok;
    integer     pass, fail;

    initial begin
        $display("========== EXCEPTION HANDLER STACK TESTBENCH ==========");
        $display("Checks that x20/x21/x22 survive a trap handler invocation");

        pass = 0; fail = 0;

        rst = 1;
        repeat(5) @(posedge clk); #1;
        rst = 0;

        // byte 0 — mcause, sent by the handler (ECALL cause = 0x0B = 11)
        capture_byte(mcause_b, ok);
        if (!ok) begin $display("TIMEOUT: mcause"); $finish; end
        if (mcause_b == 8'h0B) begin
            $display("PASS: mcause = 0x%02h (ECALL)", mcause_b); pass++;
        end else begin
            $display("FAIL: mcause = 0x%02h (expected 0x0B)", mcause_b); fail++;
        end

        // byte 1 — x20, sent after MRET (should still be 0xAA)
        capture_byte(x20_b, ok);
        if (!ok) begin $display("TIMEOUT: x20"); $finish; end
        if (x20_b == 8'hAA) begin
            $display("PASS: x20 = 0x%02h (preserved across trap)", x20_b); pass++;
        end else begin
            $display("FAIL: x20 = 0x%02h (expected 0xAA — handler corrupted x20)", x20_b); fail++;
        end

        // byte 2 — x21 (should still be 0xBB)
        capture_byte(x21_b, ok);
        if (!ok) begin $display("TIMEOUT: x21"); $finish; end
        if (x21_b == 8'hBB) begin
            $display("PASS: x21 = 0x%02h (preserved across trap)", x21_b); pass++;
        end else begin
            $display("FAIL: x21 = 0x%02h (expected 0xBB — handler corrupted x21)", x21_b); fail++;
        end

        // byte 3 — x22 (should still be 0xCC)
        capture_byte(x22_b, ok);
        if (!ok) begin $display("TIMEOUT: x22"); $finish; end
        if (x22_b == 8'hCC) begin
            $display("PASS: x22 = 0x%02h (preserved across trap)", x22_b); pass++;
        end else begin
            $display("FAIL: x22 = 0x%02h (expected 0xCC — handler corrupted x22)", x22_b); fail++;
        end

        $display("--- %0d passed  %0d failed ---", pass, fail);
        $display("========== DONE ==========");
        $finish;
    end

endmodule