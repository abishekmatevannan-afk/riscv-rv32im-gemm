// Detects data hazards and selects forwarded values
// Generates 2-bit select signals for ALU input muxes
// forward_a/b encoding:
// 2'b00 = no forwarding, use register file output
// 2'b01 = forward from MEM/WB stage
// 2'b10 = forward from EX/MEM stage

module forward_unit (
    // register addresses in EX stage (current instruction)
    input  logic [4:0] ex_rs1_addr,
    input  logic [4:0] ex_rs2_addr,

    // destination register and write enable from EX/MEM stage
    input  logic [4:0] mem_rd_addr,
    input  logic       mem_reg_we,

    // destination register and write enable from MEM/WB stage
    input  logic [4:0] wb_rd_addr,
    input  logic       wb_reg_we,

    // forwarding select signals
    output logic [1:0] forward_a,   
    output logic [1:0] forward_b    
);

    always_comb begin
        // default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;

        // --- operand A forwarding ---

        // EX/MEM forward takes priority (more recent value)
        if (mem_reg_we &&
            mem_rd_addr != 5'd0 &&
            mem_rd_addr == ex_rs1_addr) begin
            forward_a = 2'b10;  // forward from EX/MEM

        // MEM/WB forward (only if EX/MEM isn't already forwarding)
        end else if (wb_reg_we &&
                     wb_rd_addr != 5'd0 &&
                     wb_rd_addr == ex_rs1_addr) begin
            forward_a = 2'b01;  // forward from MEM/WB
        end

        // --- operand B forwarding ---

        if (mem_reg_we &&
            mem_rd_addr != 5'd0 &&
            mem_rd_addr == ex_rs2_addr) begin
            forward_b = 2'b10;  // forward from EX/MEM

        end else if (wb_reg_we &&
                     wb_rd_addr != 5'd0 &&
                     wb_rd_addr == ex_rs2_addr) begin
            forward_b = 2'b01;  // forward from MEM/WB
        end
    end

endmodule