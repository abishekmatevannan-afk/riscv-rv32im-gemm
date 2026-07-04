// 2-bit saturating counter branch predictor with Branch Target Buffer
// 64-entry Branch History Table indexed by PC[7:2]
// 64-entry Branch Target Buffer with tag bits to prevent aliasing
//
// Without tags, two PCs that share the same PC[7:2] index (e.g. 0x020 and
// 0x120) map to the same BTB entry. A trained loop branch at 0x020 could
// redirect a sequential fetch at 0x120 back into the loop body. Adding
// btb_tag stores PC[31:8] alongside the target — predictions are suppressed
// when the tag does not match the current PC.

module branch_predictor (
    input  logic        clk,
    input  logic        rst,

    // IF stage — prediction request
    input  logic [31:0] if_pc,          // current PC being fetched
    output logic        predict_taken,   // prediction for this PC
    output logic [31:0] predict_target,  // predicted target address

    // EX stage — update after branch resolves
    input  logic        ex_branch,       // is this a branch instruction
    input  logic [31:0] ex_pc,           // PC of the branch instruction
    input  logic        ex_actual_taken, // was the branch actually taken
    input  logic [31:0] ex_actual_target // actual target address
);

    // 64-entry BHT: 2-bit saturating counter per entry
    logic [1:0]  bht      [0:63];

    // 64-entry BTB: target address, valid flag, and tag
    // btb_tag stores PC[31:8] so aliased PCs (same index, different upper
    // bits) do not borrow each other's predictions
    (* ram_style = "distributed" *) logic [31:0] btb      [0:63];
                                    logic        btb_valid[0:63];
    (* ram_style = "distributed" *) logic [23:0] btb_tag  [0:63]; // PC[31:8] of the branch that filled this entry

    // index into tables using PC[7:2] (6 bits → 64 entries)
    logic [5:0] if_index;
    logic [5:0] ex_index;

    assign if_index = if_pc[7:2];
    assign ex_index = ex_pc[7:2];

    integer i;

    // prediction: taken only if counter >= 2, BTB valid, AND tag matches.
    // the tag check is what prevents aliasing — a PC that happens to share
    // the same 6-bit index as a trained branch gets predict_taken=0 unless
    // its upper bits also match the stored tag.
    assign predict_taken  = bht[if_index][1]
                         && btb_valid[if_index]
                         && (btb_tag[if_index] == if_pc[31:8]);
    assign predict_target = btb[if_index];

    // update BHT and BTB when branch resolves in EX stage
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 64; i++) begin
                bht[i]       <= 2'b01;
                btb_valid[i] <= 1'b0;
            end
        end else if (ex_branch) begin

            // on a taken branch: update target, valid flag, and tag
            if (ex_actual_taken) begin
                btb[ex_index]       <= ex_actual_target;
                btb_valid[ex_index] <= 1'b1;
                btb_tag[ex_index]   <= ex_pc[31:8];
            end

            // update BHT counter: saturate at 11 (taken) and 00 (not-taken)
            if (ex_actual_taken) begin
                if (bht[ex_index] != 2'b11)
                    bht[ex_index] <= bht[ex_index] + 1;
            end else begin
                if (bht[ex_index] != 2'b00)
                    bht[ex_index] <= bht[ex_index] - 1;
            end

        end
    end

endmodule