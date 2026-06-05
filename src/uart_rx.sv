// 8N1 format, configurable baud rate
// FSM: IDLE -> START -> DATA -> STOP
// Samples at mid-bit to avoid edge noise

module uart_rx #(
    parameter CLKS_PER_BIT = 10416
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       rx_serial,
    output logic [7:0] rx_data,
    output logic       rx_done,
    output logic       rx_valid    // stays high until cleared
);

    localparam HALF_BIT = CLKS_PER_BIT / 2;
    localparam CNT_W    = $clog2(CLKS_PER_BIT + 1);

    // 2-flop synchronizer
    logic rx_meta, rx_sync, rx_prev;
    always_ff @(posedge clk) begin
        rx_meta <= rx_serial;
        rx_sync <= rx_meta;
        rx_prev <= rx_sync;
    end

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t              state;
    logic [CNT_W-1:0]    clk_count;
    logic [2:0]          bit_idx;
    logic [7:0]          rx_shift;

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            clk_count <= 0;
            bit_idx   <= 0;
            rx_shift  <= 0;
            rx_data   <= 0;
            rx_done   <= 0;
            rx_valid  <= 0;
        end else begin
            rx_done <= 0;

            case (state)

                IDLE: begin
                    clk_count <= 0;
                    bit_idx   <= 0;
                    // detect falling edge on synchronized line
                    if (rx_prev && !rx_sync)
                        state <= START;
                end

                START: begin
                    // wait to mid-point of start bit and confirm
                    if (clk_count == HALF_BIT - 1) begin
                        clk_count <= 0;
                        if (!rx_sync)
                            state <= DATA;
                        else
                            state <= IDLE;  // noise, abort
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count             <= 0;
                        rx_shift[bit_idx]     <= rx_sync;
                        if (bit_idx == 3'b111) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state     <= IDLE;
                        if (rx_sync) begin
                            // valid stop bit
                            rx_done  <= 1;
                            rx_valid <= 1;
                            rx_data  <= rx_shift;
                        end
                        // else: framing error, silently discard
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

            endcase
        end
    end

endmodule