`timescale 1ns/1ps

module tb_matmul;

    localparam CLKS_PER_BIT = 10;

    logic clk_s, rst_s, tx_s;
    logic clk_d, rst_d, tx_d;

    top_pipeline #(
        .HEX_FILE     ("programs/matmul_scalar.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) scalar_cpu (
        .clk         (clk_s),
        .rst         (rst_s),
        .uart_tx_pin (tx_s),
        .uart_rx_pin (1'b1)
    );

    top_pipeline #(
        .HEX_FILE     ("programs/matmul_simd.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) simd_cpu (
        .clk         (clk_d),
        .rst         (rst_d),
        .uart_tx_pin (tx_d),
        .uart_rx_pin (1'b1)
    );

    initial clk_s = 0; always #5 clk_s = ~clk_s;
    initial clk_d = 0; always #5 clk_d = ~clk_d;

    initial begin
        $dumpfile("sim/tb_matmul.vcd");
        $dumpvars(0, tb_matmul);
    end

    // PDOT trace: print x16,x17,x20,x21,result every time PDOT fires in EX
    always @(posedge clk_d) begin
        if (simd_cpu.ex_pc == 32'h00000114 && simd_cpu.ex_valid) begin
            $display("  [PDOT] i=%0d j=%0d a=0x%08h b=0x%08h result=0x%08h",
                simd_cpu.RF.regs[16],
                simd_cpu.RF.regs[17],
                simd_cpu.ex_fwd_a,
                simd_cpu.ex_fwd_b,
                simd_cpu.ex_result);
        end
    end

    // scalar capture tasks
    task automatic cap_byte_s(output logic [7:0] data, output logic ok);
        integer timeout;
        timeout = 0; ok = 0; data = 0;
        while (tx_s == 1 && timeout < 10000000) begin
            @(posedge clk_s); timeout++;
        end
        if (timeout >= 10000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk_s);
        for (int i = 0; i < 8; i++) begin
            repeat(CLKS_PER_BIT) @(posedge clk_s);
            data[i] = tx_s;
        end
        repeat(CLKS_PER_BIT) @(posedge clk_s);
        ok = 1;
    endtask

    task automatic cap_word_s(output logic [31:0] w, output logic ok);
        logic [7:0] b; logic b_ok;
        w = 0; ok = 1;
        for (int i = 0; i < 4; i++) begin
            cap_byte_s(b, b_ok);
            if (!b_ok) begin ok = 0; return; end
            w |= (32'(b) << (i*8));
        end
    endtask

    // simd capture tasks
    task automatic cap_byte_d(output logic [7:0] data, output logic ok);
        integer timeout;
        timeout = 0; ok = 0; data = 0;
        while (tx_d == 1 && timeout < 10000000) begin
            @(posedge clk_d); timeout++;
        end
        if (timeout >= 10000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk_d);
        for (int i = 0; i < 8; i++) begin
            repeat(CLKS_PER_BIT) @(posedge clk_d);
            data[i] = tx_d;
        end
        repeat(CLKS_PER_BIT) @(posedge clk_d);
        ok = 1;
    endtask

    task automatic cap_word_d(output logic [31:0] w, output logic ok);
        logic [7:0] b; logic b_ok;
        w = 0; ok = 1;
        for (int i = 0; i < 4; i++) begin
            cap_byte_d(b, b_ok);
            if (!b_ok) begin ok = 0; return; end
            w |= (32'(b) << (i*8));
        end
    endtask

    logic [31:0] s_cycles, s_instrs, s_branches, s_mispredicts, s_dhits, s_dmisses;
    logic [31:0] d_cycles, d_instrs, d_branches, d_mispredicts, d_dhits, d_dmisses;
    logic [7:0]  s_c[0:15], d_c[0:15];
    logic        ok_s, ok_d;
    real         s_cpi, d_cpi, s_hit_rate, d_hit_rate, speedup;

    logic [7:0] expected_c[0:15];

    initial begin
        expected_c[0]=1;  expected_c[1]=2;  expected_c[2]=3;  expected_c[3]=4;
        expected_c[4]=5;  expected_c[5]=6;  expected_c[6]=7;  expected_c[7]=8;
        expected_c[8]=1;  expected_c[9]=2;  expected_c[10]=3; expected_c[11]=4;
        expected_c[12]=5; expected_c[13]=6; expected_c[14]=7; expected_c[15]=8;
    end

    initial begin
        $display("========== MATRIX MULTIPLY BENCHMARK ==========");

        // ---- SCALAR ----
        rst_s = 1; rst_d = 1;
        repeat(5) @(posedge clk_s); #1;
        rst_s = 0;

        $display("\n--- Scalar (shift-and-add multiply) ---");
        cap_word_s(s_cycles,      ok_s); if (!ok_s) begin $display("TIMEOUT scalar cycles");      $finish; end
        cap_word_s(s_instrs,      ok_s); if (!ok_s) begin $display("TIMEOUT scalar instrs");      $finish; end
        cap_word_s(s_branches,    ok_s); if (!ok_s) begin $display("TIMEOUT scalar branches");    $finish; end
        cap_word_s(s_mispredicts, ok_s); if (!ok_s) begin $display("TIMEOUT scalar mispredicts"); $finish; end
        cap_word_s(s_dhits,       ok_s); if (!ok_s) begin $display("TIMEOUT scalar dhits");       $finish; end
        cap_word_s(s_dmisses,     ok_s); if (!ok_s) begin $display("TIMEOUT scalar dmisses");     $finish; end

        $display("  cycles       = %0d", s_cycles);
        $display("  instructions = %0d", s_instrs);
        $display("  branches     = %0d", s_branches);
        $display("  mispredicts  = %0d", s_mispredicts);
        $display("  D$ hits      = %0d", s_dhits);
        $display("  D$ misses    = %0d", s_dmisses);

        for (int i = 0; i < 16; i++) begin
            cap_byte_s(s_c[i], ok_s);
            if (!ok_s) begin $display("TIMEOUT scalar C[%0d]", i); $finish; end
        end

        $display("  C matrix:");
        for (int r = 0; r < 4; r++) begin
            $write("    row%0d: [", r);
            for (int c2 = 0; c2 < 4; c2++) $write(" %0d", s_c[r*4+c2]);
            $display(" ]");
        end

        begin
            integer errs; errs = 0;
            for (int i = 0; i < 16; i++)
                if (s_c[i] !== expected_c[i]) errs++;
            if (errs == 0) $display("  PASS: C = A (correct)");
            else           $display("  FAIL: %0d elements wrong", errs);
        end

        s_cpi      = real'(s_cycles) / real'(s_instrs);
        s_hit_rate = 100.0 * real'(s_dhits) / real'(s_dhits + s_dmisses > 0 ? s_dhits + s_dmisses : 1);
        $display("  CPI         = %.3f", s_cpi);
        $display("  D$ hit rate = %.1f%%", s_hit_rate);
        $display("  branch misp = %.1f%%",
            100.0 * real'(s_mispredicts) / real'(s_branches > 0 ? s_branches : 1));

        // ---- SIMD ----
        $display("\n--- SIMD (PDOT packed 4x8-bit dot product) ---");
        repeat(5) @(posedge clk_d); #1;
        rst_d = 0;

        cap_word_d(d_cycles,      ok_d); if (!ok_d) begin $display("TIMEOUT simd cycles");      $finish; end
        cap_word_d(d_instrs,      ok_d); if (!ok_d) begin $display("TIMEOUT simd instrs");      $finish; end
        cap_word_d(d_branches,    ok_d); if (!ok_d) begin $display("TIMEOUT simd branches");    $finish; end
        cap_word_d(d_mispredicts, ok_d); if (!ok_d) begin $display("TIMEOUT simd mispredicts"); $finish; end
        cap_word_d(d_dhits,       ok_d); if (!ok_d) begin $display("TIMEOUT simd dhits");       $finish; end
        cap_word_d(d_dmisses,     ok_d); if (!ok_d) begin $display("TIMEOUT simd dmisses");     $finish; end

        $display("  cycles       = %0d", d_cycles);
        $display("  instructions = %0d", d_instrs);
        $display("  branches     = %0d", d_branches);
        $display("  mispredicts  = %0d", d_mispredicts);
        $display("  D$ hits      = %0d", d_dhits);
        $display("  D$ misses    = %0d", d_dmisses);

        for (int i = 0; i < 16; i++) begin
            cap_byte_d(d_c[i], ok_d);
            if (!ok_d) begin $display("TIMEOUT simd C[%0d]", i); $finish; end
        end

        $display("  C matrix:");
        for (int r = 0; r < 4; r++) begin
            $write("    row%0d: [", r);
            for (int c2 = 0; c2 < 4; c2++) $write(" %0d", d_c[r*4+c2]);
            $display(" ]");
        end

        begin
            integer errs; errs = 0;
            for (int i = 0; i < 16; i++)
                if (d_c[i] !== expected_c[i]) errs++;
            if (errs == 0) $display("  PASS: C = A (correct)");
            else           $display("  FAIL: %0d elements wrong", errs);
        end

        d_cpi      = real'(d_cycles) / real'(d_instrs);
        d_hit_rate = 100.0 * real'(d_dhits) / real'(d_dhits + d_dmisses > 0 ? d_dhits + d_dmisses : 1);
        speedup    = real'(s_cycles) / real'(d_cycles);

        $display("  CPI         = %.3f", d_cpi);
        $display("  D$ hit rate = %.1f%%", d_hit_rate);
        $display("  branch misp = %.1f%%",
            100.0 * real'(d_mispredicts) / real'(d_branches > 0 ? d_branches : 1));

        $display("\n========== SUMMARY ==========");
        $display("  Scalar:  %0d cycles  %0d instrs  CPI=%.3f",
            s_cycles, s_instrs, s_cpi);
        $display("  SIMD:    %0d cycles  %0d instrs  CPI=%.3f",
            d_cycles, d_instrs, d_cpi);
        $display("  Speedup: %.2fx", speedup);
        $display("  D$ hit rate (both): %.1f%%", s_hit_rate);
        $display("========== DONE ==========");
        $finish;
    end

endmodule