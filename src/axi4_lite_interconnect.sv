// AXI4-Lite interconnect: 5 managers, 5 subordinates
// Harvard architecture: each manager has a dedicated subordinate.
// No arbitration needed — no two managers share a subordinate.
//
// Manager 0 (icache):           read-only  → Subordinate 0 (ISRAM)
// Manager 1 (dcache):           read/write → Subordinate 1 (DSRAM)
// Manager 2 (IO manager):       read/write → Subordinate 2 (UART)
// Manager 3 (accel manager):    read/write → Subordinate 3 (Parallel MAC, 0xFFFE....)
// Manager 4 (systolic manager): read/write → Subordinate 4 (Systolic array, 0xFFFD....)

module axi4_lite_interconnect (

    // ── Manager 0: icache (read-only) ────────────────────────────────────
    input  logic        m0_arvalid, output logic        m0_arready,
    input  logic [31:0] m0_araddr,
    output logic        m0_rvalid,  input  logic        m0_rready,
    output logic [31:0] m0_rdata,   output logic [1:0]  m0_rresp,

    // ── Manager 1: dcache (read/write) ───────────────────────────────────
    input  logic        m1_awvalid, output logic        m1_awready,
    input  logic [31:0] m1_awaddr,
    input  logic        m1_wvalid,  output logic        m1_wready,
    input  logic [31:0] m1_wdata,   input  logic [3:0]  m1_wstrb,
    output logic        m1_bvalid,  input  logic        m1_bready,
    output logic [1:0]  m1_bresp,
    input  logic        m1_arvalid, output logic        m1_arready,
    input  logic [31:0] m1_araddr,
    output logic        m1_rvalid,  input  logic        m1_rready,
    output logic [31:0] m1_rdata,   output logic [1:0]  m1_rresp,

    // ── Manager 2: IO manager (read/write) ───────────────────────────────
    input  logic        m2_awvalid, output logic        m2_awready,
    input  logic [31:0] m2_awaddr,
    input  logic        m2_wvalid,  output logic        m2_wready,
    input  logic [31:0] m2_wdata,   input  logic [3:0]  m2_wstrb,
    output logic        m2_bvalid,  input  logic        m2_bready,
    output logic [1:0]  m2_bresp,
    input  logic        m2_arvalid, output logic        m2_arready,
    input  logic [31:0] m2_araddr,
    output logic        m2_rvalid,  input  logic        m2_rready,
    output logic [31:0] m2_rdata,   output logic [1:0]  m2_rresp,

    // ── Manager 3: accel manager (read/write) ────────────────────────────
    input  logic        m3_awvalid, output logic        m3_awready,
    input  logic [31:0] m3_awaddr,
    input  logic        m3_wvalid,  output logic        m3_wready,
    input  logic [31:0] m3_wdata,   input  logic [3:0]  m3_wstrb,
    output logic        m3_bvalid,  input  logic        m3_bready,
    output logic [1:0]  m3_bresp,
    input  logic        m3_arvalid, output logic        m3_arready,
    input  logic [31:0] m3_araddr,
    output logic        m3_rvalid,  input  logic        m3_rready,
    output logic [31:0] m3_rdata,   output logic [1:0]  m3_rresp,

    // ── Subordinate 0: ISRAM (read-only) ─────────────────────────────────
    output logic        s0_arvalid, input  logic        s0_arready,
    output logic [31:0] s0_araddr,
    input  logic        s0_rvalid,  output logic        s0_rready,
    input  logic [31:0] s0_rdata,   input  logic [1:0]  s0_rresp,

    // ── Subordinate 1: DSRAM (read/write) ────────────────────────────────
    output logic        s1_awvalid, input  logic        s1_awready,
    output logic [31:0] s1_awaddr,
    output logic        s1_wvalid,  input  logic        s1_wready,
    output logic [31:0] s1_wdata,   output logic [3:0]  s1_wstrb,
    input  logic        s1_bvalid,  output logic        s1_bready,
    input  logic [1:0]  s1_bresp,
    output logic        s1_arvalid, input  logic        s1_arready,
    output logic [31:0] s1_araddr,
    input  logic        s1_rvalid,  output logic        s1_rready,
    input  logic [31:0] s1_rdata,   input  logic [1:0]  s1_rresp,

    // ── Subordinate 2: UART (read/write) ─────────────────────────────────
    output logic        s2_awvalid, input  logic        s2_awready,
    output logic [31:0] s2_awaddr,
    output logic        s2_wvalid,  input  logic        s2_wready,
    output logic [31:0] s2_wdata,   output logic [3:0]  s2_wstrb,
    input  logic        s2_bvalid,  output logic        s2_bready,
    input  logic [1:0]  s2_bresp,
    output logic        s2_arvalid, input  logic        s2_arready,
    output logic [31:0] s2_araddr,
    input  logic        s2_rvalid,  output logic        s2_rready,
    input  logic [31:0] s2_rdata,   input  logic [1:0]  s2_rresp,

    // ── Manager 4: systolic manager (read/write) ─────────────────────────
    input  logic        m4_awvalid, output logic        m4_awready,
    input  logic [31:0] m4_awaddr,
    input  logic        m4_wvalid,  output logic        m4_wready,
    input  logic [31:0] m4_wdata,   input  logic [3:0]  m4_wstrb,
    output logic        m4_bvalid,  input  logic        m4_bready,
    output logic [1:0]  m4_bresp,
    input  logic        m4_arvalid, output logic        m4_arready,
    input  logic [31:0] m4_araddr,
    output logic        m4_rvalid,  input  logic        m4_rready,
    output logic [31:0] m4_rdata,   output logic [1:0]  m4_rresp,

    // ── Subordinate 3: Parallel MAC (read/write) ─────────────────────────
    output logic        s3_awvalid, input  logic        s3_awready,
    output logic [31:0] s3_awaddr,
    output logic        s3_wvalid,  input  logic        s3_wready,
    output logic [31:0] s3_wdata,   output logic [3:0]  s3_wstrb,
    input  logic        s3_bvalid,  output logic        s3_bready,
    input  logic [1:0]  s3_bresp,
    output logic        s3_arvalid, input  logic        s3_arready,
    output logic [31:0] s3_araddr,
    input  logic        s3_rvalid,  output logic        s3_rready,
    input  logic [31:0] s3_rdata,   input  logic [1:0]  s3_rresp,

    // ── Subordinate 4: Systolic array (read/write) ───────────────────────
    output logic        s4_awvalid, input  logic        s4_awready,
    output logic [31:0] s4_awaddr,
    output logic        s4_wvalid,  input  logic        s4_wready,
    output logic [31:0] s4_wdata,   output logic [3:0]  s4_wstrb,
    input  logic        s4_bvalid,  output logic        s4_bready,
    input  logic [1:0]  s4_bresp,
    output logic        s4_arvalid, input  logic        s4_arready,
    output logic [31:0] s4_araddr,
    input  logic        s4_rvalid,  output logic        s4_rready,
    input  logic [31:0] s4_rdata,   input  logic [1:0]  s4_rresp
);

    // M0 → S0
    assign s0_arvalid=m0_arvalid; assign s0_araddr=m0_araddr; assign s0_rready=m0_rready;
    assign m0_arready=s0_arready; assign m0_rvalid=s0_rvalid; assign m0_rdata=s0_rdata; assign m0_rresp=s0_rresp;

    // M1 → S1
    assign s1_awvalid=m1_awvalid; assign s1_awaddr=m1_awaddr; assign s1_wvalid=m1_wvalid;
    assign s1_wdata=m1_wdata; assign s1_wstrb=m1_wstrb; assign s1_bready=m1_bready;
    assign s1_arvalid=m1_arvalid; assign s1_araddr=m1_araddr; assign s1_rready=m1_rready;
    assign m1_awready=s1_awready; assign m1_wready=s1_wready; assign m1_bvalid=s1_bvalid;
    assign m1_bresp=s1_bresp; assign m1_arready=s1_arready; assign m1_rvalid=s1_rvalid;
    assign m1_rdata=s1_rdata; assign m1_rresp=s1_rresp;

    // M2 → S2
    assign s2_awvalid=m2_awvalid; assign s2_awaddr=m2_awaddr; assign s2_wvalid=m2_wvalid;
    assign s2_wdata=m2_wdata; assign s2_wstrb=m2_wstrb; assign s2_bready=m2_bready;
    assign s2_arvalid=m2_arvalid; assign s2_araddr=m2_araddr; assign s2_rready=m2_rready;
    assign m2_awready=s2_awready; assign m2_wready=s2_wready; assign m2_bvalid=s2_bvalid;
    assign m2_bresp=s2_bresp; assign m2_arready=s2_arready; assign m2_rvalid=s2_rvalid;
    assign m2_rdata=s2_rdata; assign m2_rresp=s2_rresp;

    // M3 → S3
    assign s3_awvalid=m3_awvalid; assign s3_awaddr=m3_awaddr; assign s3_wvalid=m3_wvalid;
    assign s3_wdata=m3_wdata; assign s3_wstrb=m3_wstrb; assign s3_bready=m3_bready;
    assign s3_arvalid=m3_arvalid; assign s3_araddr=m3_araddr; assign s3_rready=m3_rready;
    assign m3_awready=s3_awready; assign m3_wready=s3_wready; assign m3_bvalid=s3_bvalid;
    assign m3_bresp=s3_bresp; assign m3_arready=s3_arready; assign m3_rvalid=s3_rvalid;
    assign m3_rdata=s3_rdata; assign m3_rresp=s3_rresp;

    // M4 → S4
    assign s4_awvalid=m4_awvalid; assign s4_awaddr=m4_awaddr; assign s4_wvalid=m4_wvalid;
    assign s4_wdata=m4_wdata; assign s4_wstrb=m4_wstrb; assign s4_bready=m4_bready;
    assign s4_arvalid=m4_arvalid; assign s4_araddr=m4_araddr; assign s4_rready=m4_rready;
    assign m4_awready=s4_awready; assign m4_wready=s4_wready; assign m4_bvalid=s4_bvalid;
    assign m4_bresp=s4_bresp; assign m4_arready=s4_arready; assign m4_rvalid=s4_rvalid;
    assign m4_rdata=s4_rdata; assign m4_rresp=s4_rresp;

endmodule