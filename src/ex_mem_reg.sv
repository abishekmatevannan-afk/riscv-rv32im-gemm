// Pipeline register between EX and MEM stages

module ex_mem_reg (
    input  logic        clk,
    input  logic        rst,

    // control signals
    input  logic        ex_reg_we,
    input  logic        ex_mem_we,
    input  logic        ex_mem_re,
    input  logic [1:0]  ex_wb_sel,
    input  logic [2:0]  ex_funct3,

    output logic        mem_reg_we,
    output logic        mem_mem_we,
    output logic        mem_mem_re,
    output logic [1:0]  mem_wb_sel,
    output logic [2:0]  mem_funct3,

    // data
    input  logic [31:0] ex_alu_result,
    input  logic        ex_alu_zero,
    input  logic [31:0] ex_rs2_data,
    input  logic [4:0]  ex_rd_addr,
    input  logic [31:0] ex_pc_plus4,

    output logic [31:0] mem_alu_result,
    output logic        mem_alu_zero,
    output logic [31:0] mem_rs2_data,
    output logic [4:0]  mem_rd_addr,
    output logic [31:0] mem_pc_plus4
);

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_reg_we     <= 0;
            mem_mem_we     <= 0;
            mem_mem_re     <= 0;
            mem_wb_sel     <= 2'b00;
            mem_funct3     <= 3'b000;
            mem_alu_result <= 32'd0;
            mem_alu_zero   <= 0;
            mem_rs2_data   <= 32'd0;
            mem_rd_addr    <= 5'd0;
            mem_pc_plus4   <= 32'd0;
        end else begin
            mem_reg_we     <= ex_reg_we;
            mem_mem_we     <= ex_mem_we;
            mem_mem_re     <= ex_mem_re;
            mem_wb_sel     <= ex_wb_sel;
            mem_funct3     <= ex_funct3;
            mem_alu_result <= ex_alu_result;
            mem_alu_zero   <= ex_alu_zero;
            mem_rs2_data   <= ex_rs2_data;
            mem_rd_addr    <= ex_rd_addr;
            mem_pc_plus4   <= ex_pc_plus4;
        end
    end

endmodule