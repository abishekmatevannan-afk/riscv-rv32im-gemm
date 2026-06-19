// RISC-V Machine-mode CSR Register File
// Supports: mstatus, mie, mtvec, mepc, mcause, mip
//
// CSR addresses:
//   0x300  mstatus  — bit 3 = MIE (machine interrupt enable)
//   0x304  mie      — bit 11 = MEIE (machine external interrupt enable)
//   0x305  mtvec    — trap vector base address
//   0x341  mepc     — exception PC (saved on trap)
//   0x342  mcause   — trap cause (bit 31 = interrupt, lower bits = code)
//   0x344  mip      — interrupt pending (read-only)
//
// Trap causes used in this design:
//   2   illegal instruction
//   4   load address misaligned
//   6   store address misaligned
//   11  environment call (ECALL)
//   0x80000011  external interrupt (machine external interrupt)

module csr_regfile (
    input  logic        clk,
    input  logic        rst,

    // CSR instruction interface (from EX stage)
    input  logic        csr_we,          // write enable
    input  logic [11:0] csr_addr,        // CSR address
    input  logic [31:0] csr_wd,          // write data
    input  logic [2:0]  csr_funct3,      // 001=CSRRW 010=CSRRS 011=CSRRC (imm variants: 101/110/111)
    input  logic [4:0]  csr_rs1_addr,    // rs1 register address (x0 suppresses write on CSRRS/CSRRC)
    output logic [31:0] csr_rd,          // read data

    // trap interface (from exception unit)
    input  logic        trap,            // take a trap this cycle
    input  logic [31:0] trap_cause,      // mcause value
    input  logic [31:0] trap_epc,        // PC to save in mepc
    input  logic        mret,            // MRET instruction

    // interrupt pending inputs
    input  logic        ext_irq,         // external interrupt line

    // outputs to pipeline
    output logic [31:0] mtvec_out,       // trap vector
    output logic [31:0] mepc_out,        // exception return PC
    output logic        mie_global,      // global interrupt enable (mstatus.MIE)
    output logic        meie             // machine external interrupt enable (mie.MEIE)
);

    // CSR storage
    logic [31:0] mstatus;   // only bit 3 (MIE) is implemented
    logic [31:0] mie_reg;   // only bit 11 (MEIE) is implemented
    logic [31:0] mtvec;
    logic [31:0] mepc;
    logic [31:0] mcause;

    // mip is read-only, reflects live interrupt inputs
    logic [31:0] mip;
    assign mip = {20'd0, ext_irq, 11'd0};  // bit 11 = MEIP

    // outputs
    assign mtvec_out  = mtvec;
    assign mepc_out   = mepc;
    assign mie_global = mstatus[3];        // MIE bit
    assign meie       = mie_reg[11];       // MEIE bit

    // CSR read
    always_comb begin
        case (csr_addr)
            12'h300: csr_rd = mstatus;
            12'h304: csr_rd = mie_reg;
            12'h305: csr_rd = mtvec;
            12'h341: csr_rd = mepc;
            12'h342: csr_rd = mcause;
            12'h344: csr_rd = mip;
            default: csr_rd = 32'd0;
        endcase
    end

    // CSR write and trap handling
    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'd0;   // MIE=0 on reset, interrupts disabled
            mie_reg <= 32'd0;
            mtvec   <= 32'd0;
            mepc    <= 32'd0;
            mcause  <= 32'd0;
        end else if (trap) begin
            // trap takes priority over CSR write
            mepc    <= trap_epc;
            mcause  <= trap_cause;
            mstatus <= mstatus & ~32'h8;  // clear MIE (disable interrupts in handler)
        end else if (mret) begin
            mstatus <= mstatus | 32'h8;   // restore MIE on return
        end else if (csr_we) begin
            // csr_funct3[1:0]: 01=RW, 10=RS(set), 11=RC(clear) — same for reg and imm variants
            case (csr_addr)
                12'h300: case (csr_funct3[1:0])
                             2'b01: mstatus <= csr_wd;
                             2'b10: mstatus <= mstatus | csr_wd;
                             2'b11: mstatus <= mstatus & ~csr_wd;
                             default: ;
                         endcase
                12'h304: case (csr_funct3[1:0])
                             2'b01: mie_reg <= csr_wd;
                             2'b10: mie_reg <= mie_reg | csr_wd;
                             2'b11: mie_reg <= mie_reg & ~csr_wd;
                             default: ;
                         endcase
                12'h305: case (csr_funct3[1:0])
                             2'b01: mtvec <= csr_wd;
                             2'b10: mtvec <= mtvec | csr_wd;
                             2'b11: mtvec <= mtvec & ~csr_wd;
                             default: ;
                         endcase
                12'h341: case (csr_funct3[1:0])
                             2'b01: mepc <= csr_wd;
                             2'b10: mepc <= mepc | csr_wd;
                             2'b11: mepc <= mepc & ~csr_wd;
                             default: ;
                         endcase
                12'h342: case (csr_funct3[1:0])
                             2'b01: mcause <= csr_wd;
                             2'b10: mcause <= mcause | csr_wd;
                             2'b11: mcause <= mcause & ~csr_wd;
                             default: ;
                         endcase
                // mip is read-only, writes ignored
                default: ;
            endcase
        end
    end

endmodule