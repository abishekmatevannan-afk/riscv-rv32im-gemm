// Direct-mapped read-only L1 instruction cache
// 256 bytes total, 16 lines, 16 bytes per line (4 words)
//
// Address breakdown [31:0]:
//   Tag    [31:8]  24 bits
//   Index  [7:4]    4 bits
//   Offset [3:0]    4 bits  (word_off = [3:2], ignored byte bits [1:0])
//
// No dirty bit, no writeback -- read-only.
// FSM: IDLE -> FILL -> DONE
// flush input aborts a mid-fill on branch misprediction so PC can redirect.

module icache (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,       // abort fill -- branch/jump correction in EX

    // CPU interface (from IF stage)
    input  logic        cpu_re,      // high every cycle PC is valid
    input  logic [31:0] cpu_addr,    // current PC
    output logic [31:0] cpu_rd,      // instruction out to IF/ID
    output logic        icache_stall,
    output logic        icache_hit,
    output logic        icache_miss,

    // Memory interface (to instruction_memory)
    output logic        mem_re,
    output logic [31:0] mem_addr,
    input  logic [31:0] mem_rd
);

    localparam NUM_LINES  = 256;
    localparam LINE_WORDS = 4;
    localparam TAG_WIDTH  = 20;
    localparam IDX_WIDTH  = 8;

    logic                 valid [NUM_LINES-1:0];
    logic [TAG_WIDTH-1:0] tags  [NUM_LINES-1:0];
    logic [31:0]          data  [NUM_LINES-1:0][LINE_WORDS-1:0];
    logic                 request_miss;

    // address breakdown
    logic [TAG_WIDTH-1:0] addr_tag;
    logic [IDX_WIDTH-1:0] addr_idx;
    logic [1:0]           word_off;

    assign addr_tag = cpu_addr[31:12];
    assign addr_idx = cpu_addr[11:4];
    assign word_off = cpu_addr[3:2];

    logic hit;
    assign hit = valid[addr_idx] && (tags[addr_idx] == addr_tag);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        FILL = 2'b01,
        DONE = 2'b10
    } state_t;

    state_t    state;
    logic [1:0] fill_word;
    logic        fill_wait;

    integer i;
    initial begin
        for (i = 0; i < NUM_LINES; i++) begin
            valid[i] = 0;
            tags[i]  = 0;
        end
    end

    // instruction read mux
    // DONE state: line just filled, data is valid for cpu_addr
    // hit: normal cache hit in IDLE
    // otherwise: NOP (pipeline is stalled anyway, this value won't be used)
    assign cpu_rd = (hit || state == DONE)
                  ? data[addr_idx][word_off]
                  : 32'h00000013;  // NOP

    // PMU signals
    assign icache_hit   = cpu_re && hit && (state == IDLE || state == DONE);
    assign icache_miss  = request_miss;
    assign icache_stall = cpu_re && !hit && (state != DONE);

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            // flush on branch correction: abandon partial fill
            // valid is NOT set so the partial line is invisible on next access
            state        <= IDLE;
            fill_wait    <= 0;
            fill_word    <= 0;
            mem_re       <= 0;
            mem_addr     <= 32'd0;
            request_miss <= 0;
        end else begin
            request_miss <= cpu_re && !hit && (state == IDLE);
            mem_re       <= 0;

            case (state)

                IDLE: begin
                    if (cpu_re && !hit) begin
                        fill_word <= 0;
                        state     <= FILL;
                        fill_wait <= 0;
                    end
                end

                FILL: begin
                    mem_re <= 1;

                    if (!fill_wait) begin
                        // present the first line word address
                        mem_addr <= {addr_tag, addr_idx, fill_word, 2'b00};
                        fill_wait <= 1;
                    end else begin
                        // instruction_memory is combinational:
                        // mem_addr from the previous cycle is now valid in mem_rd
                        data[addr_idx][fill_word] <= mem_rd;

                        if (fill_word == 2'b11) begin
                            valid[addr_idx] <= 1;
                            tags[addr_idx]  <= addr_tag;
                            fill_word       <= 0;
                            fill_wait       <= 0;
                            state           <= DONE;
                            mem_re          <= 0;
                            mem_addr        <= 32'd0;
                        end else begin
                            fill_word <= fill_word + 2'd1;
                            // request the next word on the next cycle
                            mem_addr <= {addr_tag, addr_idx, fill_word + 2'd1, 2'b00};
                            fill_wait <= 1;
                        end
                    end
                end

                DONE: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule