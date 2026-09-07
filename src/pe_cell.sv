// Single output-stationary PE from the 4×4 parallel MAC accelerator.
// Each cycle that en is asserted: acc += zero_extend(a) × zero_extend(b).
// The 4×4 grid in parallel_mac_sub.sv instantiates 16 of these in parallel
// via generate loops, one per C[i][j] output element.
//
// ASIC target: Sky130 130nm via OpenLane 2 (see asic/pe_cell/).

module pe_cell (
    input  logic        clk,
    input  logic        rst,
    input  logic        en,
    input  logic [7:0]  a,
    input  logic [7:0]  b,
    output logic [31:0] acc

);
    always_ff @(posedge clk) begin
        if (rst)
            acc <= 32'd0;
        else if (en)
            acc <= acc + ({24'd0, a} * {24'd0, b});
    end
endmodule
