// Word-organized: DEPTH_WORDS x 32-bit words
// ARREADY=AWREADY=WREADY=1 always (never stalls)
// Read response is combinational: RVALID=ARVALID, RDATA available same cycle
// Write commits synchronously at posedge clk using WSTRB byte enables
// BVALID is combinational (=AWVALID&&WVALID)
//
// Parameters:
//   DEPTH_WORDS: number of 32-bit words (256 = 1KB)
//   HEX_FILE:   optional $readmemh initialization (for instruction SRAM)
//   READ_ONLY:  1 = ignore writes (for instruction SRAM)

module axi4_lite_sram_sub #(
    parameter DEPTH_WORDS = 256,
    parameter HEX_FILE    = "",
    parameter READ_ONLY   = 0
)(
    input  logic        clk,
    input  logic        rst,

    // AR channel
    input  logic        arvalid,
    output logic        arready,
    input  logic [31:0] araddr,

    // R channel
    output logic        rvalid,
    input  logic        rready,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,

    // AW channel
    input  logic        awvalid,
    output logic        awready,
    input  logic [31:0] awaddr,

    // W channel
    input  logic        wvalid,
    output logic        wready,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,

    // B channel
    output logic        bvalid,
    input  logic        bready,
    output logic [1:0]  bresp
);
    localparam AW = $clog2(DEPTH_WORDS);  // address bits for word index

    logic [31:0] mem [0:DEPTH_WORDS-1];

    // Memory initialization: $readmemh is synthesizable for Xilinx BRAM init.
    // Zero-init is the default for uninitialized BRAM entries.
    integer fi;
    initial begin
        for (fi = 0; fi < DEPTH_WORDS; fi++)
            mem[fi] = 32'd0;
        if (HEX_FILE != "")
            $readmemh(HEX_FILE, mem);
    end

    // Read: always ready, combinational response
    // RDATA is the word at byte-address ARADDR, word-indexed as ARADDR[AW+1:2]
    assign arready = 1'b1;
    assign rvalid  = arvalid;
    assign rdata   = mem[araddr[AW+1:2]];
    assign rresp   = 2'b00;  // OKAY

    // Write: always ready, synchronous byte-enable commit
    assign awready = 1'b1;
    assign wready  = 1'b1;
    assign bvalid  = awvalid && wvalid;
    assign bresp   = 2'b00;  // OKAY

    always_ff @(posedge clk) begin
        if (!READ_ONLY && awvalid && wvalid) begin
            if (wstrb[0]) mem[awaddr[AW+1:2]][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) mem[awaddr[AW+1:2]][15: 8] <= wdata[15: 8];
            if (wstrb[2]) mem[awaddr[AW+1:2]][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[awaddr[AW+1:2]][31:24] <= wdata[31:24];
        end
    end
endmodule