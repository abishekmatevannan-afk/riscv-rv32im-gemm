`timescale 1ns/1ps

module tb_hazard_unit;

    logic       ex_mem_re;
    logic [4:0] ex_rd_addr;
    logic [4:0] id_rs1_addr, id_rs2_addr;
    logic       ex_branch, ex_jump, branch_taken, ex_predict_taken;
    logic       pc_stall, if_id_stall;
    logic       if_id_flush, id_ex_flush;
    logic       id_ex_stall, ex_mem_stall, mem_wb_stall;
    logic       branch_mispredict;
    logic       cache_stall;

    hazard_unit dut (
        .ex_mem_re        (ex_mem_re),
        .ex_rd_addr       (ex_rd_addr),
        .id_rs1_addr      (id_rs1_addr),
        .id_rs2_addr      (id_rs2_addr),
        .ex_branch        (ex_branch),
        .ex_jump          (ex_jump),
        .branch_taken     (branch_taken),
        .ex_predict_taken (ex_predict_taken),
        .cache_stall      (cache_stall),
        .pc_stall         (pc_stall),
        .if_id_stall      (if_id_stall),
        .if_id_flush      (if_id_flush),
        .id_ex_flush      (id_ex_flush),
        .id_ex_stall      (id_ex_stall),
        .ex_mem_stall     (ex_mem_stall),
        .mem_wb_stall     (mem_wb_stall),
        .branch_mispredict(branch_mispredict)
    );

    task automatic check(
        input       mem_re, branch, jump, taken, cs,
        input [4:0] ex_rd, id_rs1, id_rs2,
        input       exp_pc_stall, exp_if_id_stall,
        input       exp_if_id_flush, exp_id_ex_flush,
        input string name
    );
        ex_mem_re        = mem_re;
        ex_branch        = branch;
        ex_jump          = jump;
        branch_taken     = taken;
        ex_predict_taken = 1'b0;
        cache_stall  = cs;
        ex_rd_addr   = ex_rd;
        id_rs1_addr  = id_rs1;
        id_rs2_addr  = id_rs2;
        
        #10;

        if (pc_stall    !== exp_pc_stall    ||
            if_id_stall !== exp_if_id_stall ||
            if_id_flush !== exp_if_id_flush ||
            id_ex_flush !== exp_id_ex_flush) begin
            $display("FAIL: %s", name);
            $display("  pc_stall    exp=%b got=%b", exp_pc_stall,    pc_stall);
            $display("  if_id_stall exp=%b got=%b", exp_if_id_stall, if_id_stall);
            $display("  if_id_flush exp=%b got=%b", exp_if_id_flush, if_id_flush);
            $display("  id_ex_flush exp=%b got=%b", exp_id_ex_flush, id_ex_flush);
        end else
            $display("PASS: %s", name);
    endtask

    initial begin
        $display("========== HAZARD UNIT TESTBENCH ==========");

        // cs=0 for all normal tests
        check(0, 0, 0, 0, 0, 5'd1, 5'd2, 5'd3, 0, 0, 0, 0, "no hazard");
        check(1, 0, 0, 0, 0, 5'd1, 5'd1, 5'd2, 1, 1, 0, 1, "load-use rs1");
        check(1, 0, 0, 0, 0, 5'd1, 5'd2, 5'd1, 1, 1, 0, 1, "load-use rs2");
        check(1, 0, 0, 0, 0, 5'd1, 5'd2, 5'd3, 0, 0, 0, 0, "load no match");
        check(0, 1, 0, 1, 0, 5'd0, 5'd0, 5'd0, 0, 0, 1, 1, "branch taken");
        check(0, 1, 0, 0, 0, 5'd0, 5'd0, 5'd0, 0, 0, 0, 0, "branch not taken");
        check(0, 0, 1, 0, 0, 5'd0, 5'd0, 5'd0, 0, 0, 1, 1, "jump flush");
        check(1, 1, 0, 1, 0, 5'd1, 5'd1, 5'd2, 1, 1, 1, 1, "load-use + branch taken");

        // cache stall tests — flushes suppressed
        check(0, 1, 0, 1, 1, 5'd0, 5'd0, 5'd0, 1, 1, 0, 0, "branch taken + cache stall");
        check(0, 0, 1, 0, 1, 5'd0, 5'd0, 5'd0, 1, 1, 0, 0, "jump + cache stall");
        check(1, 0, 0, 0, 1, 5'd1, 5'd1, 5'd2, 1, 1, 0, 0, "load-use + cache stall");

        $display("========== DONE ==========");
        $finish;
    end

endmodule