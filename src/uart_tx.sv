// UART Transmitter
// 8N1 format: 8 data bits, no parity, 1 stop bit
// Configurable baud rate via CLKS_PER_BIT parameter

module uart_tx #(
    parameter CLKS_PER_BIT = 10416  // 100MHz / 9600 baud
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,    // pulse high to start transmission
    input  logic [7:0] tx_data,     // byte to transmit
    output logic       tx_serial,   // serial output line
    output logic       tx_busy,     // high while transmitting
    output logic       tx_done      // pulses high for one cycle when done
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        START   = 3'b001,
        DATA    = 3'b010,
        STOP    = 3'b011,
        CLEANUP = 3'b100
    } state_t;

    state_t state;

    logic [13:0] clk_count;     // counts clocks per bit
    logic [2:0]  bit_index;     // which data bit we're sending
    logic [7:0]  tx_data_reg;   // latched copy of tx_data

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            tx_serial  <= 1'b1;   // idle high
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
            clk_count  <= 0;
            bit_index  <= 0;
            tx_data_reg <= 0;
        end else begin
            tx_done <= 1'b0;      // default: not done

            case (state)

                IDLE: begin
                    tx_serial <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= 0;
                    bit_index <= 0;

                    if (tx_start) begin
                        tx_data_reg <= tx_data;
                        tx_busy     <= 1'b1;
                        state       <= START;
                    end
                end

                // send start bit (low)
                START: begin
                    tx_serial <= 1'b0;

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state     <= DATA;
                    end
                end

                // send 8 data bits LSB first
                DATA: begin
                    tx_serial <= tx_data_reg[bit_index];

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state     <= STOP;
                        end
                    end
                end

                // send stop bit (high)
                STOP: begin
                    tx_serial <= 1'b1;

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        tx_done   <= 1'b1;
                        state     <= CLEANUP;
                    end
                end

                // one cycle cleanup before accepting new byte
                CLEANUP: begin
                    tx_busy <= 1'b0;
                    state   <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule