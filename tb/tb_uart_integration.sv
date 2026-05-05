`timescale 1ns/1ps

module tb_uart_integration;

    // use fast simulation baud rate
    localparam CLKS_PER_BIT = 10;
    localparam BIT_PERIOD   = 100;

    logic clk, rst;
    logic uart_tx_pin;

    // instantiate pipeline with UART
    top_pipeline #(
    .HEX_FILE("programs/uart_hello.hex"),
    .CLKS_PER_BIT(CLKS_PER_BIT)
) dut (
    .clk         (clk),
    .rst         (rst),
    .uart_tx_pin (uart_tx_pin)
);

    initial begin
        $dumpfile("sim/uart_integration.vcd");
        $dumpvars(0, tb_uart_integration);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    always @(negedge uart_tx_pin) begin
        $display("MONITOR: uart_tx_pin fell low at %0t", $time);
    end

    // receive one byte from serial line
    task automatic receive_byte(output logic [7:0] received, output logic ok);
    integer i;
    integer wait_cycles;
    received = 8'd0;
    ok = 0;

    // wait until the line is idle high
    wait_cycles = 0;
    while (uart_tx_pin !== 1'b1 && wait_cycles < 10000) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end
    if (wait_cycles >= 10000) begin
        $display("ERROR: UART idle timeout waiting for high at %0t (wait_cycles=%0d, uart_tx_pin=%b)", 
                 $time, wait_cycles, uart_tx_pin);
        ok = 0;
        return;
    end
    $display("receive_byte: line idle at %0t after %0d cycles", $time, wait_cycles);
    
    // wait for start bit edge (falling edge)
    @(negedge uart_tx_pin);
    $display("receive_byte: START BIT at %0t", $time);
    
    // After the start bit edge, wait 10 + 5 = 15 cycles to sample mid-first-bit
    repeat (15) @(posedge clk);
    
    for (i = 0; i < 8; i++) begin
        received[i] = uart_tx_pin;
        $display("  sample bit %0d at %0t = %b", i, $time, uart_tx_pin);
        repeat (10) @(posedge clk);  // advance one bit period (10 cycles)
    end
    
    // After 8 data bits, sample the stop bit (should be high)
    $display("  stop bit at %0t = %b", $time, uart_tx_pin);

    ok = 1;
endtask

    logic [7:0] ch;
    logic ok;
    integer i;

    initial begin
        $display("========== UART INTEGRATION TESTBENCH ==========");

        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Received: ");
        for (i = 0; i < 6; i++) begin
            receive_byte(ch, ok);
            if (!ok) begin
                $display("ERROR: failed to receive char %0d", i);
                $finish;
            end
            $display("  char[%0d] = 0x%02h ('%c')", i, ch, ch);
        end

        $display("========== DONE ==========");
        $finish;
    end

endmodule