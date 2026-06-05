`timescale 1ns/1ps

module tb_csr_regfile;

    logic        clk, rst;
    logic        csr_we;
    logic [11:0] csr_addr;
    logic [31:0] csr_wd, csr_rd;
    logic        trap, mret;
    logic [31:0] trap_cause, trap_epc;
    logic        ext_irq;
    logic [31:0] mtvec_out, mepc_out;
    logic        mie_global, meie;

    csr_regfile dut (
        .clk        (clk),
        .rst        (rst),
        .csr_we     (csr_we),
        .csr_addr   (csr_addr),
        .csr_wd     (csr_wd),
        .csr_rd     (csr_rd),
        .trap       (trap),
        .trap_cause (trap_cause),
        .trap_epc   (trap_epc),
        .mret       (mret),
        .ext_irq    (ext_irq),
        .mtvec_out  (mtvec_out),
        .mepc_out   (mepc_out),
        .mie_global (mie_global),
        .meie       (meie)
    );

    initial begin
        $dumpfile("sim/csr_regfile.vcd");
        $dumpvars(0, tb_csr_regfile);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic csr_write(input [11:0] a, input [31:0] d);
        @(posedge clk); #1;
        csr_we = 1; csr_addr = a; csr_wd = d;
        @(posedge clk); #1;
        csr_we = 0;
    endtask

    task automatic csr_read(input [11:0] a, output [31:0] result);
        csr_addr = a;
        #1;
        result = csr_rd;
    endtask

    logic [31:0] val;

    initial begin
        $display("========== CSR REGFILE TESTBENCH ==========");

        rst = 1; csr_we = 0; trap = 0; mret = 0;
        ext_irq = 0; csr_addr = 0; csr_wd = 0;
        trap_cause = 0; trap_epc = 0;
        repeat(3) @(posedge clk); #1;
        rst = 0;

        // TEST 1: mtvec write and read
        $display("--- TEST 1: mtvec write/read ---");
        csr_write(12'h305, 32'hDEAD0000);
        csr_read(12'h305, val);
        if (val == 32'hDEAD0000 && mtvec_out == 32'hDEAD0000)
            $display("PASS: mtvec=0x%08h", val);
        else
            $display("FAIL: mtvec=0x%08h", val);

        // TEST 2: mstatus MIE bit
        $display("--- TEST 2: mstatus MIE bit ---");
        csr_write(12'h300, 32'h00000008);  // set MIE=1
        if (mie_global) $display("PASS: MIE=1");
        else             $display("FAIL: MIE not set");

        // TEST 3: mie MEIE bit
        $display("--- TEST 3: mie MEIE bit ---");
        csr_write(12'h304, 32'h00000800);  // set MEIE=1
        if (meie) $display("PASS: MEIE=1");
        else       $display("FAIL: MEIE not set");

        // TEST 4: trap saves mepc and mcause, clears MIE
        $display("--- TEST 4: trap handling ---");
        @(posedge clk); #1;
        trap = 1; trap_epc = 32'h00000100; trap_cause = 32'd2;  // illegal instruction
        @(posedge clk); #1;
        trap = 0;
        @(posedge clk); #1;
        csr_read(12'h341, val);
        if (val == 32'h00000100) $display("PASS: mepc=0x%08h", val);
        else                      $display("FAIL: mepc=0x%08h exp=0x100", val);
        csr_read(12'h342, val);
        if (val == 32'd2) $display("PASS: mcause=%0d", val);
        else               $display("FAIL: mcause=%0d exp=2", val);
        if (!mie_global) $display("PASS: MIE cleared on trap");
        else              $display("FAIL: MIE should be 0 in handler");

        // TEST 5: MRET restores MIE
        $display("--- TEST 5: MRET restores MIE ---");
        @(posedge clk); #1;
        mret = 1;
        @(posedge clk); #1;
        mret = 0;
        @(posedge clk); #1;
        if (mie_global) $display("PASS: MIE restored after MRET");
        else             $display("FAIL: MIE not restored");

        // TEST 6: mip reflects ext_irq
        $display("--- TEST 6: mip reflects ext_irq ---");
        ext_irq = 1;
        csr_read(12'h344, val);
        if (val[11]) $display("PASS: mip.MEIP=1");
        else          $display("FAIL: mip.MEIP not set");
        ext_irq = 0;
        csr_read(12'h344, val);
        if (!val[11]) $display("PASS: mip.MEIP cleared");
        else           $display("FAIL: mip.MEIP not cleared");

        // TEST 7: mepc write/read (software use)
        $display("--- TEST 7: mepc direct write ---");
        csr_write(12'h341, 32'hCAFE0004);
        if (mepc_out == 32'hCAFE0004) $display("PASS: mepc_out=0x%08h", mepc_out);
        else                           $display("FAIL: mepc_out=0x%08h", mepc_out);

        // TEST 8: mip is read-only (write ignored)
        $display("--- TEST 8: mip read-only ---");
        csr_write(12'h344, 32'hFFFFFFFF);
        ext_irq = 0;
        csr_read(12'h344, val);
        if (val == 32'd0) $display("PASS: mip write ignored");
        else               $display("FAIL: mip was written: 0x%08h", val);

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule