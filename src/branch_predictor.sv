// 2-bit saturating counter branch predictor with Branch Target Buffer
// 64-entry Branch History Table indexed by PC[7:2]
// 64-entry Branch Target Buffer for storing predicted targets
// Predicts taken/not-taken and target address in IF stage
// Updated in EX stage when branch resolves

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

    // 64-entry BHT, each entry is a 2-bit saturating counter
    logic [1:0] bht [0:63];

    // 64-entry BTB, each entry stores a predicted target address
    logic [31:0] btb [0:63];
    logic        btb_valid [0:63];

    // index into BHT/BTB using PC[7:2]
    logic [5:0] if_index;
    logic [5:0] ex_index;

    assign if_index = if_pc[7:2];
    assign ex_index = ex_pc[7:2];

    // initialize all entries to weakly not taken (01)
    integer i;
    initial begin
        for (i = 0; i < 64; i++) begin
            bht[i] = 2'b01;
            btb[i] = 32'd0;
            btb_valid[i] = 0;
        end
    end

    // prediction: taken if counter >= 2 and BTB valid
    assign predict_taken = bht[if_index][1] && btb_valid[if_index];
    assign predict_target = btb[if_index];

    // update BHT and BTB in EX stage when branch resolves
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 64; i++) begin
                bht[i] <= 2'b01;
                btb[i] <= 32'd0;
                btb_valid[i] <= 0;
            end
        end else if (ex_branch) begin
            // Update BTB with actual target if branch was taken
            if (ex_actual_taken) begin
                btb[ex_index] <= ex_actual_target;
                btb_valid[ex_index] <= 1;
            end

            // Update BHT: increment toward strongly taken, saturate at 11
            if (ex_actual_taken) begin
                if (bht[ex_index] != 2'b11)
                    bht[ex_index] <= bht[ex_index] + 1;
            end else begin
                // decrement toward strongly not taken, saturate at 00
                if (bht[ex_index] != 2'b00)
                    bht[ex_index] <= bht[ex_index] - 1;
            end
        end
    end

endmodule