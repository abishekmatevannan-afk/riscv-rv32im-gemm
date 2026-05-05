// Memory-mapped UART interface
// Base address: 0xFFFF0000
// 0xFFFF0000 — TX register (write byte here to transmit)
// 0xFFFF0004 — Status register (bit 0 = ready, 1=ready 0=busy)

module uart_mem_map #(
    parameter CLKS_PER_BIT = 10416  // 100MHz / 9600 baud
)(
    input  logic        clk,
    input  logic        rst,

    // CPU memory interface
    input  logic        we,          // write enable from CPU
    input  logic [31:0] addr,        // address from CPU
    input  logic [31:0] wd,          // write data from CPU
    output logic [31:0] rd,          // read data to CPU

    // UART physical pins
    output logic        uart_tx_pin  // connect to FPGA TX pin
);

    // UART base address
    localparam UART_TX     = 32'hFFFF0000;
    localparam UART_STATUS = 32'hFFFF0004;

    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_busy;
    logic       tx_done;

    // FIFO for buffering multiple writes
    localparam FIFO_DEPTH = 8;
    localparam FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH);

    logic [7:0] tx_fifo [FIFO_DEPTH-1:0];
    logic [FIFO_ADDR_WIDTH-1:0] fifo_wr_ptr;
    logic [FIFO_ADDR_WIDTH-1:0] fifo_rd_ptr;
    logic [FIFO_ADDR_WIDTH:0] fifo_count;

    wire fifo_full = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 0);
    wire fifo_ready = !fifo_full;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) UART (
        .clk       (clk),
        .rst       (rst),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_serial (uart_tx_pin),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_start    <= 0;
            tx_data     <= 0;
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count  <= 0;
        end else begin
            tx_start <= 0;

            // Enqueue CPU write if FIFO has space
            if (we && addr == UART_TX && !fifo_full) begin
                tx_fifo[fifo_wr_ptr] <= wd[7:0];
                fifo_wr_ptr <= fifo_wr_ptr + 1;
                fifo_count <= fifo_count + 1;
            end

            // Start transmission: fire tx_start once per byte, when UART becomes idle
            // and FIFO is not empty. Use tx_done as the edge trigger.
            if (tx_done && !fifo_empty) begin
                tx_data <= tx_fifo[fifo_rd_ptr];
                tx_start <= 1;
                fifo_rd_ptr <= fifo_rd_ptr + 1;
                fifo_count <= fifo_count - 1;
            end
            // Also start the first transmission when UART is idle and FIFO has data
            else if (!tx_busy && !fifo_empty && !tx_start) begin
                tx_data <= tx_fifo[fifo_rd_ptr];
                tx_start <= 1;
                fifo_rd_ptr <= fifo_rd_ptr + 1;
                fifo_count <= fifo_count - 1;
            end
        end
    end

    // status: bit 0 = ready (FIFO not full), bit 1 = busy (transmitting or FIFO not empty)
    assign rd = (addr == UART_STATUS) ? {31'd0, fifo_ready} : 32'd0;

endmodule