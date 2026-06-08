// Purely combinational -- ARVALID follows mem_re directly
// Requires subordinate: ARREADY=1 always, RVALID=ARVALID (same cycle)
// Timing: mem_re registered in icache, valid at posedge N
//         RDATA combinationally available [posedge N .. posedge N+1]
//         icache latches mem_rd at posedge N+1 (fill_wait=1) -- correct

module axi4_lite_icache_manager (
    // icache memory interface
    input  logic        mem_re,
    input  logic [31:0] mem_addr,
    output logic [31:0] mem_rd,

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
    assign arvalid = mem_re;
    assign araddr  = mem_addr;
    assign rready  = 1'b1;       // always consume read data
    assign mem_rd  = rvalid ? rdata : 32'd0;
endmodule