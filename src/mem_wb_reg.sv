// Pipeline register between MEM and WB stages

module mem_wb_reg (
    input  logic        clk,
    input  logic        rst,

    // control signals
    input  logic        mem_reg_we,
    input  logic [1:0]  mem_wb_sel,
    input  logic [4:0]  mem_rd_addr,

    output logic        wb_reg_we,
    output logic [1:0]  wb_wb_sel,
    output logic [4:0]  wb_rd_addr,

    // data
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_read_data,
    input  logic [31:0] mem_pc_plus4,

    output logic [31:0] wb_alu_result,
    output logic [31:0] wb_read_data,
    output logic [31:0] wb_pc_plus4
);

    always_ff @(posedge clk) begin
        if (rst) begin
            wb_reg_we     <= 0;
            wb_wb_sel     <= 2'b00;
            wb_rd_addr    <= 5'd0;
            wb_alu_result <= 32'd0;
            wb_read_data  <= 32'd0;
            wb_pc_plus4   <= 32'd0;
        end else begin
            wb_reg_we     <= mem_reg_we;
            wb_wb_sel     <= mem_wb_sel;
            wb_rd_addr    <= mem_rd_addr;
            wb_alu_result <= mem_alu_result;
            wb_read_data  <= mem_read_data;
            wb_pc_plus4   <= mem_pc_plus4;
        end
    end

endmodule