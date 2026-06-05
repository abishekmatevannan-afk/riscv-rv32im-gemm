//old hazard_unit.sv code:
    // Detects load-use hazards and branch/jump hazards
    // Controls pipeline stalls and flushes
   

// Detects load-use hazards and branch/jump hazards
// Controls pipeline stalls and flushes

module hazard_unit (
    // load-use hazard detection
    // need EX stage info to detect
    input  logic       ex_mem_re,       // is EX stage a load?
    input  logic [4:0] ex_rd_addr,      // destination of load in EX
    input  logic [4:0] id_rs1_addr,     // source regs of instruction in ID
    input  logic [4:0] id_rs2_addr,

    // branch/jump hazard detection
    input  logic       ex_branch,       // is EX stage a branch?
    input  logic       ex_jump,         // is EX stage a jump?
    input  logic       branch_taken,    // was the branch actually taken?
    input  logic       ex_predict_taken,   // was the branch predicted taken?

    input  logic       cache_stall,     // is there a stall from the memory system?
    input  logic       icache_stall,    

    // pipeline control outputs
    output logic       pc_stall,        // freeze PC
    output logic       if_id_stall,     // freeze IF/ID register
    output logic       if_id_flush,     // flush IF/ID register
    output logic       id_ex_flush,     // flush ID/EX register
    output logic       id_ex_stall,      
    output logic       ex_mem_stall,     
    output logic       mem_wb_stall,  
    output logic       branch_mispredict // branch outcome != IF prediction   
);

    logic load_use_hazard;
    logic control_hazard;

    // load-use hazard:
    // EX stage is a load AND its destination matches
    // either source of the instruction currently in ID
    assign load_use_hazard = ex_mem_re &&
                             (ex_rd_addr == id_rs1_addr ||
                              ex_rd_addr == id_rs2_addr);

    // control hazard:
    // branch taken or unconditional jump
    // need to flush the two wrongly fetched instructions
    assign branch_mispredict = ex_branch && (branch_taken != ex_predict_taken);
    assign control_hazard    = branch_mispredict || ex_jump;

    // pc_stall: release icache stall when a branch/jump correction fires.
    // if_id_flush being high means EX has resolved a misprediction or jump --
    // the PC must take pc_next (the corrected target) immediately.
    // Holding pc_stall high here would trap the PC at the wrong address.
    assign pc_stall     = load_use_hazard || cache_stall || (icache_stall && !if_id_flush);

    // if_id_stall: hold IF/ID frozen during icache fill.
    // if_id_flush takes priority in the IF/ID register (flush > stall),
    // so a simultaneous branch correction still clears the wrong instruction.
    assign if_id_stall  = load_use_hazard || cache_stall || icache_stall;
    
    assign id_ex_stall  = cache_stall || icache_stall;
    assign ex_mem_stall = cache_stall || icache_stall;
    assign mem_wb_stall = cache_stall || icache_stall;

    // flush signals
    // load-use: flush ID/EX only (insert bubble into EX)
    // control:  flush IF/ID and ID/EX (remove wrong instructions)
    assign id_ex_flush = (load_use_hazard || control_hazard) && !cache_stall;
    assign if_id_flush = control_hazard && !cache_stall;





    


endmodule