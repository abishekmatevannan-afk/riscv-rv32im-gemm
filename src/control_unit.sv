// RV32I Control Unit
// Decodes 32-bit instruction into control signals
// Pure combinational logic — no clock

module control_unit (
    input  logic [31:0] instr,       // full 32-bit instruction

    // control outputs
    output logic        reg_we,      // register file write enable
    output logic        mem_we,      // data memory write enable
    output logic        mem_re,      // data memory read enable
    output logic        alu_src,     // 0=rs2, 1=immediate
    output logic [1:0]  wb_sel,      // writeback: 00=ALU 01=MEM 10=PC+4
    output logic        branch,      // is a branch instruction
    output logic        jump,        // is a jump instruction
    output logic [3:0]  alu_ctrl,    // ALU operation
    output logic [2:0]  imm_sel,      // immediate format select
    // exception outputs
    output logic        illegal,     // unrecognized or malformed instruction
    output logic        ecall,       // ECALL instruction
    output logic        ebreak,      // EBREAK instruction (breakpoint, mcause=3)
    output logic        mret,        // MRET instruction
 
    // CSR outputs
    output logic        csr_we,      // write to a CSR this cycle
    output logic [11:0] csr_addr,    // CSR address (instr[31:20])
    output logic [2:0]  csr_funct3   // CSR operation type (CSRRW/CSRRS/etc.)
);

    // extract instruction fields
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [11:0] funct12;  // for SYSTEM instructions, use full imm[11:0] as funct

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign funct12 = instr[31:20];  // CSR address / SYSTEM sub-opcode lives in instr[31:20]

    // opcode definitions
    localparam OP_R      = 7'b0110011;
    localparam OP_I      = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_SYSTEM = 7'b1110011;
    localparam OP_FENCE  = 7'b0001111;  // FENCE / FENCE.I — treated as NOP
    localparam OP_CUSTOM = 7'b0001011;  // custom SIMD opcode

    // immediate format select encodings
    localparam IMM_R = 3'b000;
    localparam IMM_I = 3'b001;
    localparam IMM_S = 3'b010;
    localparam IMM_B = 3'b011;
    localparam IMM_U = 3'b100;
    localparam IMM_J = 3'b101;

    // ALU control encodings (match alu.sv)
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;
    localparam ALU_LUI  = 4'b1010;

    // ECALL:  opcode=SYSTEM funct3=000 funct12=000000000000
    // EBREAK: opcode=SYSTEM funct3=000 funct12=000000000001 (treat as NOP)
    // MRET:   opcode=SYSTEM funct3=000 funct12=001100000010
    // CSRRW:  opcode=SYSTEM funct3=001
    // CSRRS:  opcode=SYSTEM funct3=010
    // CSRRC:  opcode=SYSTEM funct3=011
    // CSRRWI: opcode=SYSTEM funct3=101
    // CSRRSI: opcode=SYSTEM funct3=110
    // CSRRCI: opcode=SYSTEM funct3=111
 
    always_comb begin
        // safe defaults
        reg_we     = 0;
        mem_we     = 0;
        mem_re     = 0;
        alu_src    = 0;
        wb_sel     = 2'b00;
        branch     = 0;
        jump       = 0;
        alu_ctrl   = ALU_ADD;
        imm_sel    = IMM_R;
        illegal    = 0;
        ecall      = 0;
        ebreak     = 0;
        mret       = 0;
        csr_we     = 0;
        csr_addr   = 12'd0;
        csr_funct3 = 3'd0;

        case (opcode)

            // R-type: ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
            OP_R: begin
                reg_we  = 1;
                alu_src = 0;        // use rs2
                wb_sel  = 2'b00;    // write ALU result
                imm_sel = IMM_R;

                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? ALU_SUB : ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            // I-type: ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU
            OP_I: begin
                reg_we  = 1;
                alu_src = 1;        // use immediate
                wb_sel  = 2'b00;
                imm_sel = IMM_I;

                case (funct3)
                    3'b000: alu_ctrl = ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            // Load: LW LH LB LHU LBU
            OP_LOAD: begin
                reg_we  = 1;
                mem_re  = 1;
                alu_src = 1;        // base + offset
                wb_sel  = 2'b01;    // write memory data
                imm_sel = IMM_I;
                alu_ctrl = ALU_ADD; // compute address
            end

            // Store: SW SH SB
            OP_STORE: begin
                mem_we  = 1;
                alu_src = 1;        // base + offset
                imm_sel = IMM_S;
                alu_ctrl = ALU_ADD; // compute address
            end

            // Branch: BEQ BNE BLT BGE BLTU BGEU
            OP_BRANCH: begin
                branch  = 1;
                alu_src = 0;        // compare registers
                imm_sel = IMM_B;

                // ALU computes comparison
                // branch logic in top level checks result
                case (funct3)
                    3'b000: alu_ctrl = ALU_SUB;   // BEQ: zero flag
                    3'b001: alu_ctrl = ALU_SUB;   // BNE: zero flag inverted
                    3'b100: alu_ctrl = ALU_SLT;   // BLT
                    3'b101: alu_ctrl = ALU_SLT;   // BGE: result inverted
                    3'b110: alu_ctrl = ALU_SLTU;  // BLTU
                    3'b111: alu_ctrl = ALU_SLTU;  // BGEU: result inverted
                    default: begin alu_ctrl = ALU_SUB; illegal = 1; end
                endcase
            end

            // JAL: jump and link
            OP_JAL: begin
                reg_we  = 1;
                jump    = 1;
                wb_sel  = 2'b10;    // write PC+4 to rd
                imm_sel = IMM_J;
                alu_ctrl = ALU_ADD;
            end

            // JALR: jump and link register
            OP_JALR: begin
                reg_we  = 1;
                jump    = 1;
                alu_src = 1;
                wb_sel  = 2'b10;    // write PC+4 to rd
                imm_sel = IMM_I;
                alu_ctrl = ALU_ADD; // rs1 + imm = target address
            end

            // LUI: load upper immediate
            OP_LUI: begin
                reg_we  = 1;
                alu_src = 1;
                wb_sel  = 2'b00;
                imm_sel = IMM_U;
                alu_ctrl = ALU_LUI; // pass immediate through
            end

            // AUIPC: add upper immediate to PC
            OP_AUIPC: begin
                reg_we  = 1;
                alu_src = 1;
                wb_sel  = 2'b00;
                imm_sel = IMM_U;
                alu_ctrl = ALU_ADD; // PC + upper immediate
            end
            
            // SYSTEM instructions: ECALL, EBREAK, MRET, CSRRS, etc.
             OP_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        // ECALL, EBREAK, MRET — distinguished by funct12
                        case (funct12)
                            12'b000000000000: ecall  = 1;   // ECALL
                            12'b000000000001: ebreak = 1;   // EBREAK — breakpoint exception
                            12'b001100000010: mret   = 1;   // MRET
                            default:          illegal = 1;
                        endcase
                    end
                    // CSR instructions
                    3'b001, 3'b010, 3'b011,   // CSRRW, CSRRS, CSRRC
                    3'b101, 3'b110, 3'b111: begin  // CSRRWI, CSRRSI, CSRRCI
                        reg_we     = 1;        // read CSR into rd (write to x0 is harmless)
                        // CSRRW/CSRRWI always write; CSRRS/CSRRC/CSRRSI/CSRRCI
                        // only write when rs1/uimm != 0 (per RISC-V spec)
                        csr_we     = (funct3 == 3'b001 || funct3 == 3'b101) ? 1'b1
                                   : (instr[19:15] != 5'b00000);
                        csr_addr   = funct12;  // CSR address in instr[31:20]
                        csr_funct3 = funct3;
                        wb_sel     = 2'b00;    // CSR read value flows through ALU result path
                        imm_sel    = IMM_I;
                    end
                    default: illegal = 1;
                endcase
            end
            
            // FENCE / FENCE.I: no-op (in-order single-core, no memory ordering needed)
            OP_FENCE: begin
                // all signals remain at safe defaults — no reg write, no mem, no branch
            end

            // CUSTOM: SIMD operations
            OP_CUSTOM: begin
                reg_we  = 1;
                alu_src = 0;        // always register-register
                wb_sel  = 2'b00;    // write result to rd
                imm_sel = IMM_R;
                alu_ctrl = 4'b0000; // alu_ctrl unused for SIMD
            end

            default: illegal = 1; // unrecognized opcode

        endcase
    end

endmodule