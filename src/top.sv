// RV32I Single-Cycle CPU Top Level
// Instantiates and connects all modules
// Handles immediate generation, branch logic, PC selection

module top #(
    parameter HEX_FILE = "programs/test1.hex"
)(
    input  logic clk,
    input  logic rst
);

    // =========================================================
    // SIGNAL DECLARATIONS
    // =========================================================

    // PC signals
    logic [31:0] pc, pc_next, pc_plus4, pc_branch, pc_jump;

    // instruction fields
    logic [31:0] instr;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    // register file signals
    logic [31:0] rs1_data, rs2_data, wb_data;

    // ALU signals
    logic [31:0] alu_a, alu_b, alu_result;
    logic        alu_zero;

    // immediate
    logic [31:0] imm;

    // data memory signals
    logic [31:0] mem_rd;

    // control signals
    logic        reg_we, mem_we, mem_re;
    logic        alu_src, branch, jump;
    logic [1:0]  wb_sel;
    logic [3:0]  alu_ctrl;
    logic [2:0]  imm_sel;

    // branch taken signal
    logic        branch_taken;
    logic        pc_we;

    // =========================================================
    // MODULE INSTANTIATIONS
    // =========================================================

    program_counter PC (
        .clk     (clk),
        .rst     (rst),
        .pc_we   (pc_we),
        .pc_next (pc_next),
        .pc      (pc)
    );

    instruction_memory #(.HEX_FILE(HEX_FILE)) IMEM (
        .addr  (pc),
        .instr (instr)
    );

    control_unit CU (
        .instr    (instr),
        .reg_we   (reg_we),
        .mem_we   (mem_we),
        .mem_re   (mem_re),
        .alu_src  (alu_src),
        .wb_sel   (wb_sel),
        .branch   (branch),
        .jump     (jump),
        .alu_ctrl (alu_ctrl),
        .imm_sel  (imm_sel)
    );

    register_file RF (
        .clk (clk),
        .we  (reg_we),
        .rs1 (rs1_addr),
        .rs2 (rs2_addr),
        .rd  (rd_addr),
        .wd  (wb_data),
        .rd1 (rs1_data),
        .rd2 (rs2_data)
    );

    alu ALU (
        .a        (alu_a),
        .b        (alu_b),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result),
        .zero     (alu_zero)
    );

    data_memory DMEM (
        .clk    (clk),
        .we     (mem_we),
        .re     (mem_re),
        .addr   (alu_result),
        .wd     (rs2_data),
        .funct3 (funct3),
        .rd     (mem_rd)
    );

    // =========================================================
    // INSTRUCTION FIELD EXTRACTION
    // =========================================================

    assign opcode   = instr[6:0];
    assign rd_addr  = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign funct7   = instr[31:25];

    // =========================================================
    // IMMEDIATE GENERATION
    // sign-extends immediates from instruction bits
    // each format scrambles the bits differently per RISC-V spec
    // =========================================================

    always @* begin
        case (imm_sel)
            // I-type: bits [31:20] sign extended
            3'b001: imm = {{20{instr[31]}}, instr[31:20]};

            // S-type: bits [31:25] and [11:7]
            3'b010: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type: bits [31], [7], [30:25], [11:8], implicit 0
            3'b011: imm = {{19{instr[31]}}, instr[31],
                            instr[7], instr[30:25],
                            instr[11:8], 1'b0};

            // U-type: bits [31:12] shifted left 12
            3'b100: imm = {instr[31:12], 12'd0};

            // J-type: bits [31], [19:12], [20], [30:21], implicit 0
            3'b101: imm = {{11{instr[31]}}, instr[31],
                            instr[19:12], instr[20],
                            instr[30:21], 1'b0};

            // R-type: no immediate
            default: imm = 32'd0;
        endcase
    end

    // =========================================================
    // ALU INPUT SELECTION
    // =========================================================

    // operand A: PC for AUIPC/JAL, rs1 for everything else
    assign alu_a = (opcode == 7'b0010111 ||
                    opcode == 7'b1101111) ? pc : rs1_data;

    // operand B: immediate or rs2
    assign alu_b = alu_src ? imm : rs2_data;

    // =========================================================
    // BRANCH LOGIC
    // determines if a branch is actually taken
    // based on funct3 and ALU result
    // =========================================================

    always @* begin
        branch_taken = 0;
        if (branch) begin
            case (funct3)
                3'b000: branch_taken = alu_zero;          // BEQ
                3'b001: branch_taken = ~alu_zero;         // BNE
                3'b100: branch_taken = alu_result[0];     // BLT
                3'b101: branch_taken = ~alu_result[0];    // BGE
                3'b110: branch_taken = alu_result[0];     // BLTU
                3'b111: branch_taken = ~alu_result[0];    // BGEU
                default: branch_taken = 0;
            endcase
        end
    end

    // =========================================================
    // PC NEXT LOGIC
    // =========================================================

    assign pc_plus4  = pc + 32'd4;
    assign pc_branch = pc + imm;                          // branch target
    assign pc_jump   = (opcode == 7'b1100111) ?
                        (rs1_data + imm) & ~32'd1 :       // JALR: rs1+imm, clear bit 0
                        pc + imm;                         // JAL: pc+imm

    // select next PC
    assign pc_next = jump         ? pc_jump   :
                     branch_taken ? pc_branch :
                                    pc_plus4;

    // PC write enable — always updating
    assign pc_we = 1'b1;

    // =========================================================
    // WRITEBACK SELECTION
    // what gets written back to the register file
    // =========================================================

    assign wb_data = (wb_sel == 2'b01) ? mem_rd    :   // load
                     (wb_sel == 2'b10) ? pc_plus4  :   // JAL/JALR return addr
                                         alu_result;   // ALU result

endmodule