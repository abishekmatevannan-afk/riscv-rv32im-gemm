// Generates AXI4-Lite transactions for IO-mapped addresses (UART).
// Purely combinational — the UART subordinate is always-ready and
// responds in the same cycle, so no FSM or stall signal is needed.
// Reads and writes from the MEM stage are presented directly to the
// AXI channels. The pipeline timing is identical to the old direct
// uart_mem_map connection.
//
// io_active must be asserted only for true IO addresses:
//   assign io_active = is_io && !is_perf  (in top_pipeline.sv)
// This prevents PMU reads (also in the 0xFFFF range) from being
// forwarded to the UART subordinate.
 
module axi4_lite_io_manager (
    // MEM stage inputs
    input  logic        io_active,   // gated is_io: excludes PMU
    input  logic        mem_re,      // load instruction in MEM
    input  logic        mem_we,      // store instruction in MEM
    input  logic [31:0] mem_addr,    // mem_alu_result
    input  logic [31:0] mem_wdata,   // mem_rs2_data
 
    // Read data back to pipeline mux
    output logic [31:0] io_rd,
 
    // AR channel (read address)
    output logic        arvalid,
    input  logic        arready,
    output logic [31:0] araddr,
 
    // R channel (read data)
    input  logic        rvalid,
    output logic        rready,
    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
 
    // AW channel (write address)
    output logic        awvalid,
    input  logic        awready,
    output logic [31:0] awaddr,
 
    // W channel (write data)
    output logic        wvalid,
    input  logic        wready,
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
 
    // B channel (write response)
    input  logic        bvalid,
    output logic        bready
);
 
    // Read path — present address when an IO load is in MEM
    assign arvalid = io_active && mem_re;
    assign araddr  = mem_addr;
    assign rready  = 1'b1;
    assign io_rd   = rvalid ? rdata : 32'b0;
 
    // Write path — present address and data when an IO store is in MEM
    assign awvalid = io_active && mem_we;
    assign awaddr  = mem_addr;
    assign wvalid  = io_active && mem_we;
    assign wdata   = mem_wdata;
    assign wstrb   = 4'b1111;  // all bus transactions are word-wide
    assign bready  = 1'b1;
 
endmodule