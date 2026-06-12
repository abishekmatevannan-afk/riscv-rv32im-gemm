// 4x4 INT8 Parallel MAC Matrix Multiply Accelerator
// AXI4-Lite subordinate at base address 0xFFFE0000
//
// Register map (offset from base):
//   0x00  CTRL        W   [0]=start, [1]=accumulate (skip clearing c_acc on start)
//   0x04  STATUS      R   bit 0 = done
//   0x08  CYCLES      R   compute cycles (always 4 for 4x4)
//   0x10  A_ROW0      W   A[0][3:0] packed {byte3,byte2,byte1,byte0}
//   0x14  A_ROW1      W
//   0x18  A_ROW2      W
//   0x1C  A_ROW3      W
//   0x20  B_ROW0      W   B^T[0][3:0] packed  (B stored transposed)
//   0x24  B_ROW1      W
//   0x28  B_ROW2      W
//   0x2C  B_ROW3      W
//   0x30  SCALE_SHIFT W   [4:0] right-shift applied to c_acc before packing (default 0)
//   0x34  ZERO_POINT  W   [7:0] additive offset after shift, before saturation (default 0)
//   0x40  C_ROW0      R   C[0][3:0] packed: each byte = saturate8(c_acc>>shift + zp)
//   0x44  C_ROW1      R
//   0x48  C_ROW2      R
//   0x4C  C_ROW3      R
//   0x80-0xBC  C_INT32[r][c]  R  raw 32-bit c_acc: addr = 0x80 + r*0x10 + c*4
//
// Operation: C[i][j] = sum_k A[i][k] * B^T[j][k]  (all 16 PEs parallel)
//
// Accumulate mode (CTRL[1]=1): c_acc is not cleared on start, enabling
//   tile-K accumulation — e.g. feed an 8x4 A matrix in two 4x4 passes.
// Requantization: c_row byte = saturate8((c_acc >> scale_shift) + zero_point)
// INT32 readback: c_acc[r][c] available at 0x80+r*16+c*4 for diagnostic use.

