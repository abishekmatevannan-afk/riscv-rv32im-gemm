// Holds current instruction address
// Increments by 4 each cycle (word-aligned)
// Supports branch/jump by loading arbitrary next address

module program_counter (
    input  logic        clk,
    input  logic        rst,         // synchronous reset
    input  logic        stall,       // stall PC on hazards/misses
    input  logic        pc_we,       // write enable (for branch/jump target)
    input  logic [31:0] pc_next,     // next PC value (branch/jump or sequential)
    output logic [31:0] pc           // current PC value
);

    always_ff @(posedge clk) begin
        if (rst)
            pc <= 32'd0;             // reset to address 0
        else if (stall)
            pc <= pc;                // hold PC during stall
        else if (pc_we)
            pc <= pc_next;           // branch/jump or explicit next update
        else
            pc <= pc + 32'd4;        // default sequential increment
    end

endmodule