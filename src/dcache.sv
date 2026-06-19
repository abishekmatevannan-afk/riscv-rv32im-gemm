// Direct-mapped write-back write-allocate L1 Data Cache
// 4096 bytes total, 256 lines, 16 bytes per line (4 words)
//
// Address breakdown [31:0]:
//   Tag    [31:12] 20 bits
//   Index  [11:4]   8 bits  (selects 1 of 256 lines)
//   Offset [3:0]    4 bits  (byte within line)
 
module dcache (
    input  logic        clk,
    input  logic        rst,
 
    // CPU interface (from MEM stage)
    input  logic        cpu_we,          // write enable from CPU
    input  logic        cpu_re,          // read enable from CPU
    input  logic [31:0] cpu_addr,        // byte address from CPU (= registered EX result)
    input  logic [31:0] cpu_wd,          // write data from CPU
    input  logic [2:0]  cpu_funct3,      // access width
    output logic [31:0] cpu_rd,          // read data to CPU
    output logic        cache_stall,     // stall pipeline on miss
    output logic        cache_hit,       // high on hit (for PMU)
    output logic        cache_miss,      // high on miss (for PMU)

    // Prefetch address — the combinational EX ALU result before it is captured
    // in the EX/MEM register.  Driving BRAM one cycle early hides its latency
    // so hits have zero added stall cycles.
    input  logic [31:0] ex_addr_i,
    input  logic        ex_stall_i,      // when 1 EX/MEM won't advance; hold cached_word_q

    // Memory interface (to data_memory)
    output logic        mem_we,
    output logic        mem_re,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wd,
    output logic [2:0]  mem_funct3,
    input  logic [31:0] mem_rd,
    input  logic        is_io           // pass through for IO addresses
);
 
    // cache parameters
    localparam NUM_LINES  = 256;
    localparam LINE_WORDS = 4;
    localparam TAG_WIDTH  = 20;
    localparam IDX_WIDTH  = 8;
    localparam OFF_WIDTH  = 4;
 
    // cache storage
    // valid/dirty/tags: distributed RAM — supports combinational reads for hit
    //   detection and dirty-eviction checks inside always_ff.
    // data: block RAM — reads are registered via the cached_word_q prefetch path.
    (* ram_style = "distributed" *) logic                valid [NUM_LINES-1:0];
    (* ram_style = "distributed" *) logic                dirty [NUM_LINES-1:0];
    (* ram_style = "distributed" *) logic [TAG_WIDTH-1:0] tags [NUM_LINES-1:0];
    (* ram_style = "block" *)       logic [31:0]          data [NUM_LINES-1:0][LINE_WORDS-1:0];

    // Registered BRAM-prefetch read of data[]; see always_ff after hit detection.
    logic [31:0] cached_word_q;

    // Word captured from mem_rd during the fill cycle that fills word_off.
    // Used as cpu_rd in the DONE state so there is no combinational BRAM read.
    logic [31:0] fill_wd_q;

    // ADDRESS BREAKDOWN
    // All bit-selects on cpu_addr are done here as named wires
    // so that always_* blocks never contain bit-selects of a
    // parent signal (avoids Icarus sensitivity-list warnings).
 
    logic [TAG_WIDTH-1:0] addr_tag;
    logic [IDX_WIDTH-1:0] addr_idx;
    logic [OFF_WIDTH-1:0] addr_off;
    logic [1:0]           word_off;     // bits [3:2] — word within line
    logic [1:0]           byte_off;     // bits [1:0] — byte within word
    logic                 byte_off_hi;  // bit  [1]
    logic                 byte_off_lo;  // bit  [0]
 
    assign addr_tag    = cpu_addr[31:12];
    assign addr_idx    = cpu_addr[11:4];
    assign addr_off    = cpu_addr[3:0];
    assign word_off    = cpu_addr[3:2];
    assign byte_off    = cpu_addr[1:0];
    assign byte_off_hi = cpu_addr[1];
    assign byte_off_lo = cpu_addr[0];
 
    // hit detection
    logic hit;
    assign hit = valid[addr_idx] && (tags[addr_idx] == addr_tag);

    // Prefetch always_ff — placed here so addr_idx, word_off, byte_off_hi, hit
    // are all in scope (Icarus Verilog requires declaration before use).
    // Write-hit forwarding: when the MEM-stage write-hit and the EX-stage
    // prefetch target the same cache word, both the non-blocking write to data[]
    // and this non-blocking read fire at the same posedge — the read would see
    // the pre-posedge (stale) value.  Detect and forward instead.
    always_ff @(posedge clk) begin
        if (rst) begin
            cached_word_q <= 32'd0;
        end else if (!ex_stall_i) begin
            if (cpu_we && hit && !is_io &&
                ex_addr_i[11:4] == addr_idx && ex_addr_i[3:2] == word_off) begin
                case (cpu_funct3)
                    3'b000: begin // SB — one byte changes; merge with old word
                        case (byte_off)
                            2'b00: cached_word_q <= {data[ex_addr_i[11:4]][ex_addr_i[3:2]][31: 8], cpu_wd[7:0]};
                            2'b01: cached_word_q <= {data[ex_addr_i[11:4]][ex_addr_i[3:2]][31:16], cpu_wd[7:0], data[ex_addr_i[11:4]][ex_addr_i[3:2]][ 7:0]};
                            2'b10: cached_word_q <= {data[ex_addr_i[11:4]][ex_addr_i[3:2]][31:24], cpu_wd[7:0], data[ex_addr_i[11:4]][ex_addr_i[3:2]][15:0]};
                            2'b11: cached_word_q <= {cpu_wd[7:0], data[ex_addr_i[11:4]][ex_addr_i[3:2]][23:0]};
                        endcase
                    end
                    3'b001: begin // SH — two bytes change; merge with old word
                        if (!byte_off_hi)
                            cached_word_q <= {data[ex_addr_i[11:4]][ex_addr_i[3:2]][31:16], cpu_wd[15:0]};
                        else
                            cached_word_q <= {cpu_wd[15:0], data[ex_addr_i[11:4]][ex_addr_i[3:2]][15:0]};
                    end
                    default: cached_word_q <= cpu_wd; // SW — entire word replaced
                endcase
            end else begin
                cached_word_q <= data[ex_addr_i[11:4]][ex_addr_i[3:2]];
            end
        end
    end

    // IO pass-through — bypass cache for memory-mapped peripherals
    logic is_cacheable;
    assign is_cacheable = !is_io;
 
 
    // FSM
    typedef enum logic [1:0] {
        IDLE      = 2'b00,
        WRITEBACK = 2'b01,
        FILL      = 2'b10,
        DONE      = 2'b11
    } state_t;
 
    state_t state;
 
    // fill word counter — tracks which word we are fetching/writing
    logic [1:0] fill_word;
 
    // writeback address
    logic [31:0] wb_addr;
 
    // one cycle wait for memory to respond
    logic fill_wait;
 
    integer i;
 
    // =========================================================
    // INTERMEDIATE READ DATA SIGNALS
    // All sub-word extractions use constant bit ranges on
    // cached_word (itself a named wire), so no warnings arise.
    // =========================================================
 
    logic [31:0] cached_word;
    assign cached_word = cached_word_q;  // registered prefetch; see always_ff above
 
    // signed byte reads
    logic [31:0] lb_00, lb_01, lb_10, lb_11;
    assign lb_00 = {{24{cached_word[7]}},  cached_word[7:0]};
    assign lb_01 = {{24{cached_word[15]}}, cached_word[15:8]};
    assign lb_10 = {{24{cached_word[23]}}, cached_word[23:16]};
    assign lb_11 = {{24{cached_word[31]}}, cached_word[31:24]};
 
    // unsigned byte reads
    logic [31:0] lbu_00, lbu_01, lbu_10, lbu_11;
    assign lbu_00 = {24'd0, cached_word[7:0]};
    assign lbu_01 = {24'd0, cached_word[15:8]};
    assign lbu_10 = {24'd0, cached_word[23:16]};
    assign lbu_11 = {24'd0, cached_word[31:24]};
 
    // signed halfword reads
    logic [31:0] lh_0, lh_1;
    assign lh_0 = {{16{cached_word[15]}}, cached_word[15:0]};
    assign lh_1 = {{16{cached_word[31]}}, cached_word[31:16]};
 
    // unsigned halfword reads
    logic [31:0] lhu_0, lhu_1;
    assign lhu_0 = {16'd0, cached_word[15:0]};
    assign lhu_1 = {16'd0, cached_word[31:16]};
 
    // =========================================================
    // HIT READ MUX
    // Uses byte_off_hi / byte_off_lo (plain wire names) instead
    // of addr_off[1] / addr_off[0] — eliminates Icarus warnings.
    // =========================================================
 
    logic [31:0] hit_rd;
    always_comb begin
        case (cpu_funct3)
            3'b000:  hit_rd = byte_off_hi ? (byte_off_lo ? lb_11  : lb_10)
                                          : (byte_off_lo ? lb_01  : lb_00);
            3'b001:  hit_rd = byte_off_hi ? lh_1  : lh_0;
            3'b010:  hit_rd = cached_word;
            3'b100:  hit_rd = byte_off_hi ? (byte_off_lo ? lbu_11 : lbu_10)
                                          : (byte_off_lo ? lbu_01 : lbu_00);
            3'b101:  hit_rd = byte_off_hi ? lhu_1 : lhu_0;
            default: hit_rd = cached_word;
        endcase
    end
 
    assign cpu_rd = is_io                          ? mem_rd  :
                    (state == DONE)                ? fill_wd_q :
                    (hit && (cpu_re || !cpu_we))   ? hit_rd  :
                                                     32'd0;
 
    // =========================================================
    // PMU SIGNALS
    // =========================================================
 
    assign cache_hit   = is_cacheable && (cpu_re || cpu_we) &&  hit && (state == IDLE);
    assign cache_miss  = is_cacheable && (cpu_re || cpu_we) && !hit && (state == IDLE);
    assign cache_stall = is_cacheable && (cpu_re || cpu_we) && 
                     ((!hit && state == IDLE) || 
                      state == WRITEBACK       || 
                      state == FILL);
    // =========================================================
    // FSM — MISS HANDLING
    // Write-hit cases use byte_off / byte_off_hi (plain wire
    // names) instead of addr_off[1:0] / addr_off[1] to avoid
    // Icarus sensitivity-list warnings inside always_ff.
    // =========================================================
 
    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            fill_wait  <= 0;
            fill_word  <= 0;
            fill_wd_q  <= 32'd0;
            mem_we     <= 0;
            mem_re     <= 0;
            mem_addr   <= 32'd0;
            mem_wd     <= 32'd0;
            mem_funct3 <= 3'b000;
            for (i = 0; i < NUM_LINES; i++) begin
                valid[i] <= 0;
                dirty[i] <= 0;
                tags[i]  <= '0;
            end
        end else begin
            mem_we <= 0;
            mem_re <= 0;
 
            case (state)
 
                IDLE: begin
                    if (is_io) begin
                        // IO access — pass straight to memory
                        mem_we     <= cpu_we;
                        mem_re     <= cpu_re;
                        mem_addr   <= cpu_addr;
                        mem_wd     <= cpu_wd;
                        mem_funct3 <= cpu_funct3;
 
                    end else if ((cpu_re || cpu_we) && !hit) begin
                        // cache miss
                        fill_word <= 0;
                        if (valid[addr_idx] && dirty[addr_idx]) begin
                            // dirty line — writeback before fill
                            wb_addr <= {tags[addr_idx], addr_idx, 4'd0};
                            state   <= WRITEBACK;
                        end else begin
                            // clean or invalid — go straight to fill
                            state <= FILL;
                        end
 
                    end else if (cpu_we && hit) begin
                        // write hit — update cache, mark dirty
                        dirty[addr_idx] <= 1;
                        case (cpu_funct3)
                            3'b000: begin // SB — uses byte_off (was addr_off[1:0])
                                case (byte_off)
                                    2'b00: data[addr_idx][word_off][7:0]   <= cpu_wd[7:0];
                                    2'b01: data[addr_idx][word_off][15:8]  <= cpu_wd[7:0];
                                    2'b10: data[addr_idx][word_off][23:16] <= cpu_wd[7:0];
                                    2'b11: data[addr_idx][word_off][31:24] <= cpu_wd[7:0];
                                endcase
                            end
                            3'b001: begin // SH — uses byte_off_hi (was addr_off[1])
                                case (byte_off_hi)
                                    1'b0: data[addr_idx][word_off][15:0]  <= cpu_wd[15:0];
                                    1'b1: data[addr_idx][word_off][31:16] <= cpu_wd[15:0];
                                endcase
                            end
                            3'b010:  data[addr_idx][word_off] <= cpu_wd; // SW
                            default: data[addr_idx][word_off] <= cpu_wd;
                        endcase
                    end
                end
 
                WRITEBACK: begin
                    // write back one word per cycle
                    mem_we     <= 1;
                    mem_addr <= {wb_addr[31:4], fill_word, 2'b00};
                    mem_wd     <= data[addr_idx][fill_word];
                    mem_funct3 <= 3'b010; // always write full words
 
                    if (fill_word == 2'b11) begin
                        fill_word       <= 0;
                        dirty[addr_idx] <= 0;
                        state           <= FILL;
                    end else begin
                        fill_word <= fill_word + 1;
                    end
                end
 
                FILL: begin
                    mem_re     <= 1;
                    mem_addr   <= {addr_tag, addr_idx, fill_word, 2'b00};
                    mem_funct3 <= 3'b010;
 
                    if (!fill_wait) begin
                        // first cycle: send address, wait for memory
                        fill_wait <= 1;
                    end else begin
                        // subsequent cycles: latch incoming word
                        data[addr_idx][fill_word] <= mem_rd;
                        if (fill_word == word_off)
                            fill_wd_q <= mem_rd;  // save the word cpu_addr needs

                        if (fill_word == 2'b11) begin
                            valid[addr_idx] <= 1;
                            tags[addr_idx]  <= addr_tag;
                            fill_word       <= 0;
                            fill_wait       <= 0;
 
                            if (cpu_we) begin
                                dirty[addr_idx]          <= 1;
                                data[addr_idx][word_off] <= cpu_wd;
                            end
 
                            state <= DONE;
                        end else begin
                            fill_word <= fill_word + 1;
                        end
                    end
                end
 
                DONE: begin
                    // one cycle to let data propagate to cpu_rd
                    state <= IDLE;
                end
 
            endcase
        end
    end
 
endmodule