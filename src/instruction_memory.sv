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

    integer im;
    integer fd;
    integer line_count;
    string  line;

    initial begin
        for (im = 0; im < 256; im++)
            mem[im] = 32'h00000013;

        line_count = 0;
        fd = $fopen(HEX_FILE, "r");
        if (fd == 0) begin
            $display("ERROR: could not open %s", HEX_FILE);
        end else begin
            while (!$feof(fd)) begin
                line = "";
                if ($fgets(line, fd)) begin
                    if (line.len() > 0)
                        line_count = line_count + 1;
                end
            end
            $fclose(fd);
            if (line_count > 0)
                $readmemh(HEX_FILE, mem, 0, line_count - 1);
        end
    end

    assign instr = mem[addr[31:2]];

endmodule