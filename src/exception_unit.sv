// Purely combinational — no state
//
// Priority (highest to lowest):
//   1. External interrupt (if MIE=1 and MEIE=1 and ext_irq=1)
//   2. Illegal instruction
//   3. Load address misaligned
//   4. Store address misaligned
//   5. ECALL
//
// Misalignment detection:
//   LH/LHU (funct3=001/101): addr[0] must be 0
//   LW     (funct3=010):     addr[1:0] must be 00
//   SH     (funct3=001):     addr[0] must be 0
//   SW     (funct3=010):     addr[1:0] must be 00

module exception_unit (
    // pipeline signals
    input  logic [31:0] ex_pc,           // PC of instruction in EX
    input  logic        ex_valid,        // is there a real instruction in EX?
    input  logic        ex_illegal,      // control unit flagged illegal instruction
    input  logic        ex_ecall,        // ECALL instruction in EX
    input  logic        ex_mem_re,       // load in EX
    input  logic        ex_mem_we,       // store in EX
    input  logic [2:0]  ex_funct3,       // access width for load/store
    input  logic [31:0] ex_alu_result,   // computed address for load/store

    // interrupt inputs
    input  logic        ext_irq,         // external interrupt pending
    input  logic        mie_global,      // mstatus.MIE
    input  logic        meie,            // mie.MEIE

    // outputs
    output logic        trap,            // take a trap this cycle
    output logic [31:0] trap_cause,      // mcause value to write
    output logic [31:0] trap_epc        // PC to save in mepc
);

    // misalignment detection
    logic load_misalign;
    logic store_misalign;

    logic addr_bit0;
    logic addr_bit1;
    assign addr_bit0 = ex_alu_result[0];
    assign addr_bit1 = ex_alu_result[1];

    always_comb begin
        load_misalign = 0;
        if (ex_mem_re && ex_valid) begin
            case (ex_funct3)
                3'b001: load_misalign = addr_bit0;
                3'b101: load_misalign = addr_bit0;
                3'b010: load_misalign = addr_bit0 | addr_bit1;
                default: load_misalign = 0;
            endcase
        end
    end

    always_comb begin
        store_misalign = 0;
        if (ex_mem_we && ex_valid) begin
            case (ex_funct3)
                3'b001: store_misalign = addr_bit0;
                3'b010: store_misalign = addr_bit0 | addr_bit1;
                default: store_misalign = 0;
            endcase
        end
    end

    // interrupt condition
    logic take_interrupt;
    assign take_interrupt = ext_irq && mie_global && meie;

    // trap arbitration
    always_comb begin
        trap       = 0;
        trap_cause = 32'd0;
        trap_epc   = ex_pc;

        if (!ex_valid) begin
            // bubble in EX — only interrupts can fire
            if (take_interrupt) begin
                trap       = 1;
                trap_cause = 32'h80000011;  // machine external interrupt
                trap_epc   = ex_pc;
            end
        end else begin
            // priority order
            if (take_interrupt) begin
                trap       = 1;
                trap_cause = 32'h80000011;
                trap_epc   = ex_pc;
            end else if (ex_illegal) begin
                trap       = 1;
                trap_cause = 32'd2;         // illegal instruction
                trap_epc   = ex_pc;
            end else if (load_misalign) begin
                trap       = 1;
                trap_cause = 32'd4;         // load address misaligned
                trap_epc   = ex_pc;
            end else if (store_misalign) begin
                trap       = 1;
                trap_cause = 32'd6;         // store address misaligned
                trap_epc   = ex_pc;
            end else if (ex_ecall) begin
                trap       = 1;
                trap_cause = 32'd11;        // ECALL from M-mode
                trap_epc   = ex_pc;
            end
        end
    end

endmodule