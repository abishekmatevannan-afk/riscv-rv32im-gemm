`timescale 1ns/1ps

module tb_matmul;

    localparam CLKS_PER_BIT = 10;

    logic clk_s, rst_s, tx_s;
    logic clk_d, rst_d, tx_d;
    logic clk_p, rst_p, tx_p;
    logic clk_a, rst_a, tx_a;

    top_pipeline #(
        .HEX_FILE     ("programs/matmul_scalar.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) scalar_cpu (
        .clk(clk_s), .rst(rst_s), .uart_tx_pin(tx_s), .uart_rx_pin(1'b1)
    );

    top_pipeline #(
        .HEX_FILE     ("programs/matmul_simd.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) simd_cpu (
        .clk(clk_d), .rst(rst_d), .uart_tx_pin(tx_d), .uart_rx_pin(1'b1)
    );

    top_pipeline #(
        .HEX_FILE     ("programs/matmul_parallel_mac.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) pmac_cpu (
        .clk(clk_p), .rst(rst_p), .uart_tx_pin(tx_p), .uart_rx_pin(1'b1)
    );

    top_pipeline #(
        .HEX_FILE     ("programs/matmul_systolic.hex"),
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) systolic_cpu (
        .clk(clk_a), .rst(rst_a), .uart_tx_pin(tx_a), .uart_rx_pin(1'b1)
    );

    initial clk_s = 0; always #5 clk_s = ~clk_s;
    initial clk_d = 0; always #5 clk_d = ~clk_d;
    initial clk_p = 0; always #5 clk_p = ~clk_p;
    initial clk_a = 0; always #5 clk_a = ~clk_a;

    initial begin
        $dumpfile("sim/tb_matmul.vcd");
        $dumpvars(0, tb_matmul);
    end

    // PDOT trace
    always @(posedge clk_d) begin
        if (simd_cpu.ex_pc == 32'h00000150 && simd_cpu.ex_valid) begin
            $display("  [PDOT] i=%0d j=%0d a=0x%08h b=0x%08h result=0x%08h",
                simd_cpu.RF.regs[16], simd_cpu.RF.regs[17],
                simd_cpu.ex_fwd_a, simd_cpu.ex_fwd_b, simd_cpu.ex_result);
        end
    end

    // capture tasks: scalar version
    task automatic cap_byte_s(output logic [7:0] data, output logic ok);
        integer t; t=0; ok=0; data=0;
        while (tx_s==1 && t<10000000) begin @(posedge clk_s); t++; end
        if (t>=10000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk_s);
        for (int i=0;i<8;i++) begin repeat(CLKS_PER_BIT) @(posedge clk_s); data[i]=tx_s; end
        repeat(CLKS_PER_BIT) @(posedge clk_s); ok=1;
    endtask
    task automatic cap_word_s(output logic [31:0] w, output logic ok);
        logic [7:0] b; logic b_ok; w=0; ok=1;
        for (int i=0;i<4;i++) begin cap_byte_s(b,b_ok); if (!b_ok) begin ok=0; return; end w|=(32'(b)<<(i*8)); end
    endtask

    //capture tasks: simd 
    task automatic cap_byte_d(output logic [7:0] data, output logic ok);
        integer t; t=0; ok=0; data=0;
        while (tx_d==1 && t<10000000) begin @(posedge clk_d); t++; end
        if (t>=10000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk_d);
        for (int i=0;i<8;i++) begin repeat(CLKS_PER_BIT) @(posedge clk_d); data[i]=tx_d; end
        repeat(CLKS_PER_BIT) @(posedge clk_d); ok=1;
    endtask
    task automatic cap_word_d(output logic [31:0] w, output logic ok);
        logic [7:0] b; logic b_ok; w=0; ok=1;
        for (int i=0;i<4;i++) begin cap_byte_d(b,b_ok); if (!b_ok) begin ok=0; return; end w|=(32'(b)<<(i*8)); end
    endtask

    // capture tasks: parallel MAC
    task automatic cap_byte_p(output logic [7:0] data, output logic ok);
        integer t; t=0; ok=0; data=0;
        while (tx_p==1 && t<10000000) begin @(posedge clk_p); t++; end
        if (t>=10000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk_p);
        for (int i=0;i<8;i++) begin repeat(CLKS_PER_BIT) @(posedge clk_p); data[i]=tx_p; end
        repeat(CLKS_PER_BIT) @(posedge clk_p); ok=1;
    endtask
    task automatic cap_word_p(output logic [31:0] w, output logic ok);
        logic [7:0] b; logic b_ok; w=0; ok=1;
        for (int i=0;i<4;i++) begin cap_byte_p(b,b_ok); if (!b_ok) begin ok=0; return; end w|=(32'(b)<<(i*8)); end
    endtask

    // capture tasks: systolic
    task automatic cap_byte_a(output logic [7:0] data, output logic ok);
        integer t; t=0; ok=0; data=0;
        while (tx_a==1 && t<10000000) begin @(posedge clk_a); t++; end
        if (t>=10000000) return;
        repeat(CLKS_PER_BIT/2) @(posedge clk_a);
        for (int i=0;i<8;i++) begin repeat(CLKS_PER_BIT) @(posedge clk_a); data[i]=tx_a; end
        repeat(CLKS_PER_BIT) @(posedge clk_a); ok=1;
    endtask
    task automatic cap_word_a(output logic [31:0] w, output logic ok);
        logic [7:0] b; logic b_ok; w=0; ok=1;
        for (int i=0;i<4;i++) begin cap_byte_a(b,b_ok); if (!b_ok) begin ok=0; return; end w|=(32'(b)<<(i*8)); end
    endtask

    // results
    logic [31:0] s_cycles, s_instrs, s_branches, s_mispredicts, s_dhits, s_dmisses;
    logic [31:0] d_cycles, d_instrs, d_branches, d_mispredicts, d_dhits, d_dmisses;
    logic [31:0] p_cycles, p_instrs, p_branches, p_mispredicts, p_dhits, p_dmisses;
    logic [31:0] p_accel_cycles;
    logic [31:0] a_cycles, a_instrs, a_branches, a_mispredicts, a_dhits, a_dmisses;
    logic [31:0] a_accel_cycles;
    logic [7:0]  s_c[0:15], d_c[0:15], p_c[0:15], a_c[0:15];
    logic        ok_s, ok_d, ok_p, ok_a;
    real         s_cpi, d_cpi, s_hit_rate, d_hit_rate;

    logic [7:0] expected_c[0:15];

    initial begin
        // C = A x B where A=B=[[1,2,3,4],[5,6,7,8],[1,2,3,4],[5,6,7,8]]
        expected_c[0]=34;  expected_c[1]=44;  expected_c[2]=54;  expected_c[3]=64;
        expected_c[4]=82;  expected_c[5]=108; expected_c[6]=134; expected_c[7]=160;
        expected_c[8]=34;  expected_c[9]=44;  expected_c[10]=54; expected_c[11]=64;
        expected_c[12]=82; expected_c[13]=108; expected_c[14]=134; expected_c[15]=160;
    end

    initial begin
        $display("========== MATRIX MULTIPLY BENCHMARK ==========");

        // ── SCALAR ──
        rst_s=1; rst_d=1; rst_p=1; rst_a=1;
        repeat(5) @(posedge clk_s); #1;
        rst_s=0;

        $display("\n--- Scalar (RV32M hardware multiply) ---");
        cap_word_s(s_cycles,ok_s);      if(!ok_s) begin $display("TIMEOUT s_cycles");      $finish; end
        cap_word_s(s_instrs,ok_s);      if(!ok_s) begin $display("TIMEOUT s_instrs");      $finish; end
        cap_word_s(s_branches,ok_s);    if(!ok_s) begin $display("TIMEOUT s_branches");    $finish; end
        cap_word_s(s_mispredicts,ok_s); if(!ok_s) begin $display("TIMEOUT s_mispreds");    $finish; end
        cap_word_s(s_dhits,ok_s);       if(!ok_s) begin $display("TIMEOUT s_dhits");       $finish; end
        cap_word_s(s_dmisses,ok_s);     if(!ok_s) begin $display("TIMEOUT s_dmisses");     $finish; end
        for (int i=0;i<16;i++) begin cap_byte_s(s_c[i],ok_s); if(!ok_s) begin $display("TIMEOUT s_c[%0d]",i); $finish; end end
        begin integer e; e=0; for(int i=0;i<16;i++) if(s_c[i]!==expected_c[i]) e++; if(e==0) $display("  PASS"); else $display("  FAIL: %0d wrong",e); end
        s_cpi = real'(s_cycles)/real'(s_instrs);
        s_hit_rate = 100.0*real'(s_dhits)/real'(s_dhits+s_dmisses>0?s_dhits+s_dmisses:1);
        $display("  cycles=%0d  instrs=%0d  CPI=%.3f  D$=%.1f%%", s_cycles, s_instrs, s_cpi, s_hit_rate);

        // ── SIMD ──
        $display("\n--- SIMD (PDOT packed dot product) ---");
        repeat(5) @(posedge clk_d); #1;
        rst_d=0;
        cap_word_d(d_cycles,ok_d);      if(!ok_d) begin $display("TIMEOUT d_cycles");      $finish; end
        cap_word_d(d_instrs,ok_d);      if(!ok_d) begin $display("TIMEOUT d_instrs");      $finish; end
        cap_word_d(d_branches,ok_d);    if(!ok_d) begin $display("TIMEOUT d_branches");    $finish; end
        cap_word_d(d_mispredicts,ok_d); if(!ok_d) begin $display("TIMEOUT d_mispreds");    $finish; end
        cap_word_d(d_dhits,ok_d);       if(!ok_d) begin $display("TIMEOUT d_dhits");       $finish; end
        cap_word_d(d_dmisses,ok_d);     if(!ok_d) begin $display("TIMEOUT d_dmisses");     $finish; end
        for (int i=0;i<16;i++) begin cap_byte_d(d_c[i],ok_d); if(!ok_d) begin $display("TIMEOUT d_c[%0d]",i); $finish; end end
        begin integer e; e=0; for(int i=0;i<16;i++) if(d_c[i]!==expected_c[i]) e++; if(e==0) $display("  PASS"); else $display("  FAIL: %0d wrong",e); end
        d_cpi = real'(d_cycles)/real'(d_instrs);
        d_hit_rate = 100.0*real'(d_dhits)/real'(d_dhits+d_dmisses>0?d_dhits+d_dmisses:1);
        $display("  cycles=%0d  instrs=%0d  CPI=%.3f  D$=%.1f%%", d_cycles, d_instrs, d_cpi, d_hit_rate);

        // ── PARALLEL MAC ──
        $display("\n--- Parallel MAC (0xFFFE, 4-cycle compute) ---");
        repeat(5) @(posedge clk_p); #1;
        rst_p=0;
        cap_word_p(p_cycles,ok_p);      if(!ok_p) begin $display("TIMEOUT p_cycles");      $finish; end
        cap_word_p(p_instrs,ok_p);      if(!ok_p) begin $display("TIMEOUT p_instrs");      $finish; end
        cap_word_p(p_branches,ok_p);    if(!ok_p) begin $display("TIMEOUT p_branches");    $finish; end
        cap_word_p(p_mispredicts,ok_p); if(!ok_p) begin $display("TIMEOUT p_mispreds");    $finish; end
        cap_word_p(p_dhits,ok_p);       if(!ok_p) begin $display("TIMEOUT p_dhits");       $finish; end
        cap_word_p(p_dmisses,ok_p);     if(!ok_p) begin $display("TIMEOUT p_dmisses");     $finish; end
        cap_word_p(p_accel_cycles,ok_p); if(!ok_p) begin $display("TIMEOUT p_accel");      $finish; end
        for (int i=0;i<16;i++) begin cap_byte_p(p_c[i],ok_p); if(!ok_p) begin $display("TIMEOUT p_c[%0d]",i); $finish; end end
        begin integer e; e=0; for(int i=0;i<16;i++) if(p_c[i]!==expected_c[i]) e++; if(e==0) $display("  PASS"); else $display("  FAIL: %0d wrong",e); end
        $display("  CPU cycles=%0d  instrs=%0d  accel_cycles=%0d", p_cycles, p_instrs, p_accel_cycles);

        // ── SYSTOLIC ──
        $display("\n--- Systolic Array (0xFFFD, 11-cycle wavefront) ---");
        repeat(5) @(posedge clk_a); #1;
        rst_a=0;
        cap_word_a(a_cycles,ok_a);       if(!ok_a) begin $display("TIMEOUT a_cycles");      $finish; end
        cap_word_a(a_instrs,ok_a);       if(!ok_a) begin $display("TIMEOUT a_instrs");      $finish; end
        cap_word_a(a_branches,ok_a);     if(!ok_a) begin $display("TIMEOUT a_branches");    $finish; end
        cap_word_a(a_mispredicts,ok_a);  if(!ok_a) begin $display("TIMEOUT a_mispreds");    $finish; end
        cap_word_a(a_dhits,ok_a);        if(!ok_a) begin $display("TIMEOUT a_dhits");       $finish; end
        cap_word_a(a_dmisses,ok_a);      if(!ok_a) begin $display("TIMEOUT a_dmisses");     $finish; end
        cap_word_a(a_accel_cycles,ok_a); if(!ok_a) begin $display("TIMEOUT a_accel");       $finish; end
        for (int i=0;i<16;i++) begin cap_byte_a(a_c[i],ok_a); if(!ok_a) begin $display("TIMEOUT a_c[%0d]",i); $finish; end end
        begin integer e; e=0; for(int i=0;i<16;i++) if(a_c[i]!==expected_c[i]) e++; if(e==0) $display("  PASS"); else $display("  FAIL: %0d wrong",e); end
        $display("  CPU cycles=%0d  instrs=%0d  accel_cycles=%0d", a_cycles, a_instrs, a_accel_cycles);

        // ── SUMMARY ──
        $display("\n========== SUMMARY ==========");
        $display("  %-14s  %6s  %6s  %6s  %8s", "Version", "Cycles", "Instrs", "CPI", "Speedup");
        $display("  %-14s  %6d  %6d  %5.3f  %8s", "Scalar",   s_cycles, s_instrs, s_cpi, "1.00x");
        $display("  %-14s  %6d  %6d  %5.3f  %7.2fx",
            "SIMD", d_cycles, d_instrs, d_cpi, real'(s_cycles)/real'(d_cycles));
        $display("  %-14s  %6d  %6d  %5s  %7.2fx  (accel: %0d cycles)",
            "Parallel MAC", p_cycles, p_instrs, "--",
            real'(s_cycles)/real'(p_cycles), p_accel_cycles);
        $display("  %-14s  %6d  %6d  %5s  %7.2fx  (accel: %0d cycles)",
            "Systolic", a_cycles, a_instrs, "--",
            real'(s_cycles)/real'(a_cycles), a_accel_cycles);
        $display("  Scalar -> Parallel MAC (compute only): %.0fx",
            real'(s_cycles)/real'(p_accel_cycles));
        $display("  Scalar -> Systolic (compute only):     %.0fx",
            real'(s_cycles)/real'(a_accel_cycles));
        $display("========== DONE ==========");
        $finish;
    end

endmodule