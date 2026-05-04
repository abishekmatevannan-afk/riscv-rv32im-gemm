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

    // pipeline control outputs
    output logic       pc_stall,        // freeze PC
    output logic       if_id_stall,     // freeze IF/ID register
    output logic       if_id_flush,     // flush IF/ID register
    output logic       id_ex_flush      // flush ID/EX register
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
    assign control_hazard = (ex_branch && branch_taken) || ex_jump;

    // stall signals — freeze PC and IF/ID when load-use detected
    assign pc_stall    = load_use_hazard;
    assign if_id_stall = load_use_hazard;

    // flush signals
    // load-use: flush ID/EX only (insert bubble into EX)
    // control:  flush IF/ID and ID/EX (remove wrong instructions)
    assign id_ex_flush = load_use_hazard || control_hazard;
    assign if_id_flush = control_hazard;

endmodule