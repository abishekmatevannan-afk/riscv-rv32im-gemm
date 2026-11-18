// RV32M multiply/divide unit
// Multiplier: 2 cycles in EX, one shared 33x33 signed multiply (DSP48).
//   - Arrival cycle (mul_wait=0): busy=1, operands captured into mul_a/b_reg
//   - Next cycle    (mul_wait=1): busy=0, product valid, EX/MEM captures it
//   Registering the operands takes the forwarding mux out of the multiply's
//   timing path; the cost is a 1-cycle stall per MUL.
// Divider:    32-cycle iterative restoring algorithm.
//   - RUNNING state (32 cycles): busy=1, pipeline stalled
//   - DONE state   (1+ cycles):  busy=0, result stable, pipeline captures result
//                                (held while freeze is high)
//   - IDLE state: ready for next instruction
//
// freeze: high while a D$ miss freezes EX. The MUL wait bit and the DONE state
// hold so they stay in step with the instruction in EX. It must never include
// this unit's own busy, or the pipeline would deadlock.
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
    input  logic        freeze,   // D$ miss is freezing EX: hold MUL/DIV state, don't advance
    output logic [31:0] result,
    output logic        busy      // stall: MUL arrival cycle, or divider arrival/RUNNING
);

    // ── Multiplier (registered operands, 1-cycle stall — FPGA infers DSP48) ──
    logic [32:0] mul_a_reg, mul_b_reg;   // 33-bit operands captured in the arrival cycle
    logic        mul_wait;               // 1 = product is valid this cycle

    // Signedness is chosen by the 33rd bit, picked BEFORE the register so the
    // DSP inputs come straight from flops (Vivado can pack them into the
    // DSP48's own A/B registers; no LUT between register and multiplier).
    //
    //   op      a's bit 32   b's bit 32
    //   MUL     0            0          (low 32 bits same for any signedness)
    //   MULH    a[31]        b[31]      signed x signed
    //   MULHSU  a[31]        0          signed x unsigned
    //   MULHU   0            0          unsigned x unsigned
    wire a_signed = (funct3[1:0] == 2'b01) || (funct3[1:0] == 2'b10);  // MULH, MULHSU
    wire b_signed = (funct3[1:0] == 2'b01);                            // MULH

    // mul_wait: 0 -> 1 when a MUL arrives, 1 -> 0 the next cycle, so a
    // back-to-back MUL sees 0 again and stalls for its own capture.
    // Everything holds while freeze is high (the MUL is frozen in EX too).
    always_ff @(posedge clk) begin
        if (rst) begin
            mul_a_reg <= 33'd0;
            mul_b_reg <= 33'd0;
            mul_wait  <= 1'b0;
        end else if (!freeze) begin
            if (start && !funct3[2] && !mul_wait) begin
                mul_a_reg <= {a_signed && a[31], a};
                mul_b_reg <= {b_signed && b[31], b};
                mul_wait  <= 1'b1;
            end else if (mul_wait) begin
                mul_wait  <= 1'b0;
            end
        end
    end

    // Single 33x33 signed multiplication replaces the old three products
    // (ss, su, uu). The low 64 bits contain the complete RV32M product.
    logic signed [65:0] mul_product;

    assign mul_product = $signed(mul_a_reg) * $signed(mul_b_reg);

    // Stall in the arrival cycle only. Combinational on purpose: if this
    // waited for mul_wait to rise, EX/MEM would capture a stale product
    // (the same bug the divider had, see below).
    wire mul_busy = start && !funct3[2] && !mul_wait;

    // ── Divider (sequential, restoring algorithm) ─────────────────────────
    typedef enum logic [1:0] { IDLE=2'b00, RUNNING=2'b01, DONE=2'b10 } state_t;
    state_t state;

    logic [4:0]  count;
    logic [31:0] op_a, op_b;
    logic [31:0] quotient;
    logic [32:0] remainder;
    logic        neg_q, neg_r;

    // Busy also covers the cycle a divide arrives in EX (state still IDLE).
    // Without that cycle the pipeline advanced immediately and EX/MEM captured
    // the previous division's quotient instead of waiting for this one.
    // mul_busy follows the same rule for the multiplier.
    assign busy = mul_busy || (state == RUNNING) || (state == IDLE && start && funct3[2]);

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
                    // Hold DONE while EX is frozen: EX/MEM hasn't captured the
                    // result yet. Dropping to IDLE here would restart the
                    // divide (32 more cycles) for the same instruction.
                    if (!freeze)
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
            3'b000:  result = mul_product[31:0];
            3'b001:  result = mul_product[63:32];
            3'b010:  result = mul_product[63:32];
            3'b011:  result = mul_product[63:32];
            3'b100:  result = q_out;
            3'b101:  result = quotient;
            3'b110:  result = r_out;
            3'b111:  result = remainder[31:0];
            default: result = 32'd0;
        endcase
    end

endmodule
