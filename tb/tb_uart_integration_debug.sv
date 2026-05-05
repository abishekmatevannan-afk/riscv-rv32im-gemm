`timescale 1ns/1ps

module tb_uart_integration_debug;
    localparam CLKS_PER_BIT = 10;
    logic clk, rst;
    logic uart_tx_pin;

    top_pipeline #(
        .HEX_FILE("programs/uart_hello.hex"),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .uart_tx_pin(uart_tx_pin)
    );

    initial begin
        $dumpfile("sim/uart_integration_debug.vcd");
        $dumpvars(0, tb_uart_integration_debug);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    logic uart_tx_pin_d;
    logic [3:0] fifo_count_d;

    always @(posedge clk) begin
        uart_tx_pin_d <= uart_tx_pin;
        fifo_count_d <= dut.UART_MAP.fifo_count;
        if (uart_tx_pin !== uart_tx_pin_d) begin
            $display("%0t uart_tx_pin changed: %b -> %b", $time, uart_tx_pin_d, uart_tx_pin);
        end
        if (dut.UART_MAP.fifo_count !== fifo_count_d) begin
            $display("%0t UART FIFO count changed: %0d -> %0d", $time,
                     fifo_count_d,
                     dut.UART_MAP.fifo_count);
        end
        if (dut.uart_we) begin
            $display("%0t uart_we: wd=0x%02h (char '%c')", $time,
                     dut.mem_rs2_data[7:0],
                     dut.mem_rs2_data[7:0]);
        end
        if (dut.UART_MAP.tx_start) begin
            $display("%0t tx_start: tx_data=0x%02h (char '%c')", $time,
                     dut.UART_MAP.tx_data,
                     dut.UART_MAP.tx_data);
        end
    end

    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (4000) @(posedge clk);
        $display("DONE after 4000 cycles");
        $finish;
    end

endmodule
