`timescale 1ns/1ps
// Unit test for simd_alu PMACC (funct3=3'b011): rd = acc + PDOT(rs1, rs2)
//
// Tests:
//  1. PMACC with acc=0 equals PDOT
//  2. PMACC chains accumulate: two passes of the same inputs double the result
//  3. Large accumulator: verify 32-bit result with 4*255*255=260100 per pass
//  4. Regression: PADD / PSUB / PMUL / PDOT unaffected by new acc input
//
// The acc input is the forwarded or register-file rd value; in this unit test
// we drive it directly to isolate ALU correctness from pipeline forwarding.

module tb_pmacc;

    logic [31:0] a, b, acc;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] result;
    logic        valid;

    simd_alu dut (
        .a(a), .b(b), .acc(acc),
        .funct3(funct3), .funct7(funct7),
        .result(result), .valid(valid)
    );

    integer pass_cnt, fail_cnt;

    task automatic check(
        input string      name,
        input [31:0]      got,
        input [31:0]      expected
    );
        if (got === expected) begin
            $display("PASS: %s = %0d", name, got);
            pass_cnt++;
        end else begin
            $display("FAIL: %s expected %0d, got %0d", name, expected, got);
            fail_cnt++;
        end
    endtask

    initial begin
        $dumpfile("sim/tb_pmacc.vcd");
        $dumpvars(0, tb_pmacc);

        pass_cnt = 0; fail_cnt = 0;
        funct7 = 7'b0000000;
        a = 0; b = 0; acc = 0;

        $display("========== PMACC UNIT TEST ==========");

        // ----------------------------------------------------------------
        // TEST 1: PMACC with acc=0 must equal PDOT(a,b)
        // a={1,2,3,4}=0x04030201, b={5,6,7,8}=0x08070605
        // pdot = 1*5 + 2*6 + 3*7 + 4*8 = 5+12+21+32 = 70
        // ----------------------------------------------------------------
        $display("\n--- Test 1: PMACC with acc=0 equals PDOT ---");
        funct3 = 3'b011;
        a = 32'h04030201; b = 32'h08070605; acc = 32'd0;
        #10;
        check("PMACC(acc=0)", result, 32'd70);
        check("valid=1",      {31'd0,valid}, 32'd1);

        // Verify PDOT gives same answer (acc input must not break PDOT)
        funct3 = 3'b010;
        #10;
        check("PDOT(same inputs)", result, 32'd70);

        // ----------------------------------------------------------------
        // TEST 2: PMACC chain — two passes accumulate correctly
        // Pass 1: acc=0 → result=70
        // Pass 2: acc=70 → result=140  (simulates back-to-back PMACC on same rd)
        // Pass 3: acc=140 → result=210 (third pass)
        // ----------------------------------------------------------------
        $display("\n--- Test 2: PMACC chain accumulation ---");
        funct3 = 3'b011;
        a = 32'h04030201; b = 32'h08070605;

        acc = 32'd0; #10; check("chain pass1 (acc=0)",   result, 32'd70);
        acc = 32'd70; #10; check("chain pass2 (acc=70)", result, 32'd140);
        acc = 32'd140; #10; check("chain pass3 (acc=140)", result, 32'd210);

        // ----------------------------------------------------------------
        // TEST 3: Uniform inputs, simple accumulate
        // a=b={2,2,2,2}=0x02020202: pdot = 4*4 = 16
        // ----------------------------------------------------------------
        $display("\n--- Test 3: Uniform inputs ---");
        funct3 = 3'b011;
        a = 32'h02020202; b = 32'h02020202;

        acc = 32'd0;  #10; check("uniform acc=0",  result, 32'd16);
        acc = 32'd16; #10; check("uniform acc=16", result, 32'd32);
        acc = 32'd32; #10; check("uniform acc=32", result, 32'd48);

        // ----------------------------------------------------------------
        // TEST 4: Large accumulator — 4*255*255 = 260100 per pass
        // Verifies 32-bit accumulator is not truncated
        // ----------------------------------------------------------------
        $display("\n--- Test 4: Large values (INT32 accumulator) ---");
        funct3 = 3'b011;
        a = 32'hFFFFFFFF; b = 32'hFFFFFFFF;  // all 255s

        acc = 32'd0;      #10; check("large pass1 (acc=0)",      result, 32'd260100);
        acc = 32'd260100; #10; check("large pass2 (acc=260100)", result, 32'd520200);
        acc = 32'd520200; #10; check("large pass3 (acc=520200)", result, 32'd780300);

        // ----------------------------------------------------------------
        // TEST 5: Regression — PADD/PSUB/PMUL/PDOT unaffected by acc port
        // acc is set to a non-zero sentinel; these ops must ignore it.
        // ----------------------------------------------------------------
        $display("\n--- Test 5: Regression (existing ops ignore acc) ---");
        a = 32'h04030201; b = 32'h01020304;
        acc = 32'hDEADBEEF;  // large sentinel — must not appear in results

        funct3 = 3'b000; funct7 = 7'b0000000; #10;  // PADD
        check("PADD (acc ignored)", result, 32'h05050505);

        funct3 = 3'b000; funct7 = 7'b0100000; #10;  // PSUB
        // {4-1,3-2,2-3,1-4} = {3,1,0xFF,0xFD} (8-bit wrap for negatives)
        check("PSUB (acc ignored)", result, 32'h0301FFFD);

        funct3 = 3'b001; funct7 = 7'b0000000; #10;  // PMUL
        // a*b per lane: 1*4=4, 2*3=6, 3*2=6, 4*1=4 → {4,6,6,4} = 0x04060604
        check("PMUL (acc ignored)", result, 32'h04060604);

        funct3 = 3'b010; funct7 = 7'b0000000; #10;  // PDOT
        // 1*4 + 2*3 + 3*2 + 4*1 = 4+6+6+4 = 20
        check("PDOT (acc ignored)", result, 32'd20);

        // PSRA shamt=1 with acc sentinel (acc must not appear in result)
        // a=0x04030201 (all positive), >>1: {2,1,1,0} = 0x02010100
        a = 32'h04030201;
        funct3 = 3'b100; funct7 = 7'b0010001; #10;  // PSRA shamt=1
        check("PSRA (acc ignored)", result, 32'h02010100);

        // PRELU with acc sentinel
        // a=0x04030201 (all non-negative): passes through unchanged
        a = 32'h04030201;
        funct3 = 3'b101; funct7 = 7'b0100000; #10;  // PRELU
        check("PRELU (acc ignored)", result, 32'h04030201);

        // ----------------------------------------------------------------
        // SUMMARY
        // ----------------------------------------------------------------
        $display("\n========== RESULTS: %0d passed, %0d failed ==========",
                 pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $display("FAIL: %0d checks failed", fail_cnt);
        $finish;
    end

endmodule
