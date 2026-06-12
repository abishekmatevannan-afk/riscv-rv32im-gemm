`timescale 1ns/1ps

module tb_simd_alu;

    logic [31:0] a, b, acc, result;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic        valid;

    simd_alu dut (
        .a       (a),
        .b       (b),
        .acc     (acc),
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
        a = in_a; b = in_b; acc = 32'd0;
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

        // PMACC — acc=0: result == PDOT
        // [1,2,3,4].[5,6,7,8] = 5+12+21+32 = 70; acc=0 → result=70
        begin
            a = 32'h04030201; b = 32'h08070605; acc = 32'd0;
            funct3 = 3'b011; funct7 = 7'b0000000; #10;
            if (result !== 32'd70)
                $display("FAIL: PMACC acc=0 | expected 70, got %0d", result);
            else
                $display("PASS: PMACC acc=0 | result=70");
        end

        // PMACC — chain: acc=70 → result=140
        begin
            a = 32'h04030201; b = 32'h08070605; acc = 32'd70;
            funct3 = 3'b011; funct7 = 7'b0000000; #10;
            if (result !== 32'd140)
                $display("FAIL: PMACC acc=70 | expected 140, got %0d", result);
            else
                $display("PASS: PMACC acc=70 | result=140 (chain)");
        end

        // PMACC — large accumulator: 4*255*255=260100; acc=260100 → result=520200
        begin
            a = 32'hFFFFFFFF; b = 32'hFFFFFFFF; acc = 32'd260100;
            funct3 = 3'b011; funct7 = 7'b0000000; #10;
            if (result !== 32'd520200)
                $display("FAIL: PMACC large | expected 520200, got %0d", result);
            else
                $display("PASS: PMACC large | result=520200 (INT32 accumulator)");
        end

        // PMACC — chain: acc=70 → result=140
        begin
            a = 32'h04030201; b = 32'h08070605; acc = 32'd70;
            funct3 = 3'b011; funct7 = 7'b0000000; #10;
            if (result !== 32'd140)
                $display("FAIL: PMACC acc=70 | expected 140, got %0d", result);
            else
                $display("PASS: PMACC acc=70 | result=140 (chain)");
        end

        // PSRA — shamt=1: [100, -4, 50, -128] >> 1 = [50, -2, 25, -64]
        // a = {-128, 50, -4, 100} = {0x80, 0x32, 0xFC, 0x64}
        // a = 0x8032FC64
        // expected = {0xC0, 0x19, 0xFE, 0x32} = 0xC019FE32
        check(
            32'h8032FC64,
            32'h00000000,         // b unused
            3'b100, 7'b0010001,   // funct3=100, funct7=001_0001 → shamt=1
            32'hC019FE32,
            "PSRA shamt=1 mixed signs"
        );

        // PSRA — shamt=0: identity
        check(
            32'hDEADBEEF,
            32'h00000000,
            3'b100, 7'b0010000,   // shamt=0 (funct7=0010000)
            32'hDEADBEEF,
            "PSRA shamt=0 identity"
        );

        // PSRA — shamt=7: all positive → 0 or 1, negative → -1 (0xFF)
        // a = {0x40, 0xFF, 0x7F, 0x80} = 0x40FF7F80
        // 0x40>>7=0, 0xFF(-1)>>7=-1=0xFF, 0x7F>>7=0, 0x80(-128)>>7=-1=0xFF
        // expected = {0x00, 0xFF, 0x00, 0xFF} = 0x00FF00FF
        check(
            32'h40FF7F80,
            32'h00000000,
            3'b100, 7'b0010111,   // shamt=7 (funct7=001_0111)
            32'h00FF00FF,
            "PSRA shamt=7 sign saturation"
        );

        // PSRA — shamt=8 (>=8 fills with sign bit)
        // a = {0x80, 0x7F, 0x80, 0x7F}: neg→0xFF, pos→0x00
        // expected = {0xFF, 0x00, 0xFF, 0x00} = 0xFF00FF00
        check(
            32'h807F807F,
            32'h00000000,
            3'b100, 7'b0011000,   // shamt=8 (funct7=001_1000, bit3=1 → saturate)
            32'hFF00FF00,
            "PSRA shamt=8 saturate"
        );

        // PRELU — all non-negative: passes through unchanged
        // a = {0x7F, 0x01, 0x00, 0x64} = 0x7F010064
        check(
            32'h7F010064,
            32'h00000000,
            3'b101, 7'b0100000,
            32'h7F010064,
            "PRELU all non-negative passthrough"
        );

        // PRELU — all negative: all zeroed
        // a = {0xFF, 0x80, 0xFE, 0x81} = 0xFF80FE81 (signed: -1,-128,-2,-127)
        check(
            32'hFF80FE81,
            32'h00000000,
            3'b101, 7'b0100000,
            32'h00000000,
            "PRELU all negative zeroed"
        );

        // PRELU — mixed: positive lanes pass, negative lanes zeroed
        // a = {0x7F(127), 0xFF(-1), 0x01(1), 0x80(-128)}
        // a = 0x7FFF0180
        // expected = {0x7F, 0x00, 0x01, 0x00} = 0x7F000100
        check(
            32'h7FFF0180,
            32'h00000000,
            3'b101, 7'b0100000,
            32'h7F000100,
            "PRELU mixed lanes"
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