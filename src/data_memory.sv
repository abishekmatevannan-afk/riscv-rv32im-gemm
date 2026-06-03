// RV32I Data Memory
// Supports byte, halfword, and word reads/writes
// funct3 determines access width (matches RISC-V load/store encoding)

module data_memory (
    input  logic        clk,
    input  logic        we,          // write enable
    input  logic        re,          // read enable
    input  logic [31:0] addr,        // byte address
    input  logic [31:0] wd,          // write data
    input  logic [2:0]  funct3,      // determines access width
    output logic [31:0] rd            // read data
   
);
    // IO region starts at 0xFFFF0000
    

    // 1KB of data memory — enough for test programs
    logic [7:0] mem [0:1023];
    logic [9:0] addr_idx;

    assign addr_idx = addr[9:0];

    // initialize memory to zero
    integer i;
    initial begin
        for (i = 0; i < 1024; i++)
            mem[i] = 8'd0;
    end

    // synchronous write
    always_ff @(posedge clk) begin
        if (we) begin
            case (funct3)
                3'b000: mem[addr_idx]   <= wd[7:0];
                3'b001: begin
                    mem[addr_idx]   <= wd[7:0];
                    mem[addr_idx+1] <= wd[15:8];
                end
                3'b010: begin
                    mem[addr_idx]   <= wd[7:0];
                    mem[addr_idx+1] <= wd[15:8];
                    mem[addr_idx+2] <= wd[23:16];
                    mem[addr_idx+3] <= wd[31:24];
                end
                default: ;
            endcase
        end
    end

    logic [7:0] byte0, byte1, byte2, byte3;

    assign byte0 = mem[addr_idx];
    assign byte1 = mem[addr_idx+1];
    assign byte2 = mem[addr_idx+2];
    assign byte3 = mem[addr_idx+3];

    assign rd = re ? (
        (funct3 == 3'b000) ? {{24{byte0[7]}}, byte0} :
        (funct3 == 3'b001) ? {{16{byte1[7]}}, byte1, byte0} :
        (funct3 == 3'b010) ? {byte3, byte2, byte1, byte0} :
        (funct3 == 3'b100) ? {24'd0, byte0} :
        (funct3 == 3'b101) ? {16'd0, byte1, byte0} :
        32'd0
    ) : 32'd0;

endmodule