// Detects load-use hazards and branch/jump hazards
// Controls pipeline stalls and flushes

module hazard_unit (
    input  logic       clk,
    input  logic       rst,
    // load-use hazard detection
    // need EX stage info to detect
    input  logic       ex_mem_re,       // is EX stage a load?
    input  logic [4:0] ex_rd_addr,      // destination of load in EX
    input  logic [4:0] id_rs1_addr,     // source regs of instruction in ID
    input  logic [4:0] id_rs2_addr,
    input  logic [4:0] id_rd_addr,      // destination of instruction in ID (PMACC acc source)
    input  logic       id_is_pmacc,     // high when ID instruction is PMACC

    // branch/jump hazard detection
    input  logic       ex_branch,          // is EX stage a branch?
    input  logic       ex_jump_mispredict, // jump whose target was mispredicted
    input  logic       branch_taken,       // was the branch actually taken?
    input  logic       ex_predict_taken,   // was the branch predicted taken?

    input  logic       cache_stall,     // stall from dcache miss
    input  logic       div_busy,        // stall from multi-cycle divider
    input  logic       simd_stall,      // 1-cycle stall when SIMD first enters EX
    input  logic       icache_stall,

    // pipeline control outputs
    output logic       pc_stall,        // freeze PC
    output logic       if_id_stall,     // freeze IF/ID register
    output logic       if_id_flush,     // flush IF/ID register
    output logic       id_ex_flush,     // flush ID/EX register
    output logic       id_ex_stall,      
    output logic       ex_mem_stall,     
    output logic       mem_wb_stall,  
    output logic       branch_mispredict, // branch outcome != IF prediction   
    
    // exception-related inputs (for precise exceptions)
    input  logic       trap,
    input  logic       ex_mret
);

    logic load_use_hazard;
    logic control_hazard;
    logic any_stall;          // cache miss or divider running

    assign any_stall = cache_stall || div_busy || simd_stall;

    // load-use hazard:
    // EX stage is a load AND its destination matches
    // either source of the instruction currently in ID
    assign load_use_hazard = ex_mem_re && (ex_rd_addr != 5'd0) &&
                             (ex_rd_addr == id_rs1_addr ||
                              ex_rd_addr == id_rs2_addr ||
                              (id_is_pmacc && ex_rd_addr == id_rd_addr));

    // control hazard:
    // branch taken or unconditional jump
    // need to flush the two wrongly fetched instructions
    assign branch_mispredict = ex_branch && (branch_taken != ex_predict_taken);
    assign control_hazard = branch_mispredict || ex_jump_mispredict || trap || ex_mret;

    // pc_stall: release icache stall when a branch/jump correction fires.
    // if_id_flush being high means EX has resolved a misprediction or jump --
    // the PC must take pc_next (the corrected target) immediately.
    // Holding pc_stall high here would trap the PC at the wrong address.
    assign pc_stall     = load_use_hazard || any_stall || (icache_stall && !if_id_flush);
    assign if_id_stall  = load_use_hazard || any_stall || icache_stall;
    assign id_ex_stall  = any_stall;
    assign ex_mem_stall = any_stall;
    assign mem_wb_stall = any_stall;

    assign id_ex_flush = (load_use_hazard || control_hazard || icache_stall) && !any_stall;
    assign if_id_flush = control_hazard && !any_stall;

    // SVA: load-use hazard must freeze both IF and ID stages.
    // Clocked + rst-guarded: avoids delta-cycle and X-propagation false positives.
    always_ff @(posedge clk) begin
        if (!rst)
            assert (!load_use_hazard || if_id_stall)
                else $error("SVA FAIL: load_use_hazard asserted but if_id_stall low");
    end


    


endmodule