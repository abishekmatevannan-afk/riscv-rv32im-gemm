// Memory-mapped UART interface
// Base address: 0xFFFF0000
// 0xFFFF0000 — TX register (write byte here to transmit)
// 0xFFFF0004 — Status register (bit 0 = ready, 1=ready 0=busy)

module uart_mem_map #(
    parameter CLKS_PER_BIT = 10416  // 100MHz / 9600 baud
)(
    input  logic        clk,
    input  logic        rst,

    input  logic        we,
    input  logic [31:0] addr,
    input  logic [31:0] wd,
    output logic [31:0] rd,

    output logic        uart_tx_pin
);

    localparam UART_TX     = 32'hFFFF0000;
    localparam UART_STATUS = 32'hFFFF0004;

    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_busy;
    logic       tx_done;

    localparam FIFO_DEPTH = 8;
    localparam FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH);

    logic [7:0] tx_fifo [FIFO_DEPTH-1:0];
    logic [FIFO_ADDR_WIDTH-1:0] fifo_wr_ptr;
    logic [FIFO_ADDR_WIDTH-1:0] fifo_rd_ptr;
    logic [FIFO_ADDR_WIDTH:0] fifo_count;

    wire fifo_full = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 0);
    wire fifo_ready = !fifo_full;

    // One-cycle-delayed enqueue: we_prev is qualified when we asserted on UART_TX.
    logic        we_prev;
    logic [7:0]  wd_prev;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) UART (
        .clk       (clk),
        .rst       (rst),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_serial (uart_tx_pin),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

    // pop/push decided once per cycle inside always_ff (no always_comb around tx_start /
    // UART feedback — avoids combinational stalls in simulation).
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_start    <= 0;
            tx_data     <= 0;
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count  <= 0;
            we_prev     <= 0;
            wd_prev     <= 0;
        end else begin
            logic pop;
            logic push;

            tx_start <= 0;

            pop = 1'b0;
            if (tx_done && !fifo_empty)
                pop = 1'b1;
            else if (!tx_busy && !fifo_empty && !tx_start)
                pop = 1'b1;

            push = we_prev && !fifo_full;

            if (pop) begin
                tx_data <= tx_fifo[fifo_rd_ptr];
                tx_start <= 1;
                fifo_rd_ptr <= fifo_rd_ptr + 1;
            end
            if (push) begin
                tx_fifo[fifo_wr_ptr] <= wd_prev;
                fifo_wr_ptr <= fifo_wr_ptr + 1;
            end

            if (pop && push)
                fifo_count <= fifo_count;
            else if (pop)
                fifo_count <= fifo_count - 1;
            else if (push)
                fifo_count <= fifo_count + 1;
            else
                fifo_count <= fifo_count;

            we_prev <= we && (addr == UART_TX);
            if (we && addr == UART_TX)
                wd_prev <= wd[7:0];
        end
    end

    assign rd = (addr == UART_STATUS) ? {31'd0, fifo_ready} : 32'd0;

endmodule
