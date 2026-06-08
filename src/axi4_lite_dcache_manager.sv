// Purely combinational
// WSTRB=4'b1111 always: dcache WRITEBACK uses funct3=010 (SW), all bus
// transactions are word-wide. Sub-word stores are write-hits handled
// inside dcache and never reach the bus.

module axi4_lite_dcache_manager (
    // dcache memory interface
    input  logic        mem_we,
    input  logic        mem_re,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wd,
    output logic [31:0] mem_rd,

    // AXI4-Lite AW channel
    output logic        awvalid,
    output logic [31:0] awaddr,
    input  logic        awready,

    // AXI4-Lite W channel
    output logic        wvalid,
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    input  logic        wready,

    // AXI4-Lite B channel
    input  logic        bvalid,
    input  logic [1:0]  bresp,
    output logic        bready,

    // AXI4-Lite AR channel
    output logic        arvalid,
    output logic [31:0] araddr,
    input  logic        arready,

    // AXI4-Lite R channel
    input  logic        rvalid,
    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
    output logic        rready
);
    // Write channels
    assign awvalid = mem_we;
    assign awaddr  = mem_addr;
    assign wvalid  = mem_we;
    assign wdata   = mem_wd;
    assign wstrb   = 4'b1111;    // all cache bus accesses are word-wide
    assign bready  = 1'b1;       // always consume write response

    // Read channels
    assign arvalid = mem_re;
    assign araddr  = mem_addr;
    assign rready  = 1'b1;       // always consume read data
    assign mem_rd  = rvalid ? rdata : 32'd0;
endmodule