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

    logic [7:0] mem [0:262143];  // 256KB = 262144 bytes

    integer i;
    initial begin
        for (i = 0; i < 262144; i++)
            mem[i] = 8'd0;
    end

    logic [7:0] byte0, byte1, byte2, byte3;

    assign byte0 = mem[addr[17:0]];
    assign byte1 = mem[addr[17:0] + 1];
    assign byte2 = mem[addr[17:0] + 2];
    assign byte3 = mem[addr[17:0] + 3];

    always_ff @(posedge clk) begin
        if (we) begin
            case (funct3)
                3'b000: mem[addr[17:0]]   <= wd[7:0];
                3'b001: begin
                    mem[addr[17:0]]   <= wd[7:0];
                    mem[addr[17:0]+1] <= wd[15:8];
                end
                3'b010: begin
                    mem[addr[17:0]]   <= wd[7:0];
                    mem[addr[17:0]+1] <= wd[15:8];
                    mem[addr[17:0]+2] <= wd[23:16];
                    mem[addr[17:0]+3] <= wd[31:24];
                end
            endcase
        end
    end

    assign rd = re ? (
        (funct3 == 3'b000) ? {{24{byte0[7]}}, byte0} :
        (funct3 == 3'b001) ? {{16{byte1[7]}}, byte1, byte0} :
        (funct3 == 3'b010) ? {byte3, byte2, byte1, byte0} :
        (funct3 == 3'b100) ? {24'd0, byte0} :
        (funct3 == 3'b101) ? {16'd0, byte1, byte0} :
        32'd0
    ) : 32'd0;

endmodule
