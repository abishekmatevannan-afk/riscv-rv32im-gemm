// Wraps uart_mem_map with standard AXI4-Lite interface
// Always-ready, combinational responses
//
// Connected as interconnect subordinate S2, driven by the IO manager (M2).
// top_pipeline.sv routes 0xFFFF.... addresses here, except the PMU
// range 0xFFFF20xx (is_uart = is_io && !is_perf).

module axi4_lite_uart_sub #(
    parameter CLKS_PER_BIT = 10416
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
    output logic [1:0]  bresp,

    // UART pins
    output logic        uart_tx_pin,
    input  logic        uart_rx_pin,
    output logic        uart_irq
);
    logic [31:0] uart_rd_int;

    // write takes priority for address when both present (shouldn't overlap)
    logic uart_we_int, uart_re_int;
    logic [31:0] uart_addr_int;
    assign uart_we_int   = awvalid && wvalid;
    assign uart_re_int   = arvalid;
    assign uart_addr_int = uart_we_int ? awaddr : araddr;

    uart_mem_map #(.CLKS_PER_BIT(CLKS_PER_BIT)) UART (
        .clk         (clk),
        .rst         (rst),
        .we          (uart_we_int),
        .re          (uart_re_int),
        .addr        (uart_addr_int),
        .wd          (wdata),
        .rd          (uart_rd_int),
        .uart_tx_pin (uart_tx_pin),
        .uart_rx_pin (uart_rx_pin),
        .irq         (uart_irq)
    );

    assign arready = 1'b1;
    assign rvalid  = arvalid;
    assign rdata   = uart_rd_int;
    assign rresp   = 2'b00;

    assign awready = 1'b1;
    assign wready  = 1'b1;
    assign bvalid  = awvalid && wvalid;
    assign bresp   = 2'b00;
endmodule