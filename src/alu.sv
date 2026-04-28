// RV32I ALU - supports all arithmetic/logic operations required by RV32I
// Operations defined by 4-bit control signal from control unit

module alu (
    input  logic [31:0] a,          // operand A (rs1)
    input  logic [31:0] b,          // operand B (rs2 or immediate)
    input  logic [3:0]  alu_ctrl,   // operation select
    output logic [31:0] result,     // computation result
    output logic        zero        // high when result == 0 (used for branches)
);

    // ALU operation encodings
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;  // shift left logical
    localparam ALU_SRL  = 4'b0110;  // shift right logical
    localparam ALU_SRA  = 4'b0111;  // shift right arithmetic
    localparam ALU_SLT  = 4'b1000;  // set less than (signed)
    localparam ALU_SLTU = 4'b1001;  // set less than (unsigned)
    localparam ALU_LUI  = 4'b1010;  // pass B through (for LUI instruction)

    always @* begin
        case (alu_ctrl)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_AND:  result = a & b;
            ALU_OR:   result = a | b;
            ALU_XOR:  result = a ^ b;
            ALU_SLL:  result = a << b[4:0];
            ALU_SRL:  result = a >> b[4:0];
            ALU_SRA:  result = $signed(a) >>> b[4:0];
            ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
            ALU_LUI:  result = b;
            default:  result = 32'd0;
        endcase

        zero = (result == 32'd0);
    end

endmodule