`timescale 1ns/1ps

module tb_forward_unit;

    logic [4:0] ex_rs1_addr, ex_rs2_addr;
    logic [4:0] mem_rd_addr, wb_rd_addr;
    logic       mem_reg_we, wb_reg_we;
    logic [1:0] forward_a, forward_b;

    forward_unit dut (
        .ex_rs1_addr (ex_rs1_addr),
        .ex_rs2_addr (ex_rs2_addr),
        .mem_rd_addr (mem_rd_addr),
        .mem_reg_we  (mem_reg_we),
        .wb_rd_addr  (wb_rd_addr),
        .wb_reg_we   (wb_reg_we),
        .forward_a   (forward_a),
        .forward_b   (forward_b)
    );

    task automatic check(
        input [4:0] rs1, rs2, mem_rd, wb_rd,
        input       mem_we, wb_we,
        input [1:0] exp_a, exp_b,
        input string name
    );
        ex_rs1_addr = rs1;
        ex_rs2_addr = rs2;
        mem_rd_addr = mem_rd;
        wb_rd_addr  = wb_rd;
        mem_reg_we  = mem_we;
        wb_reg_we   = wb_we;
        #10;
        if (forward_a !== exp_a || forward_b !== exp_b)
            $display("FAIL: %s | fwd_a exp=%b got=%b | fwd_b exp=%b got=%b",
                     name, exp_a, forward_a, exp_b, forward_b);
        else
            $display("PASS: %s | fwd_a=%b fwd_b=%b", name, forward_a, forward_b);
    endtask

    initial begin
        $display("========== FORWARD UNIT TESTBENCH ==========");

        // no hazard
        check(5'd1, 5'd2, 5'd3, 5'd4, 1, 1, 2'b00, 2'b00,
              "no hazard");

        // EX/MEM forward on A
        check(5'd1, 5'd2, 5'd1, 5'd4, 1, 1, 2'b10, 2'b00,
              "EX/MEM forward A");

        // EX/MEM forward on B
        check(5'd1, 5'd2, 5'd2, 5'd4, 1, 1, 2'b00, 2'b10,
              "EX/MEM forward B");

        // MEM/WB forward on A
        check(5'd1, 5'd2, 5'd5, 5'd1, 1, 1, 2'b01, 2'b00,
              "MEM/WB forward A");

        // MEM/WB forward on B
        check(5'd1, 5'd2, 5'd5, 5'd2, 1, 1, 2'b00, 2'b01,
              "MEM/WB forward B");

        // EX/MEM takes priority over MEM/WB on A
        check(5'd1, 5'd2, 5'd1, 5'd1, 1, 1, 2'b10, 2'b00,
              "EX/MEM priority over MEM/WB A");

        // x0 never forwarded
        check(5'd0, 5'd0, 5'd0, 5'd0, 1, 1, 2'b00, 2'b00,
              "x0 never forwarded");

        // reg_we=0 means no forwarding
        check(5'd1, 5'd2, 5'd1, 5'd2, 0, 0, 2'b00, 2'b00,
              "reg_we=0 no forward");

        $display("========== DONE ==========");
        $finish;
    end

endmodule