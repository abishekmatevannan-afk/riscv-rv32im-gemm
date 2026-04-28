// Testbench for RV32I ALU
// Tests all operations including edge cases

module tb_alu;

    // inputs driven by testbench
    logic [31:0] a, b;
    logic [3:0]  alu_ctrl;

    // outputs monitored by testbench
    logic [31:0] result;
    logic        zero;

    // instantiate the ALU
    alu dut (
        .a        (a),
        .b        (b),
        .alu_ctrl (alu_ctrl),
        .result   (result),
        .zero     (zero)
    );

    // waveform dump for GTKWave
    initial begin
        $dumpfile("sim/alu.vcd");
        $dumpvars(0, tb_alu);
    end

    // task to apply inputs and check output
    // makes tests readable and reusable
    task automatic check(
        input [31:0] in_a,
        input [31:0] in_b,
        input [3:0]  ctrl,
        input [31:0] expected,
        input string op_name
    );
        a = in_a;
        b = in_b;
        alu_ctrl = ctrl;
        #10; // wait for combinational logic to settle

        if (result !== expected) begin
            $display("FAIL: %s | a=0x%08h b=0x%08h | expected=0x%08h got=0x%08h",
                     op_name, in_a, in_b, expected, result);
        end else begin
            $display("PASS: %s | a=0x%08h b=0x%08h | result=0x%08h",
                     op_name, in_a, in_b, result);
        end
    endtask

    integer pass_count;
    integer fail_count;

    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("========== ALU TESTBENCH ==========");

        // ADD
        check(32'd15,        32'd10,        4'b0000, 32'd25,         "ADD basic");
        check(32'd0,         32'd0,         4'b0000, 32'd0,          "ADD zero");
        check(32'hFFFFFFFF,  32'd1,         4'b0000, 32'd0,          "ADD overflow");
        check(32'h7FFFFFFF,  32'd1,         4'b0000, 32'h80000000,   "ADD signed overflow");

        // SUB
        check(32'd20,        32'd10,        4'b0001, 32'd10,         "SUB basic");
        check(32'd0,         32'd1,         4'b0001, 32'hFFFFFFFF,   "SUB underflow");
        check(32'd5,         32'd5,         4'b0001, 32'd0,          "SUB to zero");

        // AND
        check(32'hFF00FF00,  32'h0F0F0F0F,  4'b0010, 32'h0F000F00,  "AND basic");
        check(32'hFFFFFFFF,  32'h00000000,  4'b0010, 32'h00000000,  "AND with zero");

        // OR
        check(32'hFF000000,  32'h00FF0000,  4'b0011, 32'hFFFF0000,  "OR basic");
        check(32'h00000000,  32'h00000000,  4'b0011, 32'h00000000,  "OR zeros");

        // XOR
        check(32'hFFFFFFFF,  32'hFFFFFFFF,  4'b0100, 32'h00000000,  "XOR same");
        check(32'hAAAAAAAA,  32'h55555555,  4'b0100, 32'hFFFFFFFF,  "XOR alternating");

        // SLL (shift left logical)
        check(32'd1,         32'd4,         4'b0101, 32'd16,         "SLL by 4");
        check(32'd1,         32'd31,        4'b0101, 32'h80000000,   "SLL by 31");
        check(32'hFFFFFFFF,  32'd1,         4'b0101, 32'hFFFFFFFE,   "SLL overflow");

        // SRL (shift right logical)
        check(32'h80000000,  32'd1,         4'b0110, 32'h40000000,   "SRL msb");
        check(32'hFFFFFFFF,  32'd4,         4'b0110, 32'h0FFFFFFF,   "SRL by 4");

        // SRA (shift right arithmetic - preserves sign)
        check(32'h80000000,  32'd1,         4'b0111, 32'hC0000000,   "SRA negative");
        check(32'h7FFFFFFF,  32'd1,         4'b0111, 32'h3FFFFFFF,   "SRA positive");

        // SLT (set less than signed)
        check(32'd5,         32'd10,        4'b1000, 32'd1,          "SLT true");
        check(32'd10,        32'd5,         4'b1000, 32'd0,          "SLT false");
        check(32'hFFFFFFFF,  32'd0,         4'b1000, 32'd1,          "SLT negative < 0");

        // SLTU (set less than unsigned)
        check(32'd5,         32'd10,        4'b1001, 32'd1,          "SLTU true");
        check(32'hFFFFFFFF,  32'd0,         4'b1001, 32'd0,          "SLTU large unsigned");

        // LUI passthrough
        check(32'd0,         32'hABCD1000,  4'b1010, 32'hABCD1000,  "LUI passthrough");

        // Zero flag
        a = 32'd5; b = 32'd5; alu_ctrl = 4'b0001; #10;
        if (zero !== 1'b1)
            $display("FAIL: zero flag not set on zero result");
        else
            $display("PASS: zero flag set correctly");

        a = 32'd5; b = 32'd3; alu_ctrl = 4'b0001; #10;
        if (zero !== 1'b0)
            $display("FAIL: zero flag incorrectly set on nonzero result");
        else
            $display("PASS: zero flag clear on nonzero result");

        $display("========== DONE ==========");
        $finish;
    end

endmodule