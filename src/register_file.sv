// 32 x 32-bit registers
// 2 asynchronous read ports, 1 synchronous write port
// x0 hardwired to zero

module register_file (
    input  logic        clk,
    input  logic        we,          // write enable
    input  logic [4:0]  rs1,         // read address 1
    input  logic [4:0]  rs2,         // read address 2
    input  logic [4:0]  rd,          // write address
    input  logic [31:0] wd,          // write data
    output logic [31:0] rd1,         // read data 1
    output logic [31:0] rd2          // read data 2
);

    // 32 registers each 32 bits wide
    logic [31:0] regs [31:0];

    // initialize all registers to zero at start
    integer i;
    initial begin
        for (i = 0; i < 32; i++) begin
            regs[i] = 32'd0;
        end
    end

    // synchronous write
    // x0 write is ignored (hardwired zero)
    always_ff @(posedge clk) begin
        if (we && rd != 5'd0) begin
            regs[rd] <= wd;
        end
    end

    // asynchronous read
    // x0 always returns zero regardless of content
    assign rd1 = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    assign rd2 = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

endmodule