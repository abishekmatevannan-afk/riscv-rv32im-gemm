`timescale 1ns/1ps

module tb_data_memory;

    logic        clk, we, re;
    logic [31:0] addr, wd;
    logic [2:0]  funct3;
    logic [31:0] rd;

    data_memory dut (
        .clk    (clk),
        .we     (we),
        .re     (re),
        .addr   (addr),
        .wd     (wd),
        .funct3 (funct3),
        .rd     (rd)
    );

    initial begin
        $dumpfile("sim/data_memory.vcd");
        $dumpvars(0, tb_data_memory);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // write then read back and check
    task automatic check(
        input [31:0] write_addr,
        input [31:0] write_data,
        input [2:0]  write_funct3,
        input [31:0] read_addr,
        input [2:0]  read_funct3,
        input [31:0] expected,
        input string test_name
    );
        // write
        we = 1; re = 0;
        addr = write_addr;
        wd = write_data;
        funct3 = write_funct3;
        @(posedge clk); #1;
        we = 0;

        // read
        re = 1;
        addr = read_addr;
        funct3 = read_funct3;
        #10;
        re = 0;

        if (rd !== expected)
            $display("FAIL: %s | expected=0x%08h got=0x%08h",
                     test_name, expected, rd);
        else
            $display("PASS: %s | value=0x%08h", test_name, rd);
    endtask

    initial begin
        $display("========== DATA MEMORY TESTBENCH ==========");

        we = 0; re = 0; addr = 0; wd = 0; funct3 = 0;
        #10;

        // SW then LW — basic word
        check(32'd0,  32'hDEADBEEF, 3'b010,
              32'd0,  3'b010, 32'hDEADBEEF, "SW/LW word");

        // SW then LW — different address
        check(32'd4,  32'h12345678, 3'b010,
              32'd4,  3'b010, 32'h12345678, "SW/LW addr 4");

        // SB then LBU — unsigned byte
        check(32'd8,  32'hABCDEF99, 3'b000,
              32'd8,  3'b100, 32'h00000099, "SB/LBU");

        // SB then LB — signed byte (negative)
        check(32'd9,  32'hFFFFFF80, 3'b000,
              32'd9,  3'b000, 32'hFFFFFF80, "SB/LB signed");

        // SB then LB — signed byte (positive)
        check(32'd10, 32'h0000007F, 3'b000,
              32'd10, 3'b000, 32'h0000007F, "SB/LB positive");

        // SH then LHU — unsigned halfword
        check(32'd12, 32'h0000ABCD, 3'b001,
              32'd12, 3'b101, 32'h0000ABCD, "SH/LHU");

        // SH then LH — signed halfword (negative)
        check(32'd16, 32'h00008000, 3'b001,
              32'd16, 3'b001, 32'hFFFF8000, "SH/LH signed");

        // write multiple bytes, read as word
        check(32'd20, 32'h11223344, 3'b010,
              32'd20, 3'b010, 32'h11223344, "SW then LW verify");

        // verify little-endian byte ordering
        // after storing 0x11223344 at addr 20:
        // mem[20]=0x44 mem[21]=0x33 mem[22]=0x22 mem[23]=0x11
        we = 0; re = 1;
        addr = 32'd20; funct3 = 3'b100; #10; // LBU addr 20
        if (rd !== 32'h00000044)
            $display("FAIL: little-endian byte 0 | expected=0x44 got=0x%08h", rd);
        else
            $display("PASS: little-endian byte 0 = 0x44");

        addr = 32'd21; funct3 = 3'b100; #10; // LBU addr 21
        if (rd !== 32'h00000033)
            $display("FAIL: little-endian byte 1 | expected=0x33 got=0x%08h", rd);
        else
            $display("PASS: little-endian byte 1 = 0x33");

        re = 0;

        $display("========== DONE ==========");
        $finish;
    end

endmodule