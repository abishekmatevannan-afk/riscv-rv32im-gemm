// Memory-mapped UART interface
// Base address: 0xFFFF0000
// 0xFFFF0000 — TX register        (write byte to transmit)
// 0xFFFF0004 — TX status register  (bit 0 = TX FIFO not full)
// 0xFFFF0008 — RX register         (read received byte, clears irq)
// 0xFFFF000C — RX status register  (bit 0 = data available)
 
module uart_mem_map #(
    parameter CLKS_PER_BIT = 10416
)(
    input  logic        clk,
    input  logic        rst,
 
    input  logic        we,
    input  logic        re,
    input  logic [31:0] addr,
    input  logic [31:0] wd,
    output logic [31:0] rd,
 
    output logic        uart_tx_pin,
    input  logic        uart_rx_pin,
    output logic        irq           // high when RX byte available, cleared on RX read
);
 
    localparam UART_TX        = 32'hFFFF0000;
    localparam UART_TX_STATUS = 32'hFFFF0004;
    localparam UART_RX        = 32'hFFFF0008;
    localparam UART_RX_STATUS = 32'hFFFF000C;
 
    // =========================================================
    // TX PATH
    // =========================================================
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_busy;
    logic       tx_done;
 
    localparam FIFO_DEPTH      = 8;
    localparam FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH);
 
    logic [7:0]               tx_fifo [FIFO_DEPTH-1:0];
    logic [FIFO_ADDR_WIDTH-1:0] fifo_wr_ptr;
    logic [FIFO_ADDR_WIDTH-1:0] fifo_rd_ptr;
    logic [FIFO_ADDR_WIDTH:0]   fifo_count;
 
    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 0);
    wire fifo_ready = !fifo_full;
 
    logic       we_prev;
    logic [7:0] wd_prev;
 
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) TX (
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
            we_prev     <= 0;
            wd_prev     <= 0;
        end else begin
            logic pop, push;
            tx_start <= 0;
 
            pop = (!tx_busy && !fifo_empty && !tx_start) ||
                  (tx_done  && !fifo_empty);
            push = we_prev && !fifo_full;
 
            if (pop) begin
                tx_data     <= tx_fifo[fifo_rd_ptr];
                tx_start    <= 1;
                fifo_rd_ptr <= fifo_rd_ptr + 1;
            end
            if (push) begin
                tx_fifo[fifo_wr_ptr] <= wd_prev;
                fifo_wr_ptr          <= fifo_wr_ptr + 1;
            end
 
            if      (pop && push) fifo_count <= fifo_count;
            else if (pop)         fifo_count <= fifo_count - 1;
            else if (push)        fifo_count <= fifo_count + 1;
 
            we_prev <= we && (addr == UART_TX);
            if (we && addr == UART_TX)
                wd_prev <= wd[7:0];
        end
    end
 
    // =========================================================
    // RX PATH
    // =========================================================
    logic [7:0] rx_data;
    logic       rx_done;
    logic       rx_valid;
 
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) RX (
        .clk       (clk),
        .rst       (rst),
        .rx_serial (uart_rx_pin),
        .rx_data   (rx_data),
        .rx_done   (rx_done),
        .rx_valid  (rx_valid)
    );
 
    // RX holding register and interrupt flag
    logic [7:0] rx_hold;     // latched byte waiting for CPU to read
    logic       rx_pending;  // set on rx_done, cleared on CPU read of UART_RX
 
    always_ff @(posedge clk) begin
        if (rst) begin
            rx_hold    <= 8'd0;
            rx_pending <= 0;
        end else begin
            // latch incoming byte
            if (rx_done) begin
                rx_hold    <= rx_data;
                rx_pending <= 1;
            end
            // CPU reads UART_RX — clear interrupt
            if (re && addr == UART_RX)
                rx_pending <= 0;
        end
    end
 
    assign irq = rx_pending;
 
    // =========================================================
    // READ MUX
    // =========================================================
    always_comb begin
        rd = 32'd0;
        case (addr)
            UART_TX_STATUS: rd = {31'd0, fifo_ready};
            UART_RX:        rd = {24'd0, rx_hold};
            UART_RX_STATUS: rd = {31'd0, rx_pending};
            default:        rd = 32'd0;
        endcase
    end
 
endmodule