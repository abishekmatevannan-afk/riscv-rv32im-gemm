`timescale 1ns/1ps

module tb_branch_predictor;

    logic        clk, rst;
    logic [31:0] if_pc;
    logic        predict_taken;
    logic        ex_branch;
    logic [31:0] ex_pc;
    logic        ex_actual_taken;

    branch_predictor dut (
        .clk             (clk),
        .rst             (rst),
        .if_pc           (if_pc),
        .predict_taken   (predict_taken),
        .ex_branch       (ex_branch),
        .ex_pc           (ex_pc),
        .ex_actual_taken (ex_actual_taken)
    );

    initial begin
        $dumpfile("sim/branch_predictor.vcd");
        $dumpvars(0, tb_branch_predictor);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // simulate one branch resolution
    task automatic resolve_branch(
        input [31:0] pc,
        input        actual_taken
    );
        ex_branch       = 1;
        ex_pc           = pc;
        ex_actual_taken = actual_taken;
        @(posedge clk); #1;
        ex_branch       = 0;
    endtask

    integer correct, total;
    logic pred;

    initial begin
        $display("========== BRANCH PREDICTOR TESTBENCH ==========");

        rst = 1; ex_branch = 0; if_pc = 0;
        ex_pc = 0; ex_actual_taken = 0;
        repeat(3) @(posedge clk); #1;
        rst = 0;

        correct = 0;
        total   = 0;

        // test 1: initial prediction should be weakly not taken
        if_pc = 32'h00000020;
        #10;
        if (predict_taken !== 0)
            $display("FAIL: initial prediction should be not taken");
        else
            $display("PASS: initial prediction = not taken");

        // test 2: train a branch to be taken
        // weakly not taken -> weakly taken -> strongly taken
        // needs 2 taken updates to flip prediction
        $display("\n--- Training branch at PC=0x20 to be taken ---");

        if_pc = 32'h00000020;
        #1;
        $display("Before training: predict_taken=%b", predict_taken);

        resolve_branch(32'h00000020, 1); // 01 -> 10 (now predicts taken)
        #1;
        if_pc = 32'h00000020; #1;
        $display("After 1 taken:   predict_taken=%b (expect 1)", predict_taken);
        if (predict_taken) correct = correct + 1;
        total = total + 1;

        resolve_branch(32'h00000020, 1); // 10 -> 11
        #1;
        if_pc = 32'h00000020; #1;
        $display("After 2 taken:   predict_taken=%b (expect 1)", predict_taken);
        if (predict_taken) correct = correct + 1;
        total = total + 1;

        // test 3: saturation at 11
        resolve_branch(32'h00000020, 1); // should stay 11
        resolve_branch(32'h00000020, 1);
        #1;
        if_pc = 32'h00000020; #1;
        if (predict_taken !== 1)
            $display("FAIL: should saturate at strongly taken");
        else
            $display("PASS: saturates at strongly taken");

        // test 4: one not-taken shouldn't flip prediction (hysteresis)
        resolve_branch(32'h00000020, 0); // 11 -> 10 still predicts taken
        #1;
        if_pc = 32'h00000020; #1;
        if (predict_taken !== 1)
            $display("FAIL: one misprediction should not flip from strongly taken");
        else
            $display("PASS: hysteresis works, still predicts taken after one not-taken");

        // test 5: simulate a loop — taken 9 times, not taken once
        $display("\n--- Simulating loop: 9 taken, 1 not taken ---");
        correct = 0; total = 0;

        // reset this entry by forcing not taken twice
        resolve_branch(32'h00000040, 0);
        resolve_branch(32'h00000040, 0);

        // now simulate loop iterations
        begin
            integer j;
            for (j = 0; j < 10; j++) begin
                // get prediction before resolving
                if_pc = 32'h00000040; #1;
                pred = predict_taken;

                // actual: taken for first 9, not taken on last
                if (j < 9) begin
                    resolve_branch(32'h00000040, 1);
                    if (pred == 1) correct = correct + 1;
                end else begin
                    resolve_branch(32'h00000040, 0);
                    if (pred == 0) correct = correct + 1;
                end
                total = total + 1;
            end
        end

        $display("Loop prediction accuracy: %0d/%0d", correct, total);
        if (correct >= 7) // allow for 1-2 mispredictions during training phase
            $display("PASS: good loop prediction accuracy");
        else
            $display("FAIL: poor loop prediction accuracy");

        // test 6: different PCs map to different BHT entries
        $display("\n--- Testing independent BHT entries ---");
        resolve_branch(32'h00000020, 1); // train PC=0x20 taken
        resolve_branch(32'h00000020, 1);

        if_pc = 32'h00000020; #1;
        $display("PC=0x20 predict_taken=%b (expect 1)", predict_taken);

        if_pc = 32'h00000060; #1; // different PC, different entry
        $display("PC=0x60 predict_taken=%b (expect 0)", predict_taken);

        if (predict_taken === 0)
            $display("PASS: independent BHT entries");
        else
            $display("FAIL: BHT entries not independent");

        // test 7: BTB tag mismatch prevents aliased prediction
        // PC_A=0x080 and PC_B=0x180 share index PC[7:2]=6'b100000 (index 32)
        // but have different PC[31:8] tags (0x000000 vs 0x000001).
        // After training PC_A strongly taken, PC_B must still predict not-taken
        // because the stored BTB tag (PC_A[31:8]=0) != PC_B[31:8]=1.
        $display("\n--- Test 7: BTB tag prevents cross-PC aliasing ---");
        // train PC_A = 0x080 to strongly taken
        resolve_branch(32'h00000080, 1);
        resolve_branch(32'h00000080, 1);
        // verify PC_A predicts taken
        if_pc = 32'h00000080; #1;
        if (predict_taken !== 1)
            $display("FAIL: PC_A should predict taken after training");
        else
            $display("PASS: PC_A = 0x080 predicts taken after training");
        // PC_B shares the same index but different tag — must not alias
        if_pc = 32'h00000180; #1;
        if (predict_taken !== 0)
            $display("FAIL: PC_B aliased to PC_A's BTB entry (tag check failed)");
        else
            $display("PASS: PC_B = 0x180 not aliased — tag mismatch correctly suppresses prediction");

        // test 8: BTB eviction — training PC_B overwrites PC_A's tag at the shared index
        $display("\n--- Test 8: BTB eviction on tag change ---");
        // train PC_B (same index 32, tag=0x000001) as taken → evicts PC_A's entry
        resolve_branch(32'h00000180, 1);
        resolve_branch(32'h00000180, 1);
        // PC_B now predicts taken (its tag is now stored)
        if_pc = 32'h00000180; #1;
        if (predict_taken !== 1)
            $display("FAIL: PC_B should predict taken after training");
        else
            $display("PASS: PC_B = 0x180 predicts taken after training");
        // PC_A's tag has been evicted — must now predict not-taken
        if_pc = 32'h00000080; #1;
        if (predict_taken !== 0)
            $display("FAIL: PC_A should predict not-taken after BTB eviction");
        else
            $display("PASS: PC_A = 0x080 correctly predicts not-taken after eviction by PC_B");

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule