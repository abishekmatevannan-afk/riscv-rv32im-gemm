// 4x4 INT8 Systolic-Style Matrix Multiply Accelerator
// AXI4-Lite subordinate at base address 0xFFFE0000
//
// Register map (offset from base):
//   0x00  CTRL    W   write 1 to start computation
//   0x04  STATUS  R   bit 0 = done
//   0x08  CYCLES  R   compute cycles (always 4 for 4x4)
//   0x10  A_ROW0  W   A[0][3:0] packed {byte3,byte2,byte1,byte0}
//   0x14  A_ROW1  W   A[1][3:0]
//   0x18  A_ROW2  W   A[2][3:0]
//   0x1C  A_ROW3  W   A[3][3:0]
//   0x20  B_ROW0  W   B^T[0][3:0] packed  (B transposed rows)
//   0x24  B_ROW1  W
//   0x28  B_ROW2  W
//   0x2C  B_ROW3  W
//   0x40  C_ROW0  R   C[0][3:0] packed {byte3,byte2,byte1,byte0}
//   0x44  C_ROW1  R
//   0x48  C_ROW2  R
//   0x4C  C_ROW3  R
//
// Operation: C = A x B  (treats B register file as B-transposed rows)
// C[i][j] = sum_k A[i][k] * B^T[j][k]
//
// All 16 PEs run in parallel. Computation takes exactly 4 clock cycles
// (one per k=0..3). Write A and B rows, write CTRL=1, poll STATUS until
// done=1, then read C rows.
//
// C output is truncated to 8 bits per element. Sufficient for small-valued
// matrices (e.g. A*I = A where values are 1-8).

module systolic_array_sub (
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

    // A and B register files (packed INT8 rows)
    logic [31:0] a_reg [0:3];
    logic [31:0] b_reg [0:3];

    // PE accumulator array: c_acc[row][col] = C[row][col] (32-bit)
    logic [31:0] c_acc [0:3][0:3];

    // Control registers
    logic        done;
    logic [31:0] cycles;
    logic [31:0] cycle_ctr;

    // FSM
    logic        running;
    logic [1:0]  k;          // current k index (0..3)

    // Unpack A and B bytes to avoid variable bit-select in always_ff
    // a_byte[row][col] = A[row][col] as 8-bit value
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

    // Pack C accumulator low bytes into output rows
    logic [31:0] c_row [0:3];
    generate
        genvar gr;
        for (gr = 0; gr < 4; gr++) begin : pack_c
            assign c_row[gr] = {c_acc[gr][3][7:0], c_acc[gr][2][7:0],
                                c_acc[gr][1][7:0], c_acc[gr][0][7:0]};
        end
    endgenerate

    // AXI read: combinational, always-ready
    assign arready = 1'b1;
    assign rvalid  = arvalid;
    assign rresp   = 2'b00;

    assign rdata = (araddr[7:0] == 8'h04) ? {31'd0, done} :
                   (araddr[7:0] == 8'h08) ? cycles        :
                   (araddr[7:0] == 8'h40) ? c_row[0]      :
                   (araddr[7:0] == 8'h44) ? c_row[1]      :
                   (araddr[7:0] == 8'h48) ? c_row[2]      :
                   (araddr[7:0] == 8'h4C) ? c_row[3]      :
                                            32'd0;

    // AXI write: always-ready, synchronous commit
    assign awready = 1'b1;
    assign wready  = 1'b1;
    assign bvalid  = awvalid && wvalid;
    assign bresp   = 2'b00;

    // Main sequential logic: write handling + PE array FSM
    always_ff @(posedge clk) begin
        if (rst) begin
            running   <= 0;
            done      <= 0;
            k         <= 0;
            cycles    <= 0;
            cycle_ctr <= 0;
            for (int i = 0; i < 4; i++) begin
                a_reg[i] <= 0;
                b_reg[i] <= 0;
                for (int j = 0; j < 4; j++)
                    c_acc[i][j] <= 0;
            end
        end else begin

            // Write path
            if (awvalid && wvalid) begin
                case (awaddr[7:0])
                    8'h00: if (wdata[0]) begin   // CTRL: start (always accepted)
                        for (int i = 0; i < 4; i++)
                            for (int j = 0; j < 4; j++)
                                c_acc[i][j] <= 0;
                        done      <= 0;
                        k         <= 0;
                        cycle_ctr <= 0;
                        running   <= 1;
                    end
                    // A/B writes locked out while running to prevent mid-compute corruption
                    8'h10: if (!running) a_reg[0] <= wdata;
                    8'h14: if (!running) a_reg[1] <= wdata;
                    8'h18: if (!running) a_reg[2] <= wdata;
                    8'h1C: if (!running) a_reg[3] <= wdata;
                    8'h20: if (!running) b_reg[0] <= wdata;
                    8'h24: if (!running) b_reg[1] <= wdata;
                    8'h28: if (!running) b_reg[2] <= wdata;
                    8'h2C: if (!running) b_reg[3] <= wdata;
                    default: ;
                endcase
            end

            // PE array FSM
            if (running) begin
                cycle_ctr <= cycle_ctr + 1;

                // All 16 PEs compute in parallel for this k
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        c_acc[i][j] <= c_acc[i][j] +
                            ({24'd0, a_byte[i][k]} * {24'd0, b_byte[j][k]});

                if (k == 2'd3) begin
                    cycles  <= cycle_ctr + 1;  // latch compute cycle count
                    done    <= 1;
                    running <= 0;
                end else begin
                    k <= k + 1;
                end
            end
        end
    end

endmodule