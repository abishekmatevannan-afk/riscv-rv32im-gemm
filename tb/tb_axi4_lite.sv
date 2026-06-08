`timescale 1ns/1ps

// Integrated AXI4-Lite testbench
// Tests: icache_manager + dcache_manager + interconnect + ISRAM + DSRAM
// Simulates the full icache fill path and dcache writeback+fill path
// using the actual AXI4-Lite fabric, not direct memory connections

module tb_axi4_lite;

    logic clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;

    int pass_count, fail_count;

    task tick;
        @(posedge clk); #1;
    endtask

    task check32(input string label, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $display("FAIL [%s]: exp=0x%08h got=0x%08h", label, exp, got);
            fail_count++;
        end else begin
            $display("PASS [%s]: 0x%08h", label, got);
            pass_count++;
        end
    endtask

    task check1(input string label, input logic got, input logic exp);
        if (got !== exp) begin
            $display("FAIL [%s]: exp=%b got=%b", label, exp, got);
            fail_count++;
        end else begin
            $display("PASS [%s]: %b", label, got);
            pass_count++;
        end
    endtask

    // =========================================================
    // icache side: manager signals
    
    logic        ic_mem_re;
    logic [31:0] ic_mem_addr;
    logic [31:0] ic_mem_rd;

    // icache manager AXI AR/R
    logic        ic_arvalid, ic_arready;
    logic [31:0] ic_araddr;
    logic        ic_rvalid, ic_rready;
    logic [31:0] ic_rdata;
    logic [1:0]  ic_rresp;

    axi4_lite_icache_manager ICACHE_MGR (
        .mem_re  (ic_mem_re),
        .mem_addr(ic_mem_addr),
        .mem_rd  (ic_mem_rd),
        .arvalid (ic_arvalid),
        .araddr  (ic_araddr),
        .arready (ic_arready),
        .rvalid  (ic_rvalid),
        .rdata   (ic_rdata),
        .rresp   (ic_rresp),
        .rready  (ic_rready)
    );

    // =========================================================
    // dcache side: manager signals
    // =========================================================
    logic        dc_mem_we, dc_mem_re;
    logic [31:0] dc_mem_addr, dc_mem_wd, dc_mem_rd;

    // dcache manager AXI
    logic        dc_awvalid, dc_awready;
    logic [31:0] dc_awaddr;
    logic        dc_wvalid, dc_wready;
    logic [31:0] dc_wdata;
    logic [3:0]  dc_wstrb;
    logic        dc_bvalid, dc_bready;
    logic [1:0]  dc_bresp;
    logic        dc_arvalid, dc_arready;
    logic [31:0] dc_araddr;
    logic        dc_rvalid, dc_rready;
    logic [31:0] dc_rdata;
    logic [1:0]  dc_rresp;

    axi4_lite_dcache_manager DCACHE_MGR (
        .mem_we  (dc_mem_we),
        .mem_re  (dc_mem_re),
        .mem_addr(dc_mem_addr),
        .mem_wd  (dc_mem_wd),
        .mem_rd  (dc_mem_rd),
        .awvalid (dc_awvalid), .awaddr(dc_awaddr), .awready(dc_awready),
        .wvalid  (dc_wvalid),  .wdata (dc_wdata),  .wstrb(dc_wstrb), .wready(dc_wready),
        .bvalid  (dc_bvalid),  .bresp (dc_bresp),  .bready(dc_bready),
        .arvalid (dc_arvalid), .araddr(dc_araddr), .arready(dc_arready),
        .rvalid  (dc_rvalid),  .rdata (dc_rdata),  .rresp(dc_rresp), .rready(dc_rready)
    );

    // =========================================================
    // Interconnect
    // =========================================================
    // icache → ISRAM (s0)
    logic        s0_arvalid, s0_arready;
    logic [31:0] s0_araddr;
    logic        s0_rvalid, s0_rready;
    logic [31:0] s0_rdata;
    logic [1:0]  s0_rresp;
    // dcache → DSRAM (s1)
    logic        s1_awvalid, s1_awready;
    logic [31:0] s1_awaddr;
    logic        s1_wvalid, s1_wready;
    logic [31:0] s1_wdata;
    logic [3:0]  s1_wstrb;
    logic        s1_bvalid, s1_bready;
    logic [1:0]  s1_bresp;
    logic        s1_arvalid, s1_arready;
    logic [31:0] s1_araddr;
    logic        s1_rvalid, s1_rready;
    logic [31:0] s1_rdata;
    logic [1:0]  s1_rresp;

    axi4_lite_interconnect XBAR (
        .m0_arvalid(ic_arvalid), .m0_arready(ic_arready),
        .m0_araddr (ic_araddr),
        .m0_rvalid (ic_rvalid),  .m0_rready (ic_rready),
        .m0_rdata  (ic_rdata),   .m0_rresp  (ic_rresp),

        .m1_awvalid(dc_awvalid), .m1_awready(dc_awready), .m1_awaddr(dc_awaddr),
        .m1_wvalid (dc_wvalid),  .m1_wready (dc_wready),
        .m1_wdata  (dc_wdata),   .m1_wstrb  (dc_wstrb),
        .m1_bvalid (dc_bvalid),  .m1_bready (dc_bready),  .m1_bresp (dc_bresp),
        .m1_arvalid(dc_arvalid), .m1_arready(dc_arready), .m1_araddr(dc_araddr),
        .m1_rvalid (dc_rvalid),  .m1_rready (dc_rready),
        .m1_rdata  (dc_rdata),   .m1_rresp  (dc_rresp),

        .s0_arvalid(s0_arvalid), .s0_arready(s0_arready), .s0_araddr(s0_araddr),
        .s0_rvalid (s0_rvalid),  .s0_rready (s0_rready),
        .s0_rdata  (s0_rdata),   .s0_rresp  (s0_rresp),

        .s1_awvalid(s1_awvalid), .s1_awready(s1_awready), .s1_awaddr(s1_awaddr),
        .s1_wvalid (s1_wvalid),  .s1_wready (s1_wready),
        .s1_wdata  (s1_wdata),   .s1_wstrb  (s1_wstrb),
        .s1_bvalid (s1_bvalid),  .s1_bready (s1_bready),  .s1_bresp (s1_bresp),
        .s1_arvalid(s1_arvalid), .s1_arready(s1_arready), .s1_araddr(s1_araddr),
        .s1_rvalid (s1_rvalid),  .s1_rready (s1_rready),
        .s1_rdata  (s1_rdata),   .s1_rresp  (s1_rresp)
    );

    // =========================================================
    // SRAM subordinates
    // ISRAM: initialized with known pattern for verification
    // DSRAM: starts zeroed, written then read back
    // =========================================================
    axi4_lite_sram_sub #(
        .DEPTH_WORDS(256),
        .HEX_FILE   ("programs/test1.hex"),
        .READ_ONLY  (1)
    ) ISRAM (
        .clk(clk), .rst(rst),
        .arvalid(s0_arvalid), .arready(s0_arready), .araddr(s0_araddr),
        .rvalid (s0_rvalid),  .rready (s0_rready),
        .rdata  (s0_rdata),   .rresp  (s0_rresp),
        .awvalid(1'b0), .awready(), .awaddr(32'd0),
        .wvalid (1'b0), .wready (),  .wdata(32'd0), .wstrb(4'd0),
        .bvalid (), .bready(1'b1), .bresp()
    );

    axi4_lite_sram_sub #(
        .DEPTH_WORDS(256),
        .HEX_FILE   (""),
        .READ_ONLY  (0)
    ) DSRAM (
        .clk(clk), .rst(rst),
        .arvalid(s1_arvalid), .arready(s1_arready), .araddr(s1_araddr),
        .rvalid (s1_rvalid),  .rready (s1_rready),
        .rdata  (s1_rdata),   .rresp  (s1_rresp),
        .awvalid(s1_awvalid), .awready(s1_awready), .awaddr(s1_awaddr),
        .wvalid (s1_wvalid),  .wready (s1_wready),
        .wdata  (s1_wdata),   .wstrb  (s1_wstrb),
        .bvalid (s1_bvalid),  .bready (s1_bready),  .bresp(s1_bresp)
    );

    // =========================================================
    // Test body
    // =========================================================
    initial begin
        $dumpfile("sim/tb_axi4_lite.vcd");
        $dumpvars(0, tb_axi4_lite);

        pass_count = 0;
        fail_count = 0;

        ic_mem_re   = 0;
        ic_mem_addr = 0;
        dc_mem_we   = 0;
        dc_mem_re   = 0;
        dc_mem_addr = 0;
        dc_mem_wd   = 0;

        rst = 1;
        repeat(2) tick;
        rst = 0;

        // ---------------------------------------------------------
        // TEST 1: icache read -- combinational response
        // ISRAM initialized from test1.hex
        // First word of test1 is known (0x00500093 = addi x1,x0,5)
        // Manager is combinational: ic_mem_re=1 → ARVALID=1 →
        //   SRAM: RVALID=1, RDATA=mem[0] same cycle
        //   ic_mem_rd = RDATA available immediately
        // ---------------------------------------------------------
        $display("\n--- TEST 1: icache read (ISRAM, word 0) ---");
        ic_mem_re   = 1;
        ic_mem_addr = 32'h00000000;
        #1;  // combinational settle time
        check1 ("T1 ARVALID", ic_arvalid, 1'b1);
        check1 ("T1 RVALID",  ic_rvalid,  1'b1);
        check32("T1 icache word 0", ic_mem_rd, 32'h00500093);
        tick;

        // ---------------------------------------------------------
        // TEST 2: icache read -- word 1 (still combinational)
        // ---------------------------------------------------------
        $display("\n--- TEST 2: icache read (ISRAM, word 1) ---");
        ic_mem_addr = 32'h00000004;
        #1;
        check32("T2 icache word 1", ic_mem_rd, 32'h00a00113);
        ic_mem_re = 0;
        tick;

        // ---------------------------------------------------------
        // TEST 3: dcache write (simulate WRITEBACK of two words)
        // Write 0xDEADBEEF to addr 0x00000000 and 0xCAFEBABE to 0x00000004
        // ---------------------------------------------------------
        $display("\n--- TEST 3: dcache write to DSRAM ---");
        dc_mem_we   = 1;
        dc_mem_re   = 0;
        dc_mem_addr = 32'h00000000;
        dc_mem_wd   = 32'hDEADBEEF;
        #1;
        check1 ("T3 AWVALID", dc_awvalid, 1'b1);
        check1 ("T3 WVALID",  dc_wvalid,  1'b1);
        check1 ("T3 AWREADY", dc_awready, 1'b1);
        check1 ("T3 WREADY",  dc_wready,  1'b1);
        check1 ("T3 BVALID",  dc_bvalid,  1'b1);
        tick;   // write commits at this posedge

        dc_mem_addr = 32'h00000004;
        dc_mem_wd   = 32'hCAFEBABE;
        tick;   // second word commits

        dc_mem_we = 0;
        tick;

        // ---------------------------------------------------------
        // TEST 4: dcache read -- verify written data (FILL path)
        // Read back words written in TEST 3
        // ---------------------------------------------------------
        $display("\n--- TEST 4: dcache read from DSRAM ---");
        dc_mem_re   = 1;
        dc_mem_addr = 32'h00000000;
        #1;
        check1 ("T4 ARVALID", dc_arvalid, 1'b1);
        check1 ("T4 RVALID",  dc_rvalid,  1'b1);
        check32("T4 readback word 0", dc_mem_rd, 32'hDEADBEEF);
        tick;

        dc_mem_addr = 32'h00000004;
        #1;
        check32("T4 readback word 1", dc_mem_rd, 32'hCAFEBABE);
        dc_mem_re = 0;
        tick;

        // ---------------------------------------------------------
        // TEST 5: ISRAM ignores writes (READ_ONLY=1)
        // Try to overwrite ISRAM word 0, verify it is unchanged
        // Use icache manager for read verification (through interconnect)
        // Note: this bypasses the interconnect intentionally (ISRAM has
        // no write path from any manager) -- drive DSRAM write signals
        // directly to ISRAM ports to confirm READ_ONLY behavior
        // ---------------------------------------------------------
        $display("\n--- TEST 5: ISRAM is read-only ---");
        // Force a write attempt directly to ISRAM (interconnect doesn't
        // route writes to ISRAM, so we test the sub directly)
        force ISRAM.awvalid = 1'b1;
        force ISRAM.wvalid  = 1'b1;
        force ISRAM.awaddr  = 32'h00000000;
        force ISRAM.wdata   = 32'hFFFFFFFF;
        force ISRAM.wstrb   = 4'b1111;
        tick;   // write attempted (should be ignored by READ_ONLY=1)
        release ISRAM.awvalid;
        release ISRAM.wvalid;
        release ISRAM.awaddr;
        release ISRAM.wdata;
        release ISRAM.wstrb;

        ic_mem_re   = 1;
        ic_mem_addr = 32'h00000000;
        #1;
        check32("T5 ISRAM word 0 unchanged", ic_mem_rd, 32'h00500093);
        ic_mem_re = 0;
        tick;

        // ---------------------------------------------------------
        // TEST 6: ARREADY/AWREADY/WREADY always 1 (back-pressure check)
        // ---------------------------------------------------------
        $display("\n--- TEST 6: subordinates always ready ---");
        ic_mem_re   = 1;
        ic_mem_addr = 32'h00000008;
        dc_mem_we   = 1;
        dc_mem_addr = 32'h00000010;
        dc_mem_wd   = 32'h12345678;
        #1;
        check1("T6 ISRAM ARREADY=1", s0_arready, 1'b1);
        check1("T6 DSRAM AWREADY=1", s1_awready, 1'b1);
        check1("T6 DSRAM WREADY=1",  s1_wready,  1'b1);
        ic_mem_re = 0;
        dc_mem_we = 0;
        tick;

        // ---------------------------------------------------------
        // TEST 7: fill_wait timing model
        // Simulates the two-cycle sequence the icache uses:
        // Cycle N (fill_wait=0): present mem_re=1, mem_addr=X
        // Cycle N+1 (fill_wait=1): sample mem_rd
        // Verify mem_rd is valid at posedge N+1
        // ---------------------------------------------------------
        $display("\n--- TEST 7: fill_wait timing (icache two-cycle sequence) ---");
        // Cycle N: drive address (simulates icache registering mem_re=1)
        ic_mem_re   = 1;
        ic_mem_addr = 32'h0000000C;  // word index 3
        // mem_rd is already combinationally valid here (same as cycle N+1 visible value)
        #1;
        check1 ("T7 RVALID  at posedge N", ic_rvalid, 1'b1);
        // Simulate "posedge N+1" -- sample mem_rd
        // In real icache this happens in the always_ff block
        begin
            logic [31:0] sampled;
            sampled = ic_mem_rd;
            // word 3 of test1.hex is the 4th instruction
            // test1 line 4 = 0x00500213 (addi x4,x0,5)
            check32("T7 mem_rd valid at sample", sampled, 32'h00500213);
        end
        ic_mem_re = 0;
        tick;

        $display("\n========== AXI4-Lite fabric: %0d passed, %0d failed ==========",
                 pass_count, fail_count);
        $finish;
    end

endmodule