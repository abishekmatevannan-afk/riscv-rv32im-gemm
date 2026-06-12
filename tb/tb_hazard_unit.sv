`timescale 1ns/1ps

module tb_hazard_unit;

    logic       ex_mem_re;
    logic [4:0] ex_rd_addr;
    logic [4:0] id_rs1_addr, id_rs2_addr;
    logic [4:0] id_rd_addr;
    logic       id_is_pmacc;
    logic       ex_branch, ex_jump_mispredict, branch_taken, ex_predict_taken;
    logic       pc_stall, if_id_stall;
    logic       if_id_flush, id_ex_flush;
    logic       id_ex_stall, ex_mem_stall, mem_wb_stall;
    logic       branch_mispredict;
    logic       cache_stall;
    logic       div_busy;
    logic       icache_stall;
    logic trap;
    logic ex_mret;

    hazard_unit dut (
        .ex_mem_re          (ex_mem_re),
        .ex_rd_addr         (ex_rd_addr),
        .id_rs1_addr        (id_rs1_addr),
        .id_rs2_addr        (id_rs2_addr),
        .id_rd_addr         (id_rd_addr),
        .id_is_pmacc        (id_is_pmacc),
        .ex_branch          (ex_branch),
        .ex_jump_mispredict (ex_jump_mispredict),
        .branch_taken       (branch_taken),
        .ex_predict_taken   (ex_predict_taken),
        .cache_stall        (cache_stall),
        .div_busy           (div_busy),
        .icache_stall       (icache_stall),
        .pc_stall           (pc_stall),
        .if_id_stall        (if_id_stall),
        .if_id_flush        (if_id_flush),
        .id_ex_flush        (id_ex_flush),
        .id_ex_stall        (id_ex_stall),
        .ex_mem_stall       (ex_mem_stall),
        .mem_wb_stall       (mem_wb_stall),
        .branch_mispredict  (branch_mispredict),
        .trap               (trap),
        .ex_mret            (ex_mret)
    );

    task automatic check(
        input       mem_re, branch, jump_mis, taken, cs,
        input [4:0] ex_rd, id_rs1, id_rs2,
        input       in_trap, in_ex_mret,
        input       exp_pc_stall, exp_if_id_stall,
        input       exp_if_id_flush, exp_id_ex_flush,
        input string name
    );
        ex_mem_re           = mem_re;
        ex_branch           = branch;
        ex_jump_mispredict  = jump_mis;
        branch_taken        = taken;
        ex_predict_taken    = 1'b0;
        cache_stall         = cs;
        div_busy            = 1'b0;
        icache_stall        = 1'b0;
        ex_rd_addr          = ex_rd;
        id_rs1_addr         = id_rs1;
        id_rs2_addr         = id_rs2;
        id_rd_addr          = 5'd0;   // non-PMACC: acc port unused
        id_is_pmacc         = 1'b0;
        trap                = in_trap;
        ex_mret             = in_ex_mret;

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

    // Test PMACC accumulator load-use hazard
    task automatic check_pmacc(
        input       mem_re,
        input [4:0] ex_rd, id_rs1, id_rs2, id_rd,
        input       is_pmacc,
        input       exp_stall,
        input string name
    );
        ex_mem_re          = mem_re;
        ex_rd_addr         = ex_rd;
        id_rs1_addr        = id_rs1;
        id_rs2_addr        = id_rs2;
        id_rd_addr         = id_rd;
        id_is_pmacc        = is_pmacc;
        ex_branch          = 0; ex_jump_mispredict = 0;
        branch_taken       = 0; ex_predict_taken   = 0;
        cache_stall        = 0; div_busy           = 0;
        icache_stall       = 0; trap               = 0; ex_mret = 0;

        #10;

        if (pc_stall !== exp_stall || if_id_stall !== exp_stall) begin
            $display("FAIL: %s (pc_stall=%b if_id_stall=%b exp=%b)", name, pc_stall, if_id_stall, exp_stall);
        end else
            $display("PASS: %s", name);
    endtask

    initial begin
        $display("========== HAZARD UNIT TESTBENCH ==========");

        // cs=0 for all normal tests
        check(0, 0, 0, 0, 0, 5'd1, 5'd2, 5'd3, 0, 0, 0, 0, 0, 0, "no hazard");
        check(1, 0, 0, 0, 0, 5'd1, 5'd1, 5'd2, 0, 0, 1, 1, 0, 1, "load-use rs1");
        check(1, 0, 0, 0, 0, 5'd1, 5'd2, 5'd1, 0, 0, 1, 1, 0, 1, "load-use rs2");
        check(1, 0, 0, 0, 0, 5'd1, 5'd2, 5'd3, 0, 0, 0, 0, 0, 0, "load no match");
        // x0 destination: lw x0 followed by x0-reader must NOT stall (x0 hardwired 0)
        check(1, 0, 0, 0, 0, 5'd0, 5'd0, 5'd0, 0, 0, 0, 0, 0, 0, "load-use x0 no stall");
        check(0, 1, 0, 1, 0, 5'd0, 5'd0, 5'd0, 0, 0, 0, 0, 1, 1, "branch taken");
        check(0, 1, 0, 0, 0, 5'd0, 5'd0, 5'd0, 0, 0, 0, 0, 0, 0, "branch not taken");
        // jump_mispredict=1: mispredicted jump flushes pipeline
        check(0, 0, 1, 0, 0, 5'd0, 5'd0, 5'd0, 0, 0, 0, 0, 1, 1, "jump mispredicted flush");
        // jump_mispredict=0: correctly predicted jump, no flush
        check(0, 0, 0, 0, 0, 5'd0, 5'd0, 5'd0, 0, 0, 0, 0, 0, 0, "jump correct predict no flush");
        check(1, 1, 0, 1, 0, 5'd1, 5'd1, 5'd2, 0, 0, 1, 1, 1, 1, "load-use + branch taken");

        // cache stall tests — flushes suppressed
        check(0, 1, 0, 1, 1, 5'd0, 5'd0, 5'd0, 0, 0, 1, 1, 0, 0, "branch taken + cache stall");
        check(0, 0, 1, 0, 1, 5'd0, 5'd0, 5'd0, 0, 0, 1, 1, 0, 0, "jump mispredict + cache stall");
        check(1, 0, 0, 0, 1, 5'd1, 5'd1, 5'd2, 0, 0, 1, 1, 0, 0, "load-use + cache stall");

        // PMACC accumulator load-use hazard
        // LW r1, 0(r2) in EX; PMACC r1, r3, r4 in ID — acc port (rd=r1) matches → stall
        check_pmacc(1, 5'd1, 5'd3, 5'd4, 5'd1, 1, 1, "pmacc acc load-use stall");
        // PMACC rd=r1 but EX rd=r2 — no match → no stall
        check_pmacc(1, 5'd2, 5'd3, 5'd4, 5'd1, 1, 0, "pmacc acc no match no stall");
        // LW r1, 0(r2) in EX; non-PMACC instruction with rd=r1 in ID → no stall (not pmacc)
        check_pmacc(1, 5'd1, 5'd3, 5'd4, 5'd1, 0, 0, "non-pmacc rd match no stall");
        // rs1/rs2 hazard still works even when id_is_pmacc=1
        check_pmacc(1, 5'd1, 5'd1, 5'd4, 5'd9, 1, 1, "pmacc rs1 hazard still detected");

        $display("========== DONE ==========");
        $finish;
    end

endmodule