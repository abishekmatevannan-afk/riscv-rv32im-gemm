`timescale 1ns/1ps
// Standalone unit test for systolic_array_sub (genuine output-stationary).
// Tests: A*I baseline (11 cycles), INT32 readback + overflow saturation,
//        requantization (scale_shift + zero_point), and K-tiling accumulate mode.

module tb_systolic_array;

    logic clk, rst;

    logic        arvalid, arready; logic [31:0] araddr;
    logic        rvalid,  rready;  logic [31:0] rdata; logic [1:0] rresp;
    logic        awvalid, awready; logic [31:0] awaddr;
    logic        wvalid,  wready;  logic [31:0] wdata; logic [3:0] wstrb;
    logic        bvalid,  bready;  logic [1:0]  bresp;

    systolic_array_sub dut (
        .clk(clk), .rst(rst),
        .arvalid(arvalid), .arready(arready), .araddr(araddr),
        .rvalid(rvalid),   .rready(rready),   .rdata(rdata),   .rresp(rresp),
        .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
        .wvalid(wvalid),   .wready(wready),   .wdata(wdata),   .wstrb(wstrb),
        .bvalid(bvalid),   .bready(bready),   .bresp(bresp)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end

    task automatic axi_write(input [31:0] addr, input [31:0] data);
        awvalid = 1; awaddr = addr;
        wvalid  = 1; wdata  = data; wstrb = 4'b1111;
        @(posedge clk); #1;
        awvalid = 0; wvalid = 0;
        @(posedge clk); #1;
    endtask

    task automatic axi_read(input [31:0] addr, output [31:0] data);
        arvalid = 1; araddr = addr; rready = 1;
        @(posedge clk); #1;
        data    = rdata;
        arvalid = 0;
        @(posedge clk); #1;
    endtask

    // Poll done bit with timeout (systolic needs 11+ cycles; use generous timeout)
    task automatic poll_done(input integer timeout_cycles);
        logic [31:0] s;
        s = 0;
        for (int t = 0; t < timeout_cycles && !s[0]; t++) begin
            axi_read(32'hFFFD0004, s);
            if (!s[0]) begin @(posedge clk); #1; end
        end
        if (!s[0]) begin
            $display("FAIL: done never went high (timeout)");
            $finish;
        end
    endtask

    task automatic write_identity_B();
        axi_write(32'hFFFD0020, 32'h00000001);
        axi_write(32'hFFFD0024, 32'h00000100);
        axi_write(32'hFFFD0028, 32'h00010000);
        axi_write(32'hFFFD002C, 32'h01000000);
    endtask

    logic [31:0] rd;
    logic [7:0]  c[0:15];
    integer      errs;

    initial begin
        $display("========== SYSTOLIC ARRAY UNIT TEST (output-stationary) ==========");

        rst = 1; arvalid = 0; awvalid = 0; wvalid = 0; rready = 1; bready = 1;
        repeat(5) @(posedge clk); #1;
        rst = 0;

        // ----------------------------------------------------------------
        // TEST 1: A * I = A  (baseline correctness, 11-cycle wavefront)
        // A = [[1,2,3,4],[5,6,7,8],[1,2,3,4],[5,6,7,8]]
        // ----------------------------------------------------------------
        $display("\n--- Test 1: A*I=A baseline (11-cycle wavefront) ---");

        axi_write(32'hFFFD0010, 32'h04030201);
        axi_write(32'hFFFD0014, 32'h08070605);
        axi_write(32'hFFFD0018, 32'h04030201);
        axi_write(32'hFFFD001C, 32'h08070605);
        write_identity_B();
        axi_write(32'hFFFD0000, 32'h00000001);  // CTRL=1

        poll_done(40);

        axi_read(32'hFFFD0008, rd);
        if (rd == 11)
            $display("PASS: compute cycles = 11 (wavefront: last PE at t=10)");
        else
            $display("FAIL: expected 11 compute cycles, got %0d", rd);

        axi_read(32'hFFFD0040, rd); c[0]=rd[7:0]; c[1]=rd[15:8]; c[2]=rd[23:16]; c[3]=rd[31:24];
        axi_read(32'hFFFD0044, rd); c[4]=rd[7:0]; c[5]=rd[15:8]; c[6]=rd[23:16]; c[7]=rd[31:24];
        axi_read(32'hFFFD0048, rd); c[8]=rd[7:0]; c[9]=rd[15:8]; c[10]=rd[23:16]; c[11]=rd[31:24];
        axi_read(32'hFFFD004C, rd); c[12]=rd[7:0]; c[13]=rd[15:8]; c[14]=rd[23:16]; c[15]=rd[31:24];

        errs = 0;
        begin
            logic [7:0] exp[0:15];
            exp = '{1,2,3,4, 5,6,7,8, 1,2,3,4, 5,6,7,8};
            for (int i = 0; i < 16; i++)
                if (c[i] !== exp[i]) errs++;
        end
        if (errs == 0)
            $display("PASS: C = A (A * I = A correct)");
        else
            $display("FAIL: %0d elements wrong in A*I test", errs);

        // ----------------------------------------------------------------
        // TEST 2: INT32 readback + overflow saturation
        // A = all 100s, B = all 100s
        // C_INT32[i][j] = 4 * 100 * 100 = 40000  (overflows INT8)
        // scale_shift=0: c_row bytes = 0xFF (saturated)
        // scale_shift=9: 40000>>9 = 78 = 0x4E
        // ----------------------------------------------------------------
        $display("\n--- Test 2: INT32 readback + overflow saturation ---");

        axi_write(32'hFFFD0030, 32'h0);
        axi_write(32'hFFFD0034, 32'h0);
        axi_write(32'hFFFD0010, 32'h64646464);
        axi_write(32'hFFFD0014, 32'h64646464);
        axi_write(32'hFFFD0018, 32'h64646464);
        axi_write(32'hFFFD001C, 32'h64646464);
        axi_write(32'hFFFD0020, 32'h64646464);
        axi_write(32'hFFFD0024, 32'h64646464);
        axi_write(32'hFFFD0028, 32'h64646464);
        axi_write(32'hFFFD002C, 32'h64646464);
        axi_write(32'hFFFD0000, 32'h00000001);

        poll_done(40);

        axi_read(32'hFFFD0080, rd);
        if (rd == 32'd40000)
            $display("PASS: C_INT32[0][0] = 40000 (INT32 accumulator correct)");
        else
            $display("FAIL: C_INT32[0][0] expected 40000, got %0d", rd);

        axi_read(32'hFFFD0040, rd);
        if (rd == 32'hFFFFFFFF)
            $display("PASS: C_ROW0 = 0xFFFFFFFF (saturated to 255 with shift=0)");
        else
            $display("FAIL: C_ROW0 expected 0xFFFFFFFF, got 0x%08X", rd);

        axi_write(32'hFFFD0030, 32'h9);   // scale_shift=9
        axi_read(32'hFFFD0040, rd);
        if (rd == 32'h4E4E4E4E)
            $display("PASS: C_ROW0 = 0x4E4E4E4E (requant: 40000>>9=78)");
        else
            $display("FAIL: C_ROW0 expected 0x4E4E4E4E, got 0x%08X", rd);

        // ----------------------------------------------------------------
        // TEST 3: Requantization with zero_point
        // c_acc = 40000, scale_shift=9 → 78, zero_point=100 → 178 = 0xB2
        // ----------------------------------------------------------------
        $display("\n--- Test 3: Requantization (scale_shift=9, zero_point=100) ---");

        axi_write(32'hFFFD0034, 32'd100);
        axi_read(32'hFFFD0040, rd);
        if (rd == 32'hB2B2B2B2)
            $display("PASS: C_ROW0 = 0xB2B2B2B2 (requant: 40000>>9+100=178)");
        else
            $display("FAIL: C_ROW0 expected 0xB2B2B2B2, got 0x%08X", rd);

        axi_write(32'hFFFD0034, 32'd200);
        axi_read(32'hFFFD0040, rd);
        if (rd == 32'hFFFFFFFF)
            $display("PASS: C_ROW0 saturated to 0xFF (78+200=278>255)");
        else
            $display("FAIL: saturation failed, got 0x%08X", rd);

        // ----------------------------------------------------------------
        // TEST 4: K-tiling — two-pass 8x4 x 4x4 accumulate
        //
        // Pass 1 (normal):  A_tile1 rows=[5,6,7,8], B=I → c_acc=[5,6,7,8]
        // Pass 2 (accum):   A_tile2 rows=[1,2,3,4], B=I → c_acc+=[1,2,3,4]
        //   Result row 0: [6,8,10,12] → c_row[0]=0x0C0A0806
        // ----------------------------------------------------------------
        $display("\n--- Test 4: K-tiling accumulate (two 4-wide passes) ---");

        axi_write(32'hFFFD0030, 32'h0);
        axi_write(32'hFFFD0034, 32'h0);

        // Pass 1
        axi_write(32'hFFFD0010, 32'h08070605);
        axi_write(32'hFFFD0014, 32'h08070605);
        axi_write(32'hFFFD0018, 32'h08070605);
        axi_write(32'hFFFD001C, 32'h08070605);
        write_identity_B();
        axi_write(32'hFFFD0000, 32'h00000001);

        poll_done(40);

        axi_read(32'hFFFD0080, rd);
        if (rd == 32'd5)
            $display("PASS: after pass 1, C_INT32[0][0]=5");
        else
            $display("FAIL: after pass 1, C_INT32[0][0] expected 5, got %0d", rd);

        // Pass 2 (accumulate)
        axi_write(32'hFFFD0010, 32'h04030201);
        axi_write(32'hFFFD0014, 32'h04030201);
        axi_write(32'hFFFD0018, 32'h04030201);
        axi_write(32'hFFFD001C, 32'h04030201);
        write_identity_B();
        axi_write(32'hFFFD0000, 32'h00000003);  // CTRL=3 (start + accumulate)

        poll_done(40);

        axi_read(32'hFFFD0080, rd);
        if (rd == 32'd6)  $display("PASS: C_INT32[0][0]=6");
        else              $display("FAIL: C_INT32[0][0] expected 6, got %0d", rd);
        axi_read(32'hFFFD0084, rd);
        if (rd == 32'd8)  $display("PASS: C_INT32[0][1]=8");
        else              $display("FAIL: C_INT32[0][1] expected 8, got %0d", rd);
        axi_read(32'hFFFD0088, rd);
        if (rd == 32'd10) $display("PASS: C_INT32[0][2]=10");
        else              $display("FAIL: C_INT32[0][2] expected 10, got %0d", rd);
        axi_read(32'hFFFD008C, rd);
        if (rd == 32'd12) $display("PASS: C_INT32[0][3]=12");
        else              $display("FAIL: C_INT32[0][3] expected 12, got %0d", rd);

        axi_read(32'hFFFD0040, rd);
        if (rd == 32'h0C0A0806)
            $display("PASS: C_ROW0=0x0C0A0806 (tile-K accumulate correct)");
        else
            $display("FAIL: C_ROW0 expected 0x0C0A0806, got 0x%08X", rd);

        $display("\n========== DONE ==========");
        $finish;
    end

endmodule
