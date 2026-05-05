// Tests UART transmitter by sending characters and
// checking the serial output bit pattern

`timescale 1ns/1ps

module tb_uart_tx;

    // use small CLKS_PER_BIT for fast simulation
    localparam CLKS_PER_BIT = 10;
    localparam BIT_PERIOD   = 100; // ns (CLKS_PER_BIT * 10ns clock)

    logic       clk, rst;
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_serial;
    logic       tx_busy;
    logic       tx_done;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk       (clk),
        .rst       (rst),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_serial (tx_serial),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

    initial begin
        $dumpfile("sim/uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // task to send one byte and capture received bits
    task automatic send_and_check(
        input [7:0] data,
        input string char_name
    );
        logic [7:0] received;
        integer i;

        // send the byte
        @(posedge clk);
        tx_data  = data;
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;

        // wait for start bit — sample in middle of bit
        #(BIT_PERIOD / 2);
        if (tx_serial !== 1'b0)
            $display("FAIL: %s start bit | expected 0 got %b",
                     char_name, tx_serial);

        // sample each data bit in middle of bit period
        for (i = 0; i < 8; i++) begin
            #BIT_PERIOD;
            received[i] = tx_serial;
        end

        // check stop bit
        #BIT_PERIOD;
        if (tx_serial !== 1'b1)
            $display("FAIL: %s stop bit | expected 1 got %b",
                     char_name, tx_serial);

        // verify received data
        if (received !== data)
            $display("FAIL: %s | expected=0x%02h got=0x%02h",
                     char_name, data, received);
        else
            $display("PASS: %s | sent=0x%02h received=0x%02h '%s'",
                     char_name, data, received, char_name);

        // wait for tx_done
        @(posedge tx_done);
    endtask

    initial begin
        $display("========== UART TX TESTBENCH ==========");

        rst      = 1;
        tx_start = 0;
        tx_data  = 0;
        repeat(5) @(posedge clk);
        rst = 0;

        // test individual characters
        send_and_check(8'h48, "H");   // 0x48
        send_and_check(8'h45, "E");   // 0x45
        send_and_check(8'h4C, "L");   // 0x4C
        send_and_check(8'h4C, "L");   // 0x4C
        send_and_check(8'h4F, "O");   // 0x4F
        send_and_check(8'h0A, "LF");  // newline

        // test that tx_busy works
        @(posedge clk);
        tx_data  = 8'h41; // 'A'
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;
        @(posedge clk);
        if (!tx_busy)
            $display("FAIL: tx_busy should be high during transmission");
        else
            $display("PASS: tx_busy high during transmission");

        @(posedge tx_done);
        repeat(3) @(posedge clk);
        #1;
        if (tx_busy)
            $display("FAIL: tx_busy should be low after done");
        else
            $display("PASS: tx_busy low after transmission");

        $display("========== DONE ==========");
        $finish;
    end

endmodule