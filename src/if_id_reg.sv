// Pipeline register between IF and ID stages
// Latches instruction and PC on clock edge
// Clears to NOP on flush (branch taken)
// Freezes on stall (load-use hazard)

module if_id_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,      // clear to NOP on branch taken
    input  logic        stall,      // freeze contents on load-use hazard
    input  logic [31:0] if_pc,      // PC from fetch stage
    input  logic [31:0] if_instr,   // instruction from fetch stage
    output logic [31:0] id_pc,      // PC to decode stage
    output logic [31:0] id_instr    // instruction to decode stage
);

    // NOP = addi x0, x0, 0 = 0x00000013
    localparam NOP = 32'h00000013;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            id_pc    <= 32'd0;
            id_instr <= NOP;
        end else if (!stall) begin
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
        // if stall: hold current values (do nothing)
    end

endmodule