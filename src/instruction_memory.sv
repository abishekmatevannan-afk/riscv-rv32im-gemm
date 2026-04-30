// instruction_memory.sv
// Read-only instruction memory
// Initialized from a hex file at simulation start
// Word-addressed (address divided by 4 internally)

module instruction_memory #(
    parameter HEX_FILE = "programs/test1.hex"
)(
    input  logic [31:0] addr,
    output logic [31:0] instr
);

    logic [31:0] mem [0:255];

    initial begin
        $readmemh(HEX_FILE, mem);
    end

    assign instr = mem[addr[31:2]];

endmodule