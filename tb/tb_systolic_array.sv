`timescale 1ns/1ps
// Standalone unit test for systolic_array_sub.
// Writes a 4x4 identity matrix multiply (A * I = A) via AXI4-Lite,
// polls done, reads C, verifies C == A.

module tb_systolic_array;

    logic clk, rst;

    // AXI signals
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
        $dumpfile("sim/tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end

    // AXI write helper
    task automatic axi_write(input [31:0] addr, input [31:0] data);
        awvalid = 1; awaddr = addr;
        wvalid  = 1; wdata  = data; wstrb = 4'b1111;
        @(posedge clk); #1;
        awvalid = 0; wvalid = 0;
        @(posedge clk); #1;
    endtask

    // AXI read helper
    task automatic axi_read(input [31:0] addr, output [31:0] data);
        arvalid = 1; araddr = addr; rready = 1;
        @(posedge clk); #1;
        data    = rdata;
        arvalid = 0;
        @(posedge clk); #1;
    endtask

    logic [31:0] rd;
    logic [7:0]  c[0:15];
    logic [7:0]  expected[0:15];
    integer      errs;

    initial begin
        $display("========== SYSTOLIC ARRAY UNIT TEST ==========");

        // A = [[1,2,3,4],[5,6,7,8],[1,2,3,4],[5,6,7,8]]
        // B = I (identity, stored as B-transposed rows)
        // Expected C = A * I = A

        rst = 1; arvalid = 0; awvalid = 0; wvalid = 0; rready = 1; bready = 1;
        repeat(5) @(posedge clk); #1;
        rst = 0;

        // Write A rows (packed {byte3,byte2,byte1,byte0})
        axi_write(32'hFFFE0010, 32'h04030201);  // A_ROW0 [4,3,2,1]
        axi_write(32'hFFFE0014, 32'h08070605);  // A_ROW1 [8,7,6,5]
        axi_write(32'hFFFE0018, 32'h04030201);  // A_ROW2
        axi_write(32'hFFFE001C, 32'h08070605);  // A_ROW3

        // Write B rows (B transposed, identity → same as B)
        axi_write(32'hFFFE0020, 32'h00000001);  // B_ROW0 [0,0,0,1]
        axi_write(32'hFFFE0024, 32'h00000100);  // B_ROW1
        axi_write(32'hFFFE0028, 32'h00010000);  // B_ROW2
        axi_write(32'hFFFE002C, 32'h01000000);  // B_ROW3

        // Start
        axi_write(32'hFFFE0000, 32'h00000001);  // CTRL = 1

        // Poll STATUS until done
        repeat(10) begin
            axi_read(32'hFFFE0004, rd);
            if (rd[0]) disable fork;
            @(posedge clk); #1;
        end
        axi_read(32'hFFFE0004, rd);
        if (!rd[0]) begin
            $display("FAIL: done never went high");
            $finish;
        end

        // Read cycle count
        axi_read(32'hFFFE0008, rd);
        $display("  Accelerator compute cycles = %0d", rd);
        if (rd == 4)
            $display("PASS: compute cycles = 4 (one per k)");
        else
            $display("FAIL: expected 4 compute cycles, got %0d", rd);

        // Read C rows
        axi_read(32'hFFFE0040, rd);
        c[0]=rd[7:0]; c[1]=rd[15:8]; c[2]=rd[23:16]; c[3]=rd[31:24];
        axi_read(32'hFFFE0044, rd);
        c[4]=rd[7:0]; c[5]=rd[15:8]; c[6]=rd[23:16]; c[7]=rd[31:24];
        axi_read(32'hFFFE0048, rd);
        c[8]=rd[7:0]; c[9]=rd[15:8]; c[10]=rd[23:16]; c[11]=rd[31:24];
        axi_read(32'hFFFE004C, rd);
        c[12]=rd[7:0]; c[13]=rd[15:8]; c[14]=rd[23:16]; c[15]=rd[31:24];

        $display("  C matrix:");
        for (int r = 0; r < 4; r++) begin
            $write("    row%0d: [", r);
            for (int col = 0; col < 4; col++) $write(" %0d", c[r*4+col]);
            $display(" ]");
        end

        // Verify C = A
        expected = '{1,2,3,4, 5,6,7,8, 1,2,3,4, 5,6,7,8};
        errs = 0;
        for (int i = 0; i < 16; i++)
            if (c[i] !== expected[i]) errs++;
        if (errs == 0)
            $display("PASS: C = A (A * I = A correct)");
        else
            $display("FAIL: %0d elements wrong", errs);

        $display("========== DONE ==========");
        $finish;
    end

endmodule