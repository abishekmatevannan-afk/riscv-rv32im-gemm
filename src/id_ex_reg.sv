// Pipeline register between ID and EX stages
// Carries decoded control signals and register values
// Clears to safe defaults (NOP-like) on flush or stall

module id_ex_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        stall,

    // PC
    input  logic [31:0] id_pc,
    output logic [31:0] ex_pc,

    // control signals
    input  logic        id_reg_we,
    input  logic        id_mem_we,
    input  logic        id_mem_re,
    input  logic        id_alu_src,
    input  logic [1:0]  id_wb_sel,
    input  logic        id_branch,
    input  logic        id_jump,
    input  logic [3:0]  id_alu_ctrl,
    input  logic [2:0]  id_funct3,
 
    output logic        ex_reg_we,
    output logic        ex_mem_we,
    output logic        ex_mem_re,
    output logic        ex_alu_src,
    output logic [1:0]  ex_wb_sel,
    output logic        ex_branch,
    output logic        ex_jump,
    output logic [3:0]  ex_alu_ctrl,
    output logic [2:0]  ex_funct3,
 
    // register data and addresses
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    input  logic [4:0]  id_rs1_addr,
    input  logic [4:0]  id_rs2_addr,
    input  logic [4:0]  id_rd_addr,
    input  logic [31:0] id_imm,
    input  logic [6:0]  id_opcode,
 
    output logic [31:0] ex_rs1_data,
    output logic [31:0] ex_rs2_data,
    output logic [4:0]  ex_rs1_addr,
    output logic [4:0]  ex_rs2_addr,
    output logic [4:0]  ex_rd_addr,
    output logic [31:0] ex_imm,
    output logic [6:0]  ex_opcode,
 
    // SIMD
    input  logic [6:0]  id_funct7,
    output logic [6:0]  ex_funct7,
 
    // branch predictor
    input  logic        id_predict_taken,
    input  logic [31:0] id_predict_target,
    output logic        ex_predict_taken,
    output logic [31:0] ex_predict_target,
 
    // exception signals
    input  logic        id_valid,
    output logic        ex_valid,
    input  logic        id_illegal,
    output logic        ex_illegal,
    input  logic        id_ecall,
    output logic        ex_ecall,
    input  logic        id_mret,
    output logic        ex_mret,
 
    // CSR signals
    input  logic        id_csr_we,
    output logic        ex_csr_we,
    input  logic [11:0] id_csr_addr,
    output logic [11:0] ex_csr_addr,
    input  logic [2:0]  id_csr_funct3,
    output logic [2:0]  ex_csr_funct3
);

   always_ff @(posedge clk) begin
        if (rst || flush) begin
            ex_pc            <= 32'd0;
            ex_reg_we        <= 0;
            ex_mem_we        <= 0;
            ex_mem_re        <= 0;
            ex_alu_src       <= 0;
            ex_wb_sel        <= 2'b00;
            ex_branch        <= 0;
            ex_jump          <= 0;
            ex_alu_ctrl      <= 4'b0000;
            ex_funct3        <= 3'b000;
            ex_predict_taken  <= 0;
            ex_predict_target <= 32'd0;
            ex_rs1_data      <= 32'd0;
            ex_rs2_data      <= 32'd0;
            ex_rs1_addr      <= 5'd0;
            ex_rs2_addr      <= 5'd0;
            ex_rd_addr       <= 5'd0;
            ex_imm           <= 32'd0;
            ex_opcode        <= 7'd0;
            ex_funct7        <= 7'd0;
            ex_valid         <= 0;
            ex_illegal       <= 0;
            ex_ecall         <= 0;
            ex_mret          <= 0;
            ex_csr_we        <= 0;
            ex_csr_addr      <= 12'd0;
            ex_csr_funct3    <= 3'd0;
        end else if (!stall) begin
            ex_pc            <= id_pc;
            ex_reg_we        <= id_reg_we;
            ex_mem_we        <= id_mem_we;
            ex_mem_re        <= id_mem_re;
            ex_alu_src       <= id_alu_src;
            ex_wb_sel        <= id_wb_sel;
            ex_branch        <= id_branch;
            ex_jump          <= id_jump;
            ex_alu_ctrl      <= id_alu_ctrl;
            ex_funct3        <= id_funct3;
            ex_predict_taken  <= id_predict_taken;
            ex_predict_target <= id_predict_target;
            ex_rs1_data      <= id_rs1_data;
            ex_rs2_data      <= id_rs2_data;
            ex_rs1_addr      <= id_rs1_addr;
            ex_rs2_addr      <= id_rs2_addr;
            ex_rd_addr       <= id_rd_addr;
            ex_imm           <= id_imm;
            ex_opcode        <= id_opcode;
            ex_funct7        <= id_funct7;
            ex_valid         <= id_valid;
            ex_illegal       <= id_illegal;
            ex_ecall         <= id_ecall;
            ex_mret          <= id_mret;
            ex_csr_we        <= id_csr_we;
            ex_csr_addr      <= id_csr_addr;
            ex_csr_funct3    <= id_csr_funct3;
        end
        // stall: hold all current values
    end
 
endmodule