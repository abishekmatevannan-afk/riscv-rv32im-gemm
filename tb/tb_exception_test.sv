`timescale 1ns/1ps

module tb_exception_test;

    localparam CLKS_PER_BIT = 10;

    logic clk, rst;
    logic uart_tx_pin;
    logic uart_rx_pin;

    top_pipeline #(
        .HEX_FILE     ("programs/exception_test.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) cpu (
        .clk         (clk),
        .rst         (rst),
        .uart_tx_pin (uart_tx_pin),
        .uart_rx_pin (uart_rx_pin)
    );

    initial begin
        $dumpfile("sim/exception_test.vcd");
        $dumpvars(0, tb_exception_test);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // capture one byte from uart_tx_pin
    task automatic capture_byte(output [7:0] data, output logic ok);
        integer timeout;
        // wait for start bit (line goes low)
        timeout = 0;
        while (uart_tx_pin == 1 && timeout < 100000) begin
            @(posedge clk); timeout++;
        end
        if (timeout == 100000) begin ok = 0; return; end
        // skip to mid-start-bit
        repeat(CLKS_PER_BIT/2) @(posedge clk);
        // sample 8 data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            repeat(CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx_pin;
        end
        // skip stop bit
        repeat(CLKS_PER_BIT) @(posedge clk);
        ok = 1;
    endtask

    logic [7:0] b0, b1;
    logic       ok0, ok1;

    initial begin
        $display("========== EXCEPTION TEST ==========");
        rst = 1;
        uart_rx_pin = 1;
        repeat(5) @(posedge clk);
        rst = 0;

        // byte 0: mcause low byte (expect 0x0B = 11 = ECALL from M-mode)
        capture_byte(b0, ok0);
        if (ok0 && b0 == 8'h0B)
            $display("PASS: mcause = 0x%02h (ECALL cause 11)", b0);
        else
            $display("FAIL: mcause = 0x%02h ok=%b (expected 0x0B)", b0, ok0);

        // byte 1: 'D' = 0x44 confirming MRET returned correctly
        capture_byte(b1, ok1);
        if (ok1 && b1 == 8'h44)
            $display("PASS: MRET returned, received 'D' = 0x%02h", b1);
        else
            $display("FAIL: post-MRET byte = 0x%02h ok=%b (expected 0x44)", b1, ok1);

        $display("========== DONE ==========");
        $finish;
    end

endmodule
