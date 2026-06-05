`timescale 1ns/1ps

module tb_uart_mem_map;

    localparam CLKS_PER_BIT = 10;

    logic        clk, rst;
    logic        we, re;
    logic [31:0] addr, wd, rd;
    logic        uart_tx_pin;
    logic        uart_rx_pin;
    logic        irq;

    uart_mem_map #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk         (clk),
        .rst         (rst),
        .we          (we),
        .re          (re),
        .addr        (addr),
        .wd          (wd),
        .rd          (rd),
        .uart_tx_pin (uart_tx_pin),
        .uart_rx_pin (uart_rx_pin),
        .irq         (irq)
    );

    initial begin
        $dumpfile("sim/uart_mem_map.vcd");
        $dumpvars(0, tb_uart_mem_map);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // collected TX bytes (sniffed from uart_tx_pin)
    logic [7:0] tx_captured [0:15];
    integer     tx_count;

    // receive one byte from uart_tx_pin
    task automatic capture_tx_byte(output [7:0] data);
        integer i;
        // wait for start bit
        while (uart_tx_pin == 1) @(posedge clk);
        // skip to mid-point of start bit
        repeat(CLKS_PER_BIT / 2) @(posedge clk);
        // sample 8 data bits at mid-point of each bit
        for (i = 0; i < 8; i++) begin
            repeat(CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx_pin;
        end
        // skip stop bit
        repeat(CLKS_PER_BIT) @(posedge clk);
    endtask

    // CPU write helper
    task automatic cpu_write(input [31:0] a, input [31:0] d);
        @(posedge clk); #1;
        we = 1; re = 0; addr = a; wd = d;
        @(posedge clk); #1;
        we = 0;
    endtask

    // CPU read helper
    task automatic cpu_read(input [31:0] a, output [31:0] result);
        @(posedge clk); #1;
        re = 1; we = 0; addr = a;
        @(posedge clk); #1;
        result = rd;
        re = 0;
    endtask

    // poll TX status until ready
    task automatic wait_tx_ready;
        logic [31:0] status;
        integer timeout;
        timeout = 0;
        do begin
            cpu_read(32'hFFFF0004, status);
            timeout++;
        end while (status[0] == 0 && timeout < 1000);
    endtask

    // drive one byte onto uart_rx_pin
    task automatic send_rx_byte(input [7:0] data);
        integer i;
        @(posedge clk); #1;
        uart_rx_pin = 0;                             // start bit
        repeat(CLKS_PER_BIT) @(posedge clk); #1;
        for (i = 0; i < 8; i++) begin
            uart_rx_pin = data[i];
            repeat(CLKS_PER_BIT) @(posedge clk); #1;
        end
        uart_rx_pin = 1;                             // stop bit
        repeat(CLKS_PER_BIT) @(posedge clk); #1;
    endtask

    logic [7:0] captured;
    logic [31:0] result;
    integer i;

    initial begin
        $display("========== UART MEM MAP TESTBENCH ==========");

        rst = 1; we = 0; re = 0;
        addr = 0; wd = 0;
        uart_rx_pin = 1;
        tx_count = 0;
        repeat(5) @(posedge clk); #1;
        rst = 0;
        repeat(5) @(posedge clk); #1;

        // -----------------------------------------------
        // TEST 1: TX status register reads ready initially
        // -----------------------------------------------
        $display("--- TEST 1: TX status = ready on reset ---");
        cpu_read(32'hFFFF0004, result);
        if (result[0] == 1) $display("PASS: TX ready");
        else                 $display("FAIL: TX status=0x%08h", result);

        // -----------------------------------------------
        // TEST 2: Write 'H' to TX and capture from pin
        // -----------------------------------------------
        $display("--- TEST 2: TX transmit 'H' ---");
        fork
            begin
                wait_tx_ready;
                cpu_write(32'hFFFF0000, 32'h48);
            end
            begin
                capture_tx_byte(captured);
                if (captured == 8'h48) $display("PASS: TX sent 0x%02h", captured);
                else                    $display("FAIL: TX got 0x%02h exp=0x48", captured);
            end
        join
        repeat(5) @(posedge clk); #1;

        // -----------------------------------------------
        // TEST 3: TX FIFO buffers multiple bytes
        // -----------------------------------------------
        $display("--- TEST 3: TX FIFO — write E, L, L, O ---");
        cpu_write(32'hFFFF0000, 32'h45); // E
        cpu_write(32'hFFFF0000, 32'h4C); // L
        cpu_write(32'hFFFF0000, 32'h4C); // L
        cpu_write(32'hFFFF0000, 32'h4F); // O
        // capture all four
        begin
            logic [7:0] exp [0:3];
            exp[0] = 8'h45; exp[1] = 8'h4C; exp[2] = 8'h4C; exp[3] = 8'h4F;
            for (i = 0; i < 4; i++) begin
                capture_tx_byte(captured);
                if (captured == exp[i]) $display("PASS: FIFO byte %0d = 0x%02h", i, captured);
                else                     $display("FAIL: FIFO byte %0d got=0x%02h exp=0x%02h", i, captured, exp[i]);
            end
        end
        repeat(5) @(posedge clk); #1;

        // -----------------------------------------------
        // TEST 4: IRQ low when no RX data
        // -----------------------------------------------
        $display("--- TEST 4: IRQ low before RX ---");
        if (!irq) $display("PASS: irq=0 before receive");
        else       $display("FAIL: irq unexpectedly high");

        // -----------------------------------------------
        // TEST 5: Receive byte, IRQ goes high
        // -----------------------------------------------
        $display("--- TEST 5: RX receive 0xA5, IRQ fires ---");
        send_rx_byte(8'hA5);
        repeat(5) @(posedge clk); #1;
        if (irq) $display("PASS: irq=1 after receive");
        else      $display("FAIL: irq did not fire");

        // -----------------------------------------------
        // TEST 6: Read RX register returns correct byte
        // -----------------------------------------------
        $display("--- TEST 6: Read RX register ---");
        cpu_read(32'hFFFF0008, result);
        if (result[7:0] == 8'hA5) $display("PASS: RX data=0x%02h", result[7:0]);
        else                       $display("FAIL: RX data=0x%08h exp=0xA5", result);

        // -----------------------------------------------
        // TEST 7: Reading RX clears IRQ
        // -----------------------------------------------
        $display("--- TEST 7: IRQ clears after RX read ---");
        repeat(2) @(posedge clk); #1;
        if (!irq) $display("PASS: irq=0 after read");
        else       $display("FAIL: irq still high after read");

        // -----------------------------------------------
        // TEST 8: RX status register
        // -----------------------------------------------
        $display("--- TEST 8: RX status clears after read ---");
        cpu_read(32'hFFFF000C, result);
        if (result[0] == 0) $display("PASS: RX status=0 after read");
        else                 $display("FAIL: RX status still set");

        // -----------------------------------------------
        // TEST 9: Second RX byte overwrites first
        // -----------------------------------------------
        $display("--- TEST 9: Second RX byte 0x3C ---");
        send_rx_byte(8'h3C);
        repeat(5) @(posedge clk); #1;
        cpu_read(32'hFFFF0008, result);
        if (result[7:0] == 8'h3C) $display("PASS: RX data=0x%02h", result[7:0]);
        else                       $display("FAIL: RX data=0x%08h exp=0x3C", result);
        repeat(2) @(posedge clk); #1;

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule