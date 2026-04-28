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
    output logic [31:0] rd           // read data
);

    // 1KB of data memory — enough for test programs
    logic [7:0] mem [0:1023];

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
                // SB: store byte
                3'b000: begin
                    mem[addr] <= wd[7:0];
                end

                // SH: store halfword
                3'b001: begin
                    mem[addr]   <= wd[7:0];
                    mem[addr+1] <= wd[15:8];
                end

                // SW: store word
                3'b010: begin
                    mem[addr]   <= wd[7:0];
                    mem[addr+1] <= wd[15:8];
                    mem[addr+2] <= wd[23:16];
                    mem[addr+3] <= wd[31:24];
                end

                default: ; // do nothing on unknown funct3
            endcase
        end
    end

    // asynchronous read with sign extension
    always @* begin
        rd = 32'd0;
        if (re) begin
            case (funct3)
                // LB: load byte signed
                3'b000: rd = {{24{mem[addr][7]}}, mem[addr]};

                // LH: load halfword signed
                3'b001: rd = {{16{mem[addr+1][7]}},
                               mem[addr+1],
                               mem[addr]};

                // LW: load word
                3'b010: rd = {mem[addr+3],
                               mem[addr+2],
                               mem[addr+1],
                               mem[addr]};

                // LBU: load byte unsigned
                3'b100: rd = {24'd0, mem[addr]};

                // LHU: load halfword unsigned
                3'b101: rd = {16'd0, mem[addr+1], mem[addr]};

                default: rd = 32'd0;
            endcase
        end
    end

endmodule