module parallel_mac_sub (
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

    logic [31:0] a_reg [0:3];
    logic [31:0] b_reg [0:3];

    // 32-bit accumulators: wide enough for sum of 4 products of 8-bit inputs
    logic [31:0] c_acc [0:3][0:3];

    logic        done;
    logic [31:0] cycles;
    logic [31:0] cycle_ctr;
    logic        running;
    logic [1:0]  k;

    logic [4:0]  scale_shift;
    logic [7:0]  zero_point;

    // Unpack A and B bytes to avoid variable bit-select in always_ff
    logic [7:0] a_byte [0:3][0:3];
    logic [7:0] b_byte [0:3][0:3];

    generate
        genvar gi;
        for (gi = 0; gi < 4; gi++) begin : unpack
            assign a_byte[gi][0] = a_reg[gi][ 7: 0];
            assign a_byte[gi][1] = a_reg[gi][15: 8];
            assign a_byte[gi][2] = a_reg[gi][23:16];
            assign a_byte[gi][3] = a_reg[gi][31:24];
            assign b_byte[gi][0] = b_reg[gi][ 7: 0];
            assign b_byte[gi][1] = b_reg[gi][15: 8];
            assign b_byte[gi][2] = b_reg[gi][23:16];
            assign b_byte[gi][3] = b_reg[gi][31:24];
        end
    endgenerate

    // Shift, add zero_point, saturate to [0, 255]
    function automatic [7:0] do_requant(
        input [31:0] acc,
        input [4:0]  sshift,
        input [7:0]  zp
    );
        logic [32:0] s;
        s = {1'b0, (acc >> sshift)} + {25'd0, zp};
        do_requant = (|s[32:8]) ? 8'hFF : s[7:0];
    endfunction

    logic [31:0] c_row [0:3];
    always_comb begin
        for (int i = 0; i < 4; i++)
            c_row[i] = {do_requant(c_acc[i][3], scale_shift, zero_point),
                        do_requant(c_acc[i][2], scale_shift, zero_point),
                        do_requant(c_acc[i][1], scale_shift, zero_point),
                        do_requant(c_acc[i][0], scale_shift, zero_point)};
    end

    assign arready = 1'b1;
    assign rvalid  = arvalid;
    assign rresp   = 2'b00;

    always_comb begin
        case (araddr[7:0])
            8'h04: rdata = {31'd0, done};
            8'h08: rdata = cycles;
            8'h40: rdata = c_row[0];
            8'h44: rdata = c_row[1];
            8'h48: rdata = c_row[2];
            8'h4C: rdata = c_row[3];
            8'h80: rdata = c_acc[0][0];
            8'h84: rdata = c_acc[0][1];
            8'h88: rdata = c_acc[0][2];
            8'h8C: rdata = c_acc[0][3];
            8'h90: rdata = c_acc[1][0];
            8'h94: rdata = c_acc[1][1];
            8'h98: rdata = c_acc[1][2];
            8'h9C: rdata = c_acc[1][3];
            8'hA0: rdata = c_acc[2][0];
            8'hA4: rdata = c_acc[2][1];
            8'hA8: rdata = c_acc[2][2];
            8'hAC: rdata = c_acc[2][3];
            8'hB0: rdata = c_acc[3][0];
            8'hB4: rdata = c_acc[3][1];
            8'hB8: rdata = c_acc[3][2];
            8'hBC: rdata = c_acc[3][3];
            default: rdata = 32'd0;
        endcase
    end

    assign awready = 1'b1;
    assign wready  = 1'b1;
    assign bvalid  = awvalid && wvalid;
    assign bresp   = 2'b00;

    always_ff @(posedge clk) begin
        if (rst) begin
            running     <= 0;
            done        <= 0;
            k           <= 0;
            cycles      <= 0;
            cycle_ctr   <= 0;
            scale_shift <= 0;
            zero_point  <= 0;
            for (int i = 0; i < 4; i++) begin
                a_reg[i] <= 0;
                b_reg[i] <= 0;
                for (int j = 0; j < 4; j++)
                    c_acc[i][j] <= 0;
            end
        end else begin

            if (awvalid && wvalid) begin
                case (awaddr[7:0])
                    8'h00: if (wdata[0]) begin
                        if (!wdata[1])               // normal mode: clear accumulator
                            for (int i = 0; i < 4; i++)
                                for (int j = 0; j < 4; j++)
                                    c_acc[i][j] <= 0;
                        // accumulate mode (bit 1 set): c_acc preserved across passes
                        done      <= 0;
                        k         <= 0;
                        cycle_ctr <= 0;
                        running   <= 1;
                    end
                    8'h10: if (!running) a_reg[0] <= wdata;
                    8'h14: if (!running) a_reg[1] <= wdata;
                    8'h18: if (!running) a_reg[2] <= wdata;
                    8'h1C: if (!running) a_reg[3] <= wdata;
                    8'h20: if (!running) b_reg[0] <= wdata;
                    8'h24: if (!running) b_reg[1] <= wdata;
                    8'h28: if (!running) b_reg[2] <= wdata;
                    8'h2C: if (!running) b_reg[3] <= wdata;
                    8'h30: scale_shift <= wdata[4:0];
                    8'h34: zero_point  <= wdata[7:0];
                    default: ;
                endcase
            end

            if (running) begin
                cycle_ctr <= cycle_ctr + 1;
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        c_acc[i][j] <= c_acc[i][j] +
                            ({24'd0, a_byte[i][k]} * {24'd0, b_byte[j][k]});
                if (k == 2'd3) begin
                    cycles  <= cycle_ctr + 1;
                    done    <= 1;
                    running <= 0;
                end else begin
                    k <= k + 1;
                end
            end
        end
    end

endmodule
