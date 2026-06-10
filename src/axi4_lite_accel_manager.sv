// Generates AXI4-Lite transactions for accelerator-mapped addresses (0xFFFE....).
// Purely combinational — identical in structure to axi4_lite_io_manager.sv
// but triggered by is_accel instead of is_uart.
// accel_active = is_accel (computed in top_pipeline from mem_alu_result[31:16]==0xFFFE)
 
module axi4_lite_accel_manager (
    // MEM stage inputs
    input  logic        accel_active,  // (mem_alu_result[31:16] == 16'hFFFE)
    input  logic        mem_re,
    input  logic        mem_we,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
 
    // Read data back to pipeline mux
    output logic [31:0] accel_rd,
 
    // AXI4-Lite AR channel
    output logic        arvalid,
    input  logic        arready,
    output logic [31:0] araddr,
    // R channel
    input  logic        rvalid,
    output logic        rready,
    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
    // AW channel
    output logic        awvalid,
    input  logic        awready,
    output logic [31:0] awaddr,
    // W channel
    output logic        wvalid,
    input  logic        wready,
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    // B channel
    input  logic        bvalid,
    output logic        bready
);
    assign arvalid   = accel_active && mem_re;
    assign araddr    = mem_addr;
    assign rready    = 1'b1;
    assign accel_rd  = rvalid ? rdata : 32'b0;
 
    assign awvalid   = accel_active && mem_we;
    assign awaddr    = mem_addr;
    assign wvalid    = accel_active && mem_we;
    assign wdata     = mem_wdata;
    assign wstrb     = 4'b1111;
    assign bready    = 1'b1;
endmodule