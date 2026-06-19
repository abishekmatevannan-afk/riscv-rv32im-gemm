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

    always @(posedge clk1) begin
        if (cpu1.ex_branch && cpu1.ex_funct3 == 3'b001)
            $display("t=%0t BNE in EX: fwd_a=%08h fwd_b=%08h taken=%b predict=%b mispredict=%b icache_stall=%b cache_stall=%b if_id_flush=%b",
                $time, cpu1.ex_fwd_a, cpu1.ex_fwd_b,
                cpu1.ex_branch_taken, cpu1.ex_predict_taken,
                cpu1.mispredict, cpu1.icache_stall,
                cpu1.cache_stall, cpu1.if_id_flush);
    end

    always @(posedge clk1) begin
        if (cpu1.mispredict && !cpu1.if_id_flush)
            $display("t=%0t MISPREDICT SUPPRESSED: icache_stall=%b cache_stall=%b",
                $time, cpu1.icache_stall, cpu1.cache_stall);
    end

    always @(posedge clk1) begin
        if (cpu1.if_pc > 32'h30 && cpu1.if_pc < 32'hFFFF0000)
            $display("t=%0t PC ESCAPED: if_pc=%08h bp_predict_taken=%b bp_target=%08h",
                $time, cpu1.if_pc, cpu1.bp_predict_taken, cpu1.bp_predict_target);
    end

    // Trace addr=4 accesses to diagnose the SH→LHU race
    always @(posedge clk2) begin
        if (cpu2.mem_alu_result == 32'h00000004 && (cpu2.mem_mem_we || cpu2.mem_mem_re))
            $display("t=%0t %s addr=4 wd=%08h rd=%08h hit=%b state=%0d dirty0=%b valid0=%b",
                $time,
                cpu2.mem_mem_we ? "WRITE" : "READ ",
                cpu2.mem_rs2_data,
                cpu2.cache_rd,
                cpu2.DCACHE.hit,
                cpu2.DCACHE.state,
                cpu2.DCACHE.dirty[0],
                cpu2.DCACHE.valid[0]);
    end

    // =========================================================
    // DEBUG PROBES — fires every cycle cpu_we=1 reaches dcache
    // =========================================================

   
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
        

        // add after repeat(600)
$display("icache line 0: valid=%b tag=%06h data=%08h %08h %08h %08h",
    cpu1.ICACHE.valid[0], cpu1.ICACHE.tags[0],
    cpu1.ICACHE.data[0][0], cpu1.ICACHE.data[0][1],
    cpu1.ICACHE.data[0][2], cpu1.ICACHE.data[0][3]);
$display("icache line 1: valid=%b tag=%06h data=%08h %08h %08h %08h",
    cpu1.ICACHE.valid[1], cpu1.ICACHE.tags[1],
    cpu1.ICACHE.data[1][0], cpu1.ICACHE.data[1][1],
    cpu1.ICACHE.data[1][2], cpu1.ICACHE.data[1][3]);
$display("icache line 2: valid=%b tag=%06h data=%08h %08h %08h %08h",
    cpu1.ICACHE.valid[2], cpu1.ICACHE.tags[2],
    cpu1.ICACHE.data[2][0], cpu1.ICACHE.data[2][1],
    cpu1.ICACHE.data[2][2], cpu1.ICACHE.data[2][3]);
$display("x5=0x%08h x6=0x%08h", cpu1.RF.regs[5], cpu1.RF.regs[6]);

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
            cpu2.DSRAM.mem[0][ 7: 0], cpu2.DSRAM.mem[0][15: 8],
            cpu2.DSRAM.mem[0][23:16], cpu2.DSRAM.mem[0][31:24]);
        $display("dmem[4..7]: %02h %02h %02h %02h",
            cpu2.DSRAM.mem[1][ 7: 0], cpu2.DSRAM.mem[1][15: 8],
            cpu2.DSRAM.mem[1][23:16], cpu2.DSRAM.mem[1][31:24]);

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