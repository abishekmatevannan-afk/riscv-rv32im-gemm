// instruction_memory.sv
// Read-only instruction memory
// Initialized from a hex file at simulation start
// Word-addressed (address divided by 4 internally)

module instruction_memory (
    input  logic [31:0] addr,        // byte address from PC
    output logic [31:0] instr        // 32-bit instruction output
);

    // 256 words = 1KB of instruction memory
    // enough for test programs
    logic [31:0] mem [0:255];
    localparam int PROGRAM_WORDS = 28;

    // load program from hex file at simulation start
    initial begin
        $readmemh("programs/test.hex", mem, 0, PROGRAM_WORDS - 1);
    end

    // word-aligned read — divide byte address by 4
    // The hex file stores bytes in little-endian order, so swap bytes back
    assign instr = {mem[addr[31:2]][7:0],
                    mem[addr[31:2]][15:8],
                    mem[addr[31:2]][23:16],
                    mem[addr[31:2]][31:24]};

endmodule