`timescale 1ns/1ps

module tb_uart_rx;

    localparam CLKS_PER_BIT = 10;  // fast for simulation
    localparam BIT_PERIOD   = 100; // ns (10 cycles * 10ns)

    logic       clk, rst;
    logic       rx_serial;
    logic [7:0] rx_data;
    logic       rx_done;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk       (clk),
        .rst       (rst),
        .rx_serial (rx_serial),
        .rx_data   (rx_data),
        .rx_done   (rx_done),
        .rx_valid  (rx_valid)
    );

    initial begin
        $dumpfile("sim/uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // send one byte over serial (8N1)
    task automatic send_byte(input [7:0] data);
        integer i;
        @(posedge clk); #1;
        rx_serial = 0;               // start bit
        repeat(CLKS_PER_BIT) @(posedge clk); #1;
        for (i = 0; i < 8; i++) begin
            rx_serial = data[i];
            repeat(CLKS_PER_BIT) @(posedge clk); #1;
        end
        rx_serial = 1;               // stop bit
        repeat(CLKS_PER_BIT) @(posedge clk); #1;
    endtask

    // wait for rx_done with timeout
    task automatic wait_done(output logic [7:0] result, output logic ok);
        integer timeout;
        timeout = 0;
        ok = 0;
        while (timeout < 2000) begin
            @(posedge clk); #1;
            timeout++;
            if (rx_done) begin
                result = rx_data;
                ok = 1;
                return;
            end
        end
    endtask
    

    logic [7:0] received;
    logic       ok;
    logic       got_done;

    // run send and receive concurrently
    task automatic send_and_receive(input [7:0] data, output [7:0] result, output logic success);
        got_done = 0;
        fork
            send_byte(data);
            begin : wait_block
                integer timeout;
                timeout = 0;
                success = 0;
                while (timeout < 2000 && !got_done) begin
                    @(posedge clk); #1;
                    timeout++;
                    if (rx_done) begin
                        result   = rx_data;
                        success  = 1;
                        got_done = 1;
                    end
                end
            end
        join
    endtask

    initial begin
        $display("========== UART RX TESTBENCH ==========");

        rst = 1;
        rx_serial = 1;
        repeat(5) @(posedge clk); #1;
        rst = 0;
        rx_serial = 1;
        repeat(15) @(posedge clk); #1;

        // TEST 1
        $display("--- TEST 1: Receive 0x48 ('H') ---");
        send_and_receive(8'h48, received, ok);
        if (ok && received == 8'h48) $display("PASS: received 0x%02h", received);
        else $display("FAIL: ok=%b received=0x%02h expected=0x48", ok, received);
        rx_serial = 1; repeat(15) @(posedge clk); #1;

        // TEST 2
        $display("--- TEST 2: Receive 0xFF ---");
        send_and_receive(8'hFF, received, ok);
        if (ok && received == 8'hFF) $display("PASS: received 0x%02h", received);
        else $display("FAIL: ok=%b received=0x%02h expected=0xFF", ok, received);
        rx_serial = 1; repeat(15) @(posedge clk); #1;

        // TEST 3
        $display("--- TEST 3: Receive 0x00 ---");
        send_and_receive(8'h00, received, ok);
        if (ok && received == 8'h00) $display("PASS: received 0x%02h", received);
        else $display("FAIL: ok=%b received=0x%02h expected=0x00", ok, received);
        rx_serial = 1; repeat(15) @(posedge clk); #1;

        // TEST 4
        $display("--- TEST 4: Receive 0xAB ---");
        send_and_receive(8'hAB, received, ok);
        if (ok && received == 8'hAB) $display("PASS: received 0x%02h", received);
        else $display("FAIL: ok=%b received=0x%02h expected=0xAB", ok, received);
        rx_serial = 1; repeat(15) @(posedge clk); #1;

        // TEST 5
        $display("--- TEST 5: Receive 0xCD ---");
        send_and_receive(8'hCD, received, ok);
        if (ok && received == 8'hCD) $display("PASS: received 0x%02h", received);
        else $display("FAIL: ok=%b received=0x%02h expected=0xCD", ok, received);
        rx_serial = 1; repeat(15) @(posedge clk); #1;

        // TEST 6: noise rejection
        $display("--- TEST 6: Noise rejection ---");
        rx_serial = 0; #20;
        rx_serial = 1; #80;
        repeat(10) @(posedge clk); #1;
        if (!rx_done) $display("PASS: glitch ignored");
        else $display("FAIL: false byte triggered");

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule