// Tests control unit output for representative instructions
// One instruction per opcode type

`timescale 1ns/1ps

module tb_control_unit;

    logic [31:0] instr;
    logic        reg_we, mem_we, mem_re;
    logic        alu_src, branch, jump;
    logic [1:0]  wb_sel;
    logic [3:0]  alu_ctrl;
    logic [2:0]  imm_sel;

    control_unit dut (
        .instr    (instr),
        .reg_we   (reg_we),
        .mem_we   (mem_we),
        .mem_re   (mem_re),
        .alu_src  (alu_src),
        .wb_sel   (wb_sel),
        .branch   (branch),
        .jump     (jump),
        .alu_ctrl (alu_ctrl),
        .imm_sel  (imm_sel)
    );

    initial begin
        $dumpfile("sim/control_unit.vcd");
        $dumpvars(0, tb_control_unit);
    end

    task automatic check_signals(
        input [31:0] instruction,
        input        exp_reg_we,
        input        exp_mem_we,
        input        exp_mem_re,
        input        exp_alu_src,
        input [1:0]  exp_wb_sel,
        input        exp_branch,
        input        exp_jump,
        input [3:0]  exp_alu_ctrl,
        input string test_name
    );
        instr = instruction;
        #10;

        if (reg_we   !== exp_reg_we   ||
            mem_we   !== exp_mem_we   ||
            mem_re   !== exp_mem_re   ||
            alu_src  !== exp_alu_src  ||
            wb_sel   !== exp_wb_sel   ||
            branch   !== exp_branch   ||
            jump     !== exp_jump     ||
            alu_ctrl !== exp_alu_ctrl) begin

            $display("FAIL: %s", test_name);
            $display("  reg_we  exp=%b got=%b", exp_reg_we,  reg_we);
            $display("  mem_we  exp=%b got=%b", exp_mem_we,  mem_we);
            $display("  mem_re  exp=%b got=%b", exp_mem_re,  mem_re);
            $display("  alu_src exp=%b got=%b", exp_alu_src, alu_src);
            $display("  wb_sel  exp=%b got=%b", exp_wb_sel,  wb_sel);
            $display("  branch  exp=%b got=%b", exp_branch,  branch);
            $display("  jump    exp=%b got=%b", exp_jump,    jump);
            $display("  alu_ctrl exp=%b got=%b", exp_alu_ctrl, alu_ctrl);
        end else begin
            $display("PASS: %s", test_name);
        end
    endtask

    initial begin
        $display("========== CONTROL UNIT TESTBENCH ==========");

        // ADD x1, x2, x3
        // opcode=0110011 funct3=000 funct7=0000000
        // binary: 0000000 00011 00010 000 00001 0110011
        check_signals(
            32'b0000000_00011_00010_000_00001_0110011,
            1,    // reg_we
            0,    // mem_we
            0,    // mem_re
            0,    // alu_src (use rs2)
            2'b00,// wb_sel (ALU result)
            0,    // branch
            0,    // jump
            4'b0000, // ALU_ADD
            "ADD"
        );

        // SUB x1, x2, x3
        // funct7=0100000
        check_signals(
            32'b0100000_00011_00010_000_00001_0110011,
            1, 0, 0, 0, 2'b00, 0, 0, 4'b0001,
            "SUB"
        );

        // ADDI x1, x2, 5
        // imm=000000000101 rs1=00010 funct3=000 rd=00001 opcode=0010011
        check_signals(
            32'b000000000101_00010_000_00001_0010011,
            1,    // reg_we
            0,    // mem_we
            0,    // mem_re
            1,    // alu_src (use immediate)
            2'b00,// wb_sel
            0,    // branch
            0,    // jump
            4'b0000, // ALU_ADD
            "ADDI"
        );

        // LW x1, 0(x2)
        // opcode=0000011 funct3=010
        check_signals(
            32'b000000000000_00010_010_00001_0000011,
            1,    // reg_we
            0,    // mem_we
            1,    // mem_re
            1,    // alu_src
            2'b01,// wb_sel (memory)
            0,    // branch
            0,    // jump
            4'b0000, // ALU_ADD (address calc)
            "LW"
        );

        // SW x1, 0(x2)
        // opcode=0100011 funct3=010
        check_signals(
            32'b0000000_00001_00010_010_00000_0100011,
            0,    // reg_we
            1,    // mem_we
            0,    // mem_re
            1,    // alu_src
            2'b00,// wb_sel (dont care)
            0,    // branch
            0,    // jump
            4'b0000, // ALU_ADD
            "SW"
        );

        // BEQ x1, x2, offset
        // opcode=1100011 funct3=000
        check_signals(
            32'b0000000_00010_00001_000_00000_1100011,
            0,    // reg_we
            0,    // mem_we
            0,    // mem_re
            0,    // alu_src
            2'b00,// wb_sel
            1,    // branch
            0,    // jump
            4'b0001, // ALU_SUB (check zero flag)
            "BEQ"
        );

        // JAL x1, offset
        // opcode=1101111
        check_signals(
            32'b00000000000000000000_00001_1101111,
            1,    // reg_we
            0,    // mem_we
            0,    // mem_re
            0,    // alu_src
            2'b10,// wb_sel (PC+4)
            0,    // branch
            1,    // jump
            4'b0000, // ALU_ADD
            "JAL"
        );

        // LUI x1, 0x12345
        // opcode=0110111
        check_signals(
            32'b00010010001101000101_00001_0110111,
            1,    // reg_we
            0,    // mem_we
            0,    // mem_re
            1,    // alu_src
            2'b00,// wb_sel
            0,    // branch
            0,    // jump
            4'b1010, // ALU_LUI
            "LUI"
        );

        $display("========== DONE ==========");
        $finish;
    end

endmodule