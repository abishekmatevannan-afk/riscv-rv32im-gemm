`timescale 1ns/1ps

module tb_top_pipeline;

    logic clk1, rst1;
    logic clk2, rst2;

    top_pipeline #(.HEX_FILE("programs/test1.hex")) cpu1 (
        .clk (clk1),
        .rst (rst1)
    );

    top_pipeline #(.HEX_FILE("programs/test2.hex")) cpu2 (
        .clk (clk2),
        .rst (rst2),
        .uart_tx_pin ()
    );

    initial begin
        $dumpfile("sim/top_pipeline.vcd");
        $dumpvars(0, tb_top_pipeline);
    end

    initial clk1 = 0;
    always #5 clk1 = ~clk1;

    initial clk2 = 0;
    always #5 clk2 = ~clk2;

    // =========================================================
    // DEBUG PROBES — fires every cycle cpu_we=1 reaches dcache
    // =========================================================

   // probe 1: track SH (instr=0x01501223) moving through each stage
always @(posedge clk2) begin
    if (cpu2.id_instr == 32'h01501223)
        $display("t=%0t SH in ID", $time);
end

always @(posedge clk2) begin
    if (cpu2.ex_mem_we && cpu2.ex_funct3 == 3'b001 && cpu2.ex_opcode == 7'b0100011)
        $display("t=%0t SH in EX: alu_result=%08h fwd_b=%08h",
            $time, cpu2.ex_alu_result, cpu2.ex_fwd_b);
end

always @(posedge clk2) begin
    if (cpu2.mem_mem_we && cpu2.mem_funct3 == 3'b001)
        $display("t=%0t SH in MEM: addr=%08h rs2=%08h is_io=%b cpu_we=%b",
            $time, cpu2.mem_alu_result, cpu2.mem_rs2_data,
            cpu2.is_io, cpu2.DCACHE.cpu_we);
end

always @(posedge clk2) begin
    if (cpu2.id_instr == 32'h0ff00a13 || cpu2.id_instr == 32'h01400023 || cpu2.id_instr == 32'h00004083 ||
        cpu2.id_instr == 32'h7ff00a93 || cpu2.id_instr == 32'h01501223 || cpu2.id_instr == 32'h00405103 ||
        cpu2.id_instr == 32'h00401183 || cpu2.id_instr == 32'h00500593 || cpu2.id_instr == 32'h00a00613 ||
        cpu2.id_instr == 32'h00c5a233 || cpu2.id_instr == 32'habcde2b7) begin
        $display("t=%0t DECODE ID pc=0x%08h instr=0x%08h x11=%08h x12=%08h x21=%08h x4=%08h x2=%08h x3=%08h stall=%b state=%b",
                 $time, cpu2.id_pc, cpu2.id_instr, cpu2.RF.regs[11], cpu2.RF.regs[12], cpu2.RF.regs[21], cpu2.RF.regs[4], cpu2.RF.regs[2], cpu2.RF.regs[3], cpu2.cache_stall, cpu2.DCACHE.state);
    end
end
    task automatic check1(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string test_name
    );
        if (cpu1.RF.regs[reg_addr] !== expected)
            $display("FAIL [TEST1]: %s | x%0d expected=0x%08h got=0x%08h",
                     test_name, reg_addr, expected, cpu1.RF.regs[reg_addr]);
        else
            $display("PASS [TEST1]: %s | x%0d = 0x%08h",
                     test_name, reg_addr, expected);
    endtask

    task automatic check2(
        input [4:0]  reg_addr,
        input [31:0] expected,
        input string test_name
    );
        if (cpu2.RF.regs[reg_addr] !== expected)
            $display("FAIL [TEST2]: %s | x%0d expected=0x%08h got=0x%08h",
                     test_name, reg_addr, expected, cpu2.RF.regs[reg_addr]);
        else
            $display("PASS [TEST2]: %s | x%0d = 0x%08h",
                     test_name, reg_addr, expected);
    endtask

    initial begin
        $display("========== PIPELINE CPU TESTBENCH ==========");

        rst1 = 1; rst2 = 1;
        @(posedge clk1); #1;
        rst1 = 0; rst2 = 0;
        

        repeat(40) @(posedge clk2); #1;

    repeat(100) begin
        @(posedge clk2); #1;
        if (cpu2.mem_mem_we)
            $display("STORE: addr=0x%08h wd=0x%08h funct3=%b hit=%b state=%b x21=0x%08h x11=0x%08h x12=0x%08h x4=0x%08h",
                     cpu2.mem_alu_result,
                     cpu2.mem_rs2_data,
                     cpu2.mem_funct3,
                     cpu2.DCACHE.hit,
                     cpu2.DCACHE.state,
                     cpu2.RF.regs[21],
                     cpu2.RF.regs[11],
                     cpu2.RF.regs[12],
                     cpu2.RF.regs[4]);
    end
        repeat(600) @(posedge clk1);
        #1;

        $display("\n--- DCACHE STATE DUMP ---");
        $display("dcache line 0: valid=%b dirty=%b tag=%06h data=%08h %08h %08h %08h",
            cpu2.DCACHE.valid[0], cpu2.DCACHE.dirty[0], cpu2.DCACHE.tags[0],
            cpu2.DCACHE.data[0][0], cpu2.DCACHE.data[0][1],
            cpu2.DCACHE.data[0][2], cpu2.DCACHE.data[0][3]);
        $display("dcache line 1: valid=%b dirty=%b tag=%06h data=%08h %08h %08h %08h",
            cpu2.DCACHE.valid[1], cpu2.DCACHE.dirty[1], cpu2.DCACHE.tags[1],
            cpu2.DCACHE.data[1][0], cpu2.DCACHE.data[1][1],
            cpu2.DCACHE.data[1][2], cpu2.DCACHE.data[1][3]);
        $display("dmem[0..3]: %02h %02h %02h %02h",
            cpu2.DMEM.mem[0], cpu2.DMEM.mem[1],
            cpu2.DMEM.mem[2], cpu2.DMEM.mem[3]);
        $display("dmem[4..7]: %02h %02h %02h %02h",
            cpu2.DMEM.mem[4], cpu2.DMEM.mem[5],
            cpu2.DMEM.mem[6], cpu2.DMEM.mem[7]);

        $display("\n--- TEST 1: Arithmetic + Branch + Loop ---");
        check1(5'd1, 32'd5,   "addi x1=5");
        check1(5'd2, 32'd10,  "addi x2=10");
        check1(5'd3, 32'd15,  "add  x3=15");
        check1(5'd4, 32'd5,   "addi x4=5");
        check1(5'd5, 32'd150, "loop x5=150");
        check1(5'd6, 32'd0,   "loop x6=0");

        $display("\n--- TEST 2: Memory + Logic + LUI ---");
        check2(5'd1,  32'h000000FF, "LBU byte load");
        check2(5'd2,  32'h000007FF, "LHU halfword unsigned");
        check2(5'd3,  32'h000007FF, "LH halfword positive");
        check2(5'd4,  32'd1,        "SLT 5 < 10");
        check2(5'd5,  32'hABCDE000, "LUI upper immediate");
        check2(5'd6,  32'd0,        "XOR same = 0");
        check2(5'd7,  32'd255,      "OR 0xF0|0x0F");
        check2(5'd8,  32'd100,      "AND result");

        $display("\n========== DONE ==========");
        $display("REGS x11=%08h x12=%08h x21=%08h x4=%08h", cpu2.RF.regs[11], cpu2.RF.regs[12], cpu2.RF.regs[21], cpu2.RF.regs[4]);
        $finish;
    end

endmodule