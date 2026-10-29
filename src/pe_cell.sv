// Single output-stationary PE, extracted from the 4×4 parallel MAC
// accelerator's compute loop (parallel_mac_sub.sv, which inlines the same
// multiply-add for all 16 C[i][j] elements rather than instantiating this
// module). Used standalone as the ASIC target.
//
// Two-stage pipeline: the 8×8 product is registered before the 32-bit
// accumulate, so the multiplier tree and the adder carry chain are no longer
// one combinational path. Each cycle that en is asserted contributes
// zero_extend(a) × zero_extend(b) to acc, visible one cycle later than in
// the single-cycle version.
//
// ASIC target: Sky130 130nm via LibreLane (see asic/pe_cell/).

module pe_cell (
    input  logic        clk,
    input  logic        rst,
    input  logic        en,
    input  logic [7:0]  a,
    input  logic [7:0]  b,
    output logic [31:0] acc

);
    logic [15:0] prod_q;
    logic        en_q;

    // Stage 1: multiply. prod_q loads every cycle with no reset or enable,
    // keeping the mux off the multiplier's D-input path; en_q qualifies it.
    always_ff @(posedge clk) begin
        if (rst)
            en_q <= 1'b0;
        else
            en_q <= en;
    end

    always_ff @(posedge clk) begin
        prod_q <= a * b;
    end

    // Stage 2: accumulate.
    always_ff @(posedge clk) begin
        if (rst)
            acc <= 32'd0;
        else if (en_q)
            acc <= acc + {16'd0, prod_q};
    end
endmodule
