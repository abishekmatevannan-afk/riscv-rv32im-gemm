// Testbench for RV32I register file

`timescale 1ns/1ps

module tb_register_file;
    logic        clk;
    logic        we;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] wd;
    logic [31:0] rd1, rd2;

    register_file dut (
        .clk(clk),
        .we(we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .wd(wd),
        .rd1(rd1),
        .rd2(rd2)
    );

    initial begin
        $dumpfile("sim/register_file.vcd");
        $dumpvars(0, tb_register_file);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic write_reg(input [4:0] addr, input [31:0] data);
        begin
            we = 1;
            rd = addr;
            wd = data;
            @(posedge clk);
            #1;
            we = 0;
        end
    endtask

    task automatic check_read(input [4:0] addr, input [31:0] expected, input string test_name);
        begin
            rs1 = addr;
            #10;
            if (rd1 !== expected)
                $display("FAIL: %s | addr=x%0d | expected=0x%08h got=0x%08h",
                         test_name, addr, expected, rd1);
            else
                $display("PASS: %s | addr=x%0d | value=0x%08h",
                         test_name, addr, expected);
        end
    endtask

    initial begin
        $display("========== REGISTER FILE TESTBENCH ==========");

        we = 0; rs1 = 0; rs2 = 0; rd = 0; wd = 0;
        #10;

        check_read(5'd0, 32'd0, "x0 reads zero");
        write_reg(5'd0, 32'hDEADBEEF);
        check_read(5'd0, 32'd0, "x0 write ignored");
        write_reg(5'd1, 32'hAABBCCDD);
        check_read(5'd1, 32'hAABBCCDD, "write/read x1");

        write_reg(5'd5,  32'd100);
        write_reg(5'd10, 32'd200);
        write_reg(5'd15, 32'd300);
        check_read(5'd5,  32'd100, "write/read x5");
        check_read(5'd10, 32'd200, "write/read x10");
        check_read(5'd15, 32'd300, "write/read x15");

        rs1 = 5'd5;
        rs2 = 5'd10;
        #10;
        if (rd1 !== 32'd100 || rd2 !== 32'd200)
            $display("FAIL: dual read | x5=0x%08h x10=0x%08h", rd1, rd2);
        else
            $display("PASS: dual port read | x5=%0d x10=%0d", rd1, rd2);

        write_reg(5'd1, 32'h11111111);
        check_read(5'd1, 32'h11111111, "overwrite x1");

        check_read(5'd0, 32'd0, "x0 still zero after bulk");

        $display("========== DONE ==========");
        $finish;
    end
endmodule
