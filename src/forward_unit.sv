// Detects data hazards and selects forwarded values
// Generates 2-bit select signals for ALU input muxes
// forward_a/b/acc encoding:
// 2'b00 = no forwarding, use register file output
// 2'b01 = forward from MEM/WB stage
// 2'b10 = forward from EX/MEM stage

module forward_unit (
    // register addresses in EX stage (current instruction)
    input  logic [4:0] ex_rs1_addr,
    input  logic [4:0] ex_rs2_addr,
    input  logic [4:0] ex_rd_addr,    // PMACC accumulator address (rd is both src and dst)
    input  logic       ex_is_pmacc,   // high when EX instruction is PMACC

    // destination register and write enable from EX/MEM stage
    input  logic [4:0] mem_rd_addr,
    input  logic       mem_reg_we,

    // destination register and write enable from MEM/WB stage
    input  logic [4:0] wb_rd_addr,
    input  logic       wb_reg_we,

    // forwarding select signals
    output logic [1:0] forward_a,
    output logic [1:0] forward_b,
    output logic [1:0] forward_acc   // PMACC accumulator forwarding (only fires when ex_is_pmacc)
);

    always_comb begin
        // default: no forwarding
        forward_a   = 2'b00;
        forward_b   = 2'b00;
        forward_acc = 2'b00;

        // --- operand A forwarding ---

        // EX/MEM forward takes priority (more recent value)
        if (mem_reg_we &&
            mem_rd_addr != 5'd0 &&
            mem_rd_addr == ex_rs1_addr) begin
            forward_a = 2'b10;

        // MEM/WB forward (only if EX/MEM isn't already forwarding)
        end else if (wb_reg_we &&
                     wb_rd_addr != 5'd0 &&
                     wb_rd_addr == ex_rs1_addr) begin
            forward_a = 2'b01;
        end

        // --- operand B forwarding ---

        if (mem_reg_we &&
            mem_rd_addr != 5'd0 &&
            mem_rd_addr == ex_rs2_addr) begin
            forward_b = 2'b10;

        end else if (wb_reg_we &&
                     wb_rd_addr != 5'd0 &&
                     wb_rd_addr == ex_rs2_addr) begin
            forward_b = 2'b01;
        end

        // --- PMACC accumulator forwarding ---
        // Only fire when the current EX instruction IS PMACC.
        // This prevents a non-PMACC instruction that happens to write the same rd
        // from injecting a stale value into the acc path.
        if (ex_is_pmacc) begin
            if (mem_reg_we &&
                mem_rd_addr != 5'd0 &&
                mem_rd_addr == ex_rd_addr) begin
                forward_acc = 2'b10;  // EX/MEM forward takes priority

            end else if (wb_reg_we &&
                         wb_rd_addr != 5'd0 &&
                         wb_rd_addr == ex_rd_addr) begin
                forward_acc = 2'b01;
            end
        end
    end

    // SVA: forwarding mux encodings — 2'b11 is undefined and must never appear
    always_comb begin
        assert (forward_a !== 2'b11) else $error("SVA FAIL: forward_a=2'b11 (undefined mux select)");
        assert (forward_b !== 2'b11) else $error("SVA FAIL: forward_b=2'b11 (undefined mux select)");
    end

endmodule
