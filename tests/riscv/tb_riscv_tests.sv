`timescale 1ns/1ps
// Testbench: official riscv-tests (rv32ui + rv32um) on top_pipeline
//
// Compiled once and run per test with plusargs (see `make riscv-tests`):
//   vvp sim/riscv_tests.vvp +imem=<test>.imem.hex +dmem=<test>.dmem.hex [+vcd=<file>]
//
// Programs come from scripts/build_riscv_tests.sh. Each test ends by storing
// to TOHOST (tests/riscv/env/riscv_test.h): 1 = pass, (n<<1)|1 = failed in
// test case n. The store is caught in the MEM stage, before the write-back
// dcache, so the result doesn't depend on a cache flush.
//
// Lives outside tb/ so `make test-all` (which runs every tb/tb_*.sv with no
// plusargs) doesn't pick it up.

module tb_riscv_tests;

    localparam logic [31:0] TOHOST     = 32'h3FFC;
    localparam int          MAX_CYCLES = 100_000;

    logic clk, rst;

    top_pipeline #(
        .HEX_FILE        (""),
        .IMEM_DEPTH_WORDS(2048),   // 8 KB: code at 0x0000-0x1FFF
        .DMEM_DEPTH_WORDS(4096)    // 16 KB: data at 0x2000+, TOHOST at 0x3FFC
    ) cpu (
        .clk        (clk),
        .rst        (rst),
        .uart_tx_pin(),
        .uart_rx_pin(1'b1)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    string imem_file, dmem_file, vcd_file;
    int    cycles = 0;

    initial begin
        rst = 1;
        if (!$value$plusargs("imem=%s", imem_file)) begin
            $display("FAIL (no +imem=<file> given)");
            $finish;
        end
        // The SRAMs zero-fill in their own initial blocks at time 0, so load
        // after that.
        #1;
        $readmemh(imem_file, cpu.ISRAM.mem);
        if ($value$plusargs("dmem=%s", dmem_file))
            $readmemh(dmem_file, cpu.DSRAM.mem);
        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_riscv_tests);
        end
        repeat (5) @(posedge clk);
        rst = 0;
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycles <= cycles + 1;
            if (cpu.mem_mem_we && cpu.mem_alu_result == TOHOST) begin
                if (cpu.mem_rs2_data == 32'd1)
                    $display("PASS (%0d cycles)", cycles);
                else
                    $display("FAIL (test case %0d)", cpu.mem_rs2_data >> 1);
                $finish;
            end
            if (cycles == MAX_CYCLES) begin
                $display("TIMEOUT (no result after %0d cycles)", MAX_CYCLES);
                $finish;
            end
        end
    end

endmodule
