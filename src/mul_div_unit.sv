// RV32M multiply/divide unit
// Multiplier: single-cycle, combinational.  FPGA tools infer DSP48 blocks.
// Divider:    32-cycle iterative restoring algorithm.
//   - RUNNING state (32 cycles): busy=1, pipeline stalled
//   - DONE state   (1 cycle):    busy=0, result stable, pipeline captures result
//   - IDLE state: ready for next instruction
//
// funct3 encoding (RV32M spec):
//   3'b000  MUL    lower 32 bits of signed × signed
//   3'b001  MULH   upper 32 bits of signed × signed
//   3'b010  MULHSU upper 32 bits of signed × unsigned
//   3'b011  MULHU  upper 32 bits of unsigned × unsigned
//   3'b100  DIV    signed quotient
//   3'b101  DIVU   unsigned quotient
//   3'b110  REM    signed remainder
//   3'b111  REMU   unsigned remainder
//
// RISC-V spec corner cases:
//   Divide by zero:              quotient = 0xFFFFFFFF, remainder = dividend
//   Signed overflow (INT_MIN/-1): quotient = INT_MIN,   remainder = 0

module mul_div_unit (
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [2:0]  funct3,

    input  logic        start,    // held high while a muldiv instruction is in EX
    output logic [31:0] result,
    output logic        busy      // high while divider runs; multiplier never stalls
);

    // ── Multiplier (combinational — FPGA infers DSP48) ───────────────────
    logic [63:0] prod_ss;
    logic [63:0] prod_su;
    logic [63:0] prod_uu;

    assign prod_ss = $signed(a) * $signed(b);
    assign prod_su = $signed(a) * b;
    assign prod_uu = a * b;

    // ── Divider (sequential, restoring algorithm) ─────────────────────────
    typedef enum logic [1:0] { IDLE=2'b00, RUNNING=2'b01, DONE=2'b10 } state_t;
    state_t state;

    logic [4:0]  count;
    logic [31:0] op_a, op_b;
    logic [31:0] quotient;
    logic [32:0] remainder;
    logic        neg_q, neg_r;

    assign busy = (state == RUNNING);

    // One restoring-divider step: shift remainder left, try to subtract divisor
    wire [32:0] r_shifted = {remainder[31:0], op_a[31 - count]};
    wire [32:0] r_sub     = r_shifted - {1'b0, op_b};

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            count     <= 5'd0;
            quotient  <= 32'd0;
            remainder <= 33'd0;
            op_a      <= 32'd0;
            op_b      <= 32'd0;
            neg_q     <= 1'b0;
            neg_r     <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    if (start && funct3[2]) begin
                        case (funct3)
                            3'b100, 3'b110: begin  // DIV / REM (signed)
                                if (b == 32'd0) begin
                                    quotient  <= 32'hFFFF_FFFF;
                                    remainder <= {1'b0, a};
                                    neg_q     <= 1'b0;
                                    neg_r     <= 1'b0;
                                    state     <= DONE;
                                end else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) begin
                                    quotient  <= 32'h8000_0000;
                                    remainder <= 33'd0;
                                    neg_q     <= 1'b0;
                                    neg_r     <= 1'b0;
                                    state     <= DONE;
                                end else begin
                                    op_a      <= a[31] ? (~a + 1) : a;
                                    op_b      <= b[31] ? (~b + 1) : b;
                                    neg_q     <= a[31] ^ b[31];
                                    neg_r     <= a[31];
                                    quotient  <= 32'd0;
                                    remainder <= 33'd0;
                                    count     <= 5'd0;
                                    state     <= RUNNING;
                                end
                            end
                            default: begin  // DIVU / REMU (unsigned)
                                if (b == 32'd0) begin
                                    quotient  <= 32'hFFFF_FFFF;
                                    remainder <= {1'b0, a};
                                    neg_q     <= 1'b0;
                                    neg_r     <= 1'b0;
                                    state     <= DONE;
                                end else begin
                                    op_a      <= a;
                                    op_b      <= b;
                                    neg_q     <= 1'b0;
                                    neg_r     <= 1'b0;
                                    quotient  <= 32'd0;
                                    remainder <= 33'd0;
                                    count     <= 5'd0;
                                    state     <= RUNNING;
                                end
                            end
                        endcase
                    end
                end

                RUNNING: begin
                    if (r_sub[32]) begin             // subtract underflowed → restore
                        remainder          <= r_shifted;
                        quotient[31-count] <= 1'b0;
                    end else begin
                        remainder          <= r_sub;
                        quotient[31-count] <= 1'b1;
                    end
                    count <= count + 5'd1;
                    if (count == 5'd31) state <= DONE;
                end

                DONE: begin
                    state <= IDLE;
                end

            endcase
        end
    end

    // ── Result mux ────────────────────────────────────────────────────────
    // Sign correction is combinational so the result is valid in DONE state,
    // the cycle when the pipeline captures EX/MEM.
    wire [31:0] q_out = neg_q ? (~quotient + 1) : quotient;
    wire [31:0] r_out = neg_r ? (~remainder[31:0] + 1) : remainder[31:0];

    always_comb begin
        case (funct3)
            3'b000:  result = prod_ss[31:0];
            3'b001:  result = prod_ss[63:32];
            3'b010:  result = prod_su[63:32];
            3'b011:  result = prod_uu[63:32];
            3'b100:  result = q_out;
            3'b101:  result = quotient;
            3'b110:  result = r_out;
            3'b111:  result = remainder[31:0];
            default: result = 32'd0;
        endcase
    end

endmodule
