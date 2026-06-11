// Output-stationary systolic array accelerator
// AXI4-Lite subordinate at base address 0xFFFD0000
//
// Architecture: Kung-Leiserson output-stationary wavefront.
//   A values shift RIGHT across PE rows  (j increases).
//   B values shift DOWN  across PE cols  (i increases).
//   Each PE[i][j] accumulates C[i][j] in place.
//
// Correctness: PE[i][j] receives A[i][k] and B[k][j] at cycle t = i+j+1+k.
//   For k=0..3, this spans t = i+j+1 .. i+j+4.
//   The last PE (i=3,j=3) finishes at t=10. Total compute = 11 cycles.
//
// Register map (offset from base, identical to parallel_mac_sub):
//   0x00  CTRL    W   write 1 to start
//   0x04  STATUS  R   bit 0 = done
//   0x08  CYCLES  R   compute cycles (reads 11)
//   0x10  A_ROW0  W   A[0][3:0] packed {byte3,byte2,byte1,byte0}
//   0x14  A_ROW1  W
//   0x18  A_ROW2  W
//   0x1C  A_ROW3  W
//   0x20  B_ROW0  W   B^T[0][3:0] packed (B stored transposed)
//   0x24  B_ROW1  W
//   0x28  B_ROW2  W
//   0x2C  B_ROW3  W
//   0x40  C_ROW0  R   C[0][3:0] packed {byte3,byte2,byte1,byte0}
//   0x44  C_ROW1  R
//   0x48  C_ROW2  R
//   0x4C  C_ROW3  R

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

    // Loaded A and B rows (packed INT8)
    logic [31:0] a_reg [0:3];
    logic [31:0] b_reg [0:3];

    // Unpacked bytes: a_byte[i][k] = A[i][k], b_byte[j][k] = B^T[j][k] = B[k][j]
    logic [7:0] a_byte [0:3][0:3];
    logic [7:0] b_byte [0:3][0:3];

    generate
        genvar gu;
        for (gu = 0; gu < 4; gu++) begin : unpack
            assign a_byte[gu][0] = a_reg[gu][ 7: 0];
            assign a_byte[gu][1] = a_reg[gu][15: 8];
            assign a_byte[gu][2] = a_reg[gu][23:16];
            assign a_byte[gu][3] = a_reg[gu][31:24];
            assign b_byte[gu][0] = b_reg[gu][ 7: 0];
            assign b_byte[gu][1] = b_reg[gu][15: 8];
            assign b_byte[gu][2] = b_reg[gu][23:16];
            assign b_byte[gu][3] = b_reg[gu][31:24];
        end
    endgenerate

    // Wavefront feed signals: skewed input to PE array
    // a_feed[i] = a_byte[i][t-i] when 0 <= (t-i) <= 3, else 0
    // b_feed[j] = b_byte[j][t-j] when 0 <= (t-j) <= 3, else 0
    logic [7:0] a_feed [0:3];
    logic [7:0] b_feed [0:3];

    logic [3:0] cycle_counter;  // 0..10 during RUNNING
    logic       running;

    generate
        genvar gf;
        for (gf = 0; gf < 4; gf++) begin : feed_gen
            always_comb begin
                if (cycle_counter >= 4'(gf) && (cycle_counter - 4'(gf)) <= 4'd3)
                    a_feed[gf] = a_byte[gf][cycle_counter - 4'(gf)];
                else
                    a_feed[gf] = 8'd0;
            end
        end
    endgenerate

    generate
        genvar gh;
        for (gh = 0; gh < 4; gh++) begin : bfeed_gen
            always_comb begin
                if (cycle_counter >= 4'(gh) && (cycle_counter - 4'(gh)) <= 4'd3)
                    b_feed[gh] = b_byte[gh][cycle_counter - 4'(gh)];
                else
                    b_feed[gh] = 8'd0;
            end
        end
    endgenerate

    // PE shift registers: A shifts right (j increases), B shifts down (i increases)
    logic [7:0]  a_pe  [0:3][0:3];   // a_pe[row][col]
    logic [7:0]  b_pe  [0:3][0:3];   // b_pe[row][col]

    // Output accumulators (32-bit to avoid overflow)
    logic [31:0] c_acc [0:3][0:3];

    // Control state
    logic        done;
    logic [31:0] cycles;

    // Pack C output rows
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

    // AXI write: always-ready
    assign awready = 1'b1;
    assign wready  = 1'b1;
    assign bvalid  = awvalid && wvalid;
    assign bresp   = 2'b00;

    // Main sequential logic
    always_ff @(posedge clk) begin
        if (rst) begin
            running       <= 0;
            done          <= 0;
            cycles        <= 0;
            cycle_counter <= 0;
            for (int i = 0; i < 4; i++) begin
                a_reg[i] <= 0;
                b_reg[i] <= 0;
                for (int j = 0; j < 4; j++) begin
                    a_pe[i][j]  <= 0;
                    b_pe[i][j]  <= 0;
                    c_acc[i][j] <= 0;
                end
            end
        end else begin

            // AXI write path
            if (awvalid && wvalid) begin
                case (awaddr[7:0])
                    8'h00: if (wdata[0]) begin
                        for (int i = 0; i < 4; i++)
                            for (int j = 0; j < 4; j++) begin
                                c_acc[i][j] <= 0;
                                a_pe[i][j]  <= 0;
                                b_pe[i][j]  <= 0;
                            end
                        done          <= 0;
                        cycle_counter <= 0;
                        running       <= 1;
                    end
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

            // Systolic wavefront FSM
            if (running) begin
                // 1. Accumulate using OLD a_pe / b_pe values (non-blocking semantics)
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        c_acc[i][j] <= c_acc[i][j] +
                            ({24'd0, a_pe[i][j]} * {24'd0, b_pe[i][j]});

                // 2. Shift A right: col 0 takes a_feed, cols 1-3 shift from left neighbor
                for (int i = 0; i < 4; i++) begin
                    a_pe[i][0] <= a_feed[i];
                    a_pe[i][1] <= a_pe[i][0];
                    a_pe[i][2] <= a_pe[i][1];
                    a_pe[i][3] <= a_pe[i][2];
                end

                // 3. Shift B down: row 0 takes b_feed, rows 1-3 shift from upper neighbor
                for (int j = 0; j < 4; j++) begin
                    b_pe[0][j] <= b_feed[j];
                    b_pe[1][j] <= b_pe[0][j];
                    b_pe[2][j] <= b_pe[1][j];
                    b_pe[3][j] <= b_pe[2][j];
                end

                // 4. Advance counter; done at cycle 10 (11 total cycles: 0..10)
                cycle_counter <= cycle_counter + 1;

                if (cycle_counter == 4'd10) begin
                    cycles  <= 32'd11;
                    done    <= 1;
                    running <= 0;
                end
            end
        end
    end

endmodule
