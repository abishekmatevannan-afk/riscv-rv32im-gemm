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

    // Prefetch address — the combinational next-PC that the PC register will
    // take on the next posedge.  Driving BRAM one cycle early hides its
    // 1-cycle latency so hits have zero added stall cycles.
    input  logic [31:0] pc_next_i,
    input  logic        pc_stall_i,  // when 1 the PC will NOT advance; hold data_q

    // Memory interface (to instruction_memory)
    output logic        mem_re,
    output logic [31:0] mem_addr,
    input  logic [31:0] mem_rd
);

    localparam NUM_LINES  = 256;
    localparam LINE_WORDS = 4;
    localparam TAG_WIDTH  = 20;
    localparam IDX_WIDTH  = 8;

    (* ram_style = "distributed" *) logic                 valid [NUM_LINES-1:0];
    (* ram_style = "distributed" *) logic [TAG_WIDTH-1:0] tags  [NUM_LINES-1:0];
    (* ram_style = "block" *)       logic [31:0]          data  [NUM_LINES-1:0][LINE_WORDS-1:0];
    logic                 request_miss;

    // Registered read of data[] — driven one cycle ahead by pc_next_i so
    // the result is ready the same cycle that if_pc == pc_next_i.
    // Frozen (held) whenever pc_stall_i=1 so the value stays valid for
    // the frozen PC.
    logic [31:0] data_q;

    // Word captured from mem_rd during the fill cycle whose fill_word matches
    // word_off.  Used as cpu_rd in the one-cycle DONE state so the pipeline
    // never sees a combinational read from a block-RAM array.
    logic [31:0] fill_data_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            data_q      <= 32'd0;
            fill_data_q <= 32'd0;
        end else if (!pc_stall_i) begin
            data_q <= data[pc_next_i[11:4]][pc_next_i[3:2]];
        end
    end

    // address breakdown
    logic [TAG_WIDTH-1:0] addr_tag;
    logic [IDX_WIDTH-1:0] addr_idx;
    logic [1:0]           word_off;

    assign addr_tag = cpu_addr[31:12];
    assign addr_idx = cpu_addr[11:4];
    assign word_off = cpu_addr[3:2];

    // Hit detection stays combinational: valid[] and tags[] are distributed RAM
    // so Vivado maps them to LUT RAM which supports same-cycle reads.
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

    // instruction read mux
    // DONE: use fill_data_q (captured from mem_rd during fill at word_off)
    // hit:  use data_q (BRAM prefetch registered one cycle ahead via pc_next_i)
    // else: NOP bubble (pipeline stalled, value discarded)
    assign cpu_rd = (state == DONE) ? fill_data_q
                  : hit             ? data_q
                  :                   32'h00000013;

    // PMU signals
    assign icache_hit   = cpu_re && hit && (state == IDLE || state == DONE);
    assign icache_miss  = request_miss;
    assign icache_stall = cpu_re && !hit && (state != DONE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            fill_wait    <= 0;
            fill_word    <= 0;
            mem_re       <= 0;
            mem_addr     <= 32'd0;
            request_miss <= 0;
            for (i = 0; i < NUM_LINES; i++) begin
                valid[i] <= 0;
                tags[i]  <= '0;
            end
        end else if (flush) begin
            // branch correction: abandon partial fill, preserve cached lines
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
                        if (fill_word == word_off)
                            fill_data_q <= mem_rd;  // save the word cpu_addr needs

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