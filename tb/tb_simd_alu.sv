`timescale 1ns/1ps

module tb_simd_alu;

    logic [31:0] a, b, result;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic        valid;

    simd_alu dut (
        .a       (a),
        .b       (b),
        .funct3  (funct3),
        .funct7  (funct7),
        .result  (result),
        .valid   (valid)
    );

    task automatic check(
        input [31:0] in_a, in_b,
        input [2:0]  f3,
        input [6:0]  f7,
        input [31:0] expected,
        input string op_name
    );
        a = in_a; b = in_b;
        funct3 = f3; funct7 = f7;
        #10;
        if (result !== expected)
            $display("FAIL: %s | a=0x%08h b=0x%08h expected=0x%08h got=0x%08h",
                     op_name, in_a, in_b, expected, result);
        else
            $display("PASS: %s | result=0x%08h", op_name, result);
    endtask

    initial begin
        $display("========== SIMD ALU TESTBENCH ==========");

        // PADD — add each byte lane independently
        // a = [1, 2, 3, 4], b = [5, 6, 7, 8]
        // result = [6, 8, 10, 12]
        check(
            32'h04030201,   // a: byte3=4 byte2=3 byte1=2 byte0=1
            32'h08070605,   // b: byte3=8 byte2=7 byte1=6 byte0=5
            3'b000, 7'b0000000,
            32'h0C0A0806,   // result: [12,10,8,6]
            "PADD basic"
        );

        // PADD — overflow wraps within byte lane
        check(
            32'hFF010101,
            32'h01010101,
            3'b000, 7'b0000000,
            32'h00020202,   // 0xFF+0x01 wraps to 0x00
            "PADD overflow wrap"
        );

        // PSUB
        check(
            32'h0A080604,
            32'h01020304,
            3'b000, 7'b0100000,
            32'h09060300,   // [10-1, 8-2, 6-3, 4-4]
            "PSUB basic"
        );

        // PMUL — lower 8 bits of each lane product
        // [2,3,4,5] * [2,3,4,5] = [4,9,16,25]
        check(
            32'h05040302,
            32'h05040302,
            3'b001, 7'b0000000,
            32'h19100904,   // [25,16,9,4]
            "PMUL basic"
        );

        // PMUL — overflow truncates to 8 bits
        // 0xFF * 0xFF = 0xFE01, lower 8 bits = 0x01
        check(
            32'hFFFFFFFF,
            32'hFFFFFFFF,
            3'b001, 7'b0000000,
            32'h01010101,
            "PMUL overflow truncate"
        );

        // PDOT — dot product
        // [1,2,3,4] . [1,2,3,4] = 1+4+9+16 = 30
        check(
            32'h04030201,
            32'h04030201,
            3'b010, 7'b0000000,
            32'h0000001E,   // 30 decimal
            "PDOT [1,2,3,4].[1,2,3,4]=30"
        );

        // PDOT — neural network relevant
        // [128,64,32,16] . [1,2,4,8] = 128+128+128+128 = 512
        check(
            32'h10204080,
            32'h08040201,
            3'b010, 7'b0000000,
            32'h00000200,   // 512 decimal
            "PDOT neural network weights"
        );

        // PDOT — zero vector
        check(
            32'h00000000,
            32'hFFFFFFFF,
            3'b010, 7'b0000000,
            32'h00000000,
            "PDOT zero vector"
        );

        // invalid funct3
        check(
            32'hFFFFFFFF,
            32'hFFFFFFFF,
            3'b111, 7'b0000000,
            32'h00000000,
            "invalid op returns 0"
        );

        $display("========== DONE ==========");
        $finish;
    end

endmodule