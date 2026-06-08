// AXI4-Lite interconnect: 2 managers, 2 subordinates
// Harvard architecture: managers access separate subordinates, no arbitration.
//
// Manager 0 (icache): read-only → always Subordinate 0 (ISRAM)
// Manager 1 (dcache): read/write → always Subordinate 1 (DSRAM)
//
// To add UART subordinate (Step 2 of AXI4-Lite expansion):
//   1. Add s2_* ports for UART sub
//   2. Add address decode: m1_aw_uart = m1_awaddr[31:16] == 16'hFFFF
//   3. Gate s1/s2 valid signals on address decode
//   4. Mux m1 ready/response from s1/s2 based on decode
//   5. Remove !is_io mask on dcache cpu_we/cpu_re in top_pipeline.sv
//   6. Handle one-cycle IO read stall

module axi4_lite_interconnect (
    // Manager 0: icache (read-only) 
    input  logic        m0_arvalid,
    output logic        m0_arready,
    input  logic [31:0] m0_araddr,
    output logic        m0_rvalid,
    input  logic        m0_rready,
    output logic [31:0] m0_rdata,
    output logic [1:0]  m0_rresp,

    // Manager 1: dcache (read/write)
    input  logic        m1_awvalid,
    output logic        m1_awready,
    input  logic [31:0] m1_awaddr,
    input  logic        m1_wvalid,
    output logic        m1_wready,
    input  logic [31:0] m1_wdata,
    input  logic [3:0]  m1_wstrb,
    output logic        m1_bvalid,
    input  logic        m1_bready,
    output logic [1:0]  m1_bresp,
    input  logic        m1_arvalid,
    output logic        m1_arready,
    input  logic [31:0] m1_araddr,
    output logic        m1_rvalid,
    input  logic        m1_rready,
    output logic [31:0] m1_rdata,
    output logic [1:0]  m1_rresp,

    //  Subordinate 0: ISRAM 
    output logic        s0_arvalid,
    input  logic        s0_arready,
    output logic [31:0] s0_araddr,
    input  logic        s0_rvalid,
    output logic        s0_rready,
    input  logic [31:0] s0_rdata,
    input  logic [1:0]  s0_rresp,

    // Subordinate 1: DSRAM 
    output logic        s1_awvalid,
    input  logic        s1_awready,
    output logic [31:0] s1_awaddr,
    output logic        s1_wvalid,
    input  logic        s1_wready,
    output logic [31:0] s1_wdata,
    output logic [3:0]  s1_wstrb,
    input  logic        s1_bvalid,
    output logic        s1_bready,
    input  logic [1:0]  s1_bresp,
    output logic        s1_arvalid,
    input  logic        s1_arready,
    output logic [31:0] s1_araddr,
    input  logic        s1_rvalid,
    output logic        s1_rready,
    input  logic [31:0] s1_rdata,
    input  logic [1:0]  s1_rresp
);
    // Manager 0 (icache) → Subordinate 0 (ISRAM): fixed, read-only
    assign s0_arvalid  = m0_arvalid;
    assign s0_araddr   = m0_araddr;
    assign s0_rready   = m0_rready;
    assign m0_arready  = s0_arready;
    assign m0_rvalid   = s0_rvalid;
    assign m0_rdata    = s0_rdata;
    assign m0_rresp    = s0_rresp;

    // Manager 1 (dcache) → Subordinate 1 (DSRAM): fixed, read/write
    assign s1_awvalid  = m1_awvalid;
    assign s1_awaddr   = m1_awaddr;
    assign s1_wvalid   = m1_wvalid;
    assign s1_wdata    = m1_wdata;
    assign s1_wstrb    = m1_wstrb;
    assign s1_bready   = m1_bready;
    assign s1_arvalid  = m1_arvalid;
    assign s1_araddr   = m1_araddr;
    assign s1_rready   = m1_rready;

    assign m1_awready  = s1_awready;
    assign m1_wready   = s1_wready;
    assign m1_bvalid   = s1_bvalid;
    assign m1_bresp    = s1_bresp;
    assign m1_arready  = s1_arready;
    assign m1_rvalid   = s1_rvalid;
    assign m1_rdata    = s1_rdata;
    assign m1_rresp    = s1_rresp;
endmodule