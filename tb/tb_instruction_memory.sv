// tb_instruction_memory.sv

`timescale 1ns/1ps

module tb_instruction_memory;

    logic [31:0] addr;
    logic [31:0] instr;

    instruction_memory dut (
        .addr  (addr),
        .instr (instr)
    );

    initial begin
        $dumpfile("sim/instruction_memory.vcd");
        $dumpvars(0, tb_instruction_memory);
    end

    initial begin
        $display("========== INSTRUCTION MEMORY TESTBENCH ==========");

        // test 1: read first instruction (address 0)
        addr = 32'h00000000; #10;
        $display("addr=0x%08h instr=0x%08h", addr, instr);
        if (instr !== 32'h00000013)
            $display("FAIL: addr 0 | expected NOP (0x00000013) got 0x%08h", instr);
        else
            $display("PASS: addr 0 reads NOP");

        // test 2: read second instruction (address 4)
        addr = 32'h00000004; #10;
        if (instr !== 32'h00000013)
            $display("FAIL: addr 4 | expected NOP got 0x%08h", instr);
        else
            $display("PASS: addr 4 reads NOP");

        // test 3: byte addressing works correctly
        // address 8 should map to mem[2]
        addr = 32'h00000008; #10;
        if (instr !== 32'h00000013)
            $display("FAIL: addr 8 | expected NOP got 0x%08h", instr);
        else
            $display("PASS: addr 8 reads NOP");

        $display("========== DONE ==========");
        $finish;
    end

endmodule