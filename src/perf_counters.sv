// Hardware performance monitoring unit
// Tracks cycles, instructions retired, branches, mispredictions
// Memory-mapped at 0xFFFF2000

module perf_counters (
    input  logic        clk,
    input  logic        rst,

    // CPU memory-mapped interface
    input  logic        re,
    input  logic [31:0] addr,
    output logic [31:0] rd,

    // counter increment signals from pipeline
    input  logic        instr_retired,   // high when instruction completes WB
    input  logic        branch_exec,     // high when branch in EX stage
    input  logic        mispredict,      // high when branch mispredicted
    input  logic        cache_hit,
    input  logic        cache_miss

);

    // memory map
    localparam CYCLE_ADDR     = 32'hFFFF2000;
    localparam INSTR_ADDR     = 32'hFFFF2004;
    localparam BRANCH_ADDR    = 32'hFFFF2008;
    localparam MISPREDICT_ADDR = 32'hFFFF200C;
    localparam CACHE_HIT_ADDR  = 32'hFFFF2010;
    localparam CACHE_MISS_ADDR = 32'hFFFF2014; 

    // 32-bit counters
    logic [31:0] cycle_count;
    logic [31:0] instr_count;
    logic [31:0] branch_count;
    logic [31:0] mispredict_count;
    logic [31:0] cache_hit_count;
    logic [31:0] cache_miss_count;

    // cycle counter — increments every clock
    always_ff @(posedge clk) begin
        if (rst)
            cycle_count <= 32'd0;
        else
            cycle_count <= cycle_count + 1;
    end

    // instruction retired counter
    always_ff @(posedge clk) begin
        if (rst)
            instr_count <= 32'd0;
        else if (instr_retired)
            instr_count <= instr_count + 1;
    end

    // branch counter
    always_ff @(posedge clk) begin
        if (rst)
            branch_count <= 32'd0;
        else if (branch_exec)
            branch_count <= branch_count + 1;
    end

    // misprediction counter
    always_ff @(posedge clk) begin
        if (rst)
            mispredict_count <= 32'd0;
        else if (mispredict)
            mispredict_count <= mispredict_count + 1;
    end

    // cache hit counter
    always_ff @(posedge clk) begin
        if (rst)          cache_hit_count <= 0;
        else if (cache_hit) cache_hit_count <= cache_hit_count + 1;
    end

    // cache miss counter   
    always_ff @(posedge clk) begin
        if (rst)           cache_miss_count <= 0;
        else if (cache_miss) cache_miss_count <= cache_miss_count + 1;
    end

    // read logic
    always_comb begin
        rd = 32'd0;
        if (re) begin
            case (addr)
                CYCLE_ADDR:      rd = cycle_count;
                INSTR_ADDR:      rd = instr_count;
                BRANCH_ADDR:     rd = branch_count;
                MISPREDICT_ADDR: rd = mispredict_count;
                CACHE_HIT_ADDR:  rd = cache_hit_count;
                CACHE_MISS_ADDR: rd = cache_miss_count;
                default:         rd = 32'd0;
            endcase
        end
    end

endmodule