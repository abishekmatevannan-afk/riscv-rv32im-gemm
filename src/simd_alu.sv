// SIMD ALU for packed 4x8-bit operations
// Implements custom RISC-V instructions using opcode 0001011
//
// Operations:
// PADD  — packed 4x8-bit add (unsigned wrap)
// PSUB  — packed 4x8-bit subtract (unsigned wrap)
// PMUL  — packed 4x8-bit multiply (lower 8 bits)
// PDOT  — packed dot product (ML-relevant, unsigned lanes)
// PMACC — packed multiply-accumulate: rd = acc + PDOT(rs1, rs2)
// PSRA  — packed arithmetic right shift (signed lanes, shamt from funct7[3:0])
// PRELU — packed ReLU: max(0, lane) per signed byte lane
//
// Encoding (R-type format, opcode=0001011):
// funct7=0000000 funct3=000 → PADD
// funct7=0100000 funct3=000 → PSUB
// funct7=0000000 funct3=001 → PMUL
// funct7=0000000 funct3=010 → PDOT
// funct7=0000000 funct3=011 → PMACC  (rd is both source and destination)
// funct7=001SSSS funct3=100 → PSRA   rs2=unused, shamt=funct7[3:0] (0..15)
// funct7=0100000 funct3=101 → PRELU  rs2=x0 (unary)

module simd_alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] acc,        // PMACC accumulator (rd value, forwarded)
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,
    output logic [31:0] result,
    output logic        valid       // high when opcode is a known SIMD op
);

    // unpack bytes
    logic [7:0] a0, a1, a2, a3;
    logic [7:0] b0, b1, b2, b3;

    assign a0 = a[7:0];
    assign a1 = a[15:8];
    assign a2 = a[23:16];
    assign a3 = a[31:24];

    assign b0 = b[7:0];
    assign b1 = b[15:8];
    assign b2 = b[23:16];
    assign b3 = b[31:24];

    // intermediate multiply results (16-bit to avoid overflow)
    logic [15:0] mul0, mul1, mul2, mul3;

    assign mul0 = a0 * b0;
    assign mul1 = a1 * b1;
    assign mul2 = a2 * b2;
    assign mul3 = a3 * b3;

    // PADD result (packed add)
    logic [31:0] padd_result;
    assign padd_result = {
        a3 + b3,
        a2 + b2,
        a1 + b1,
        a0 + b0
    };

    // PSUB result (packed subtract)
    logic [31:0] psub_result;
    assign psub_result = {
        a3 - b3,
        a2 - b2,
        a1 - b1,
        a0 - b0
    };

    // PMUL result (packed multiply, keep lower 8 bits)
    logic [31:0] pmul_result;
    assign pmul_result = {
        mul3[7:0],
        mul2[7:0],
        mul1[7:0],
        mul0[7:0]
    };

    // PDOT result (dot product sum)
    logic [31:0] pdot_result;
    assign pdot_result = {16'd0, mul0} +
                         {16'd0, mul1} +
                         {16'd0, mul2} +
                         {16'd0, mul3};

    // PSRA: signed byte lanes arithmetic right-shifted by funct7[3:0]
    // shamt≥8 fills all bits with the sign bit (equivalent to shift by 7+)
    logic [3:0] psra_shamt;
    logic signed [7:0] sa0, sa1, sa2, sa3;
    logic [7:0] psra0, psra1, psra2, psra3;
    logic [31:0] psra_result;

    assign psra_shamt = funct7[3:0];
    assign sa0 = $signed(a0);
    assign sa1 = $signed(a1);
    assign sa2 = $signed(a2);
    assign sa3 = $signed(a3);

    assign psra0 = psra_shamt[3] ? {8{sa0[7]}} : 8'(sa0 >>> psra_shamt[2:0]);
    assign psra1 = psra_shamt[3] ? {8{sa1[7]}} : 8'(sa1 >>> psra_shamt[2:0]);
    assign psra2 = psra_shamt[3] ? {8{sa2[7]}} : 8'(sa2 >>> psra_shamt[2:0]);
    assign psra3 = psra_shamt[3] ? {8{sa3[7]}} : 8'(sa3 >>> psra_shamt[2:0]);

    assign psra_result = {psra3, psra2, psra1, psra0};

    // PRELU: max(0, lane) — negative signed bytes become 0, non-negative pass through
    logic [31:0] prelu_result;
    assign prelu_result = {
        a3[7] ? 8'h00 : a3,
        a2[7] ? 8'h00 : a2,
        a1[7] ? 8'h00 : a1,
        a0[7] ? 8'h00 : a0
    };

    // Main opcode decoder
    always_comb begin
        result = 32'd0;
        valid  = 1'b1;

        case (funct3)
            // PADD / PSUB — funct7 distinguishes them
            3'b000: begin
                if (funct7 == 7'b0000000) begin
                    result = padd_result;
                end else if (funct7 == 7'b0100000) begin
                    result = psub_result;
                end else begin
                    result = 32'd0;
                    valid  = 1'b0;
                end
            end

            // PMUL: packed multiply, keep lower 8 bits per lane
            3'b001: begin
                result = pmul_result;
            end

            // PDOT: dot product
            3'b010: begin
                result = pdot_result;
            end

            // PMACC: rd = acc + PDOT(rs1, rs2)  — acc is the forwarded rd value
            3'b011: begin
                result = acc + pdot_result;
            end

            // PSRA: packed arithmetic right shift, shamt in funct7[3:0]
            3'b100: begin
                result = psra_result;
            end

            // PRELU: packed ReLU, max(0, signed lane)
            3'b101: begin
                result = prelu_result;
            end

            default: begin
                result = 32'd0;
                valid  = 1'b0;
            end
        endcase
    end

endmodule