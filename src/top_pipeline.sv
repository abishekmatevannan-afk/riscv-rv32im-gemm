// RV32I 5-Stage Pipelined CPU
// Stages: IF, ID, EX, MEM, WB
// Hazard handling: forwarding, load-use stall, branch flush

module top_pipeline #(
    parameter HEX_FILE = "programs/test1.hex",
    parameter CLKS_PER_BIT = 10416
)(
    input logic clk,
    input logic rst,
    output logic uart_tx_pin
);
    // UART signals
    // =========================================================
    logic        uart_we;
    logic [31:0] uart_rd;
    logic        is_io;

    // IF STAGE SIGNALS
    // =========================================================
    logic [31:0] if_pc;
    logic [31:0] if_pc_plus4;
    logic [31:0] if_instr;
    logic [31:0] pc_next;
    logic        pc_stall;

    // ID STAGE SIGNALS
    // =========================================================
    logic [31:0] id_pc;
    logic [31:0] id_instr;
    logic [31:0] id_pc_plus4;
    logic [6:0]  id_opcode;
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [31:0] id_rs1_data, id_rs2_data;
    logic [31:0] id_imm;
    logic [31:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;

    // control signals from decode
    logic        id_reg_we, id_mem_we, id_mem_re;
    logic        id_alu_src, id_branch, id_jump;
    logic [1:0]  id_wb_sel;
    logic [3:0]  id_alu_ctrl;
    logic [2:0]  id_imm_sel;

  
    // EX STAGE SIGNALS
    // =========================================================
    logic [31:0] ex_pc;
    logic [31:0] ex_pc_plus4;
    logic [31:0] ex_rs1_data, ex_rs2_data;
    logic [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    logic [31:0] ex_imm;
    logic [6:0]  ex_opcode;
    logic [2:0]  ex_funct3;

    // control signals in EX
    logic        ex_reg_we, ex_mem_we, ex_mem_re;
    logic        ex_alu_src, ex_branch, ex_jump;
    logic [1:0]  ex_wb_sel;
    logic [3:0]  ex_alu_ctrl;

    // forwarding mux outputs
    logic [31:0] ex_fwd_a, ex_fwd_b;
    logic [31:0] ex_alu_a, ex_alu_b;
    logic [31:0] ex_alu_result;
    logic        ex_alu_zero;
    logic [31:0] ex_pc_branch, ex_pc_jump;
    logic        ex_branch_taken;

    // forwarding select signals
    logic [1:0]  forward_a, forward_b;


    // MEM STAGE SIGNALS
    // =========================================================
    logic [31:0] mem_alu_result;
    logic        mem_alu_zero;
    logic [31:0] mem_rs2_data;
    logic [4:0]  mem_rd_addr;
    logic [31:0] mem_pc_plus4;
    logic [31:0] mem_read_data;
    logic        mem_reg_we, mem_mem_we, mem_mem_re;
    logic [1:0]  mem_wb_sel;
    logic [2:0]  mem_funct3;


    // WB STAGE SIGNALS
    // =========================================================
    logic [31:0] wb_alu_result;
    logic [31:0] wb_read_data;
    logic [31:0] wb_pc_plus4;
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_we;
    logic [1:0]  wb_wb_sel;
    logic [31:0] wb_data;


    // HAZARD SIGNALS
    // =========================================================
    logic if_id_stall, if_id_flush;
    logic id_ex_flush;


    // IF STAGE
    // =========================================================

    assign if_pc_plus4 = if_pc + 32'd4;

    // PC next selection
    // priority: jump > branch taken > stall > sequential
    assign pc_next = ex_jump         ? ex_pc_jump    :
                     ex_branch_taken ? ex_pc_branch  :
                                       if_pc_plus4;

    program_counter PC (
        .clk     (clk),
        .rst     (rst),
        .pc_we   (!pc_stall),
        .pc_next (pc_next),
        .pc      (if_pc)
    );

    instruction_memory #(.HEX_FILE(HEX_FILE)) IMEM (
        .addr  (if_pc),
        .instr (if_instr)
    );
    
    // IF/ID pipeline register
    if_id_reg IF_ID (
        .clk      (clk),
        .rst      (rst),
        .flush    (if_id_flush),
        .stall    (if_id_stall),
        .if_pc    (if_pc),
        .if_instr (if_instr),
        .id_pc    (id_pc),
        .id_instr (id_instr)
    );


    // ID STAGE
    // =========================================================

    assign id_pc_plus4  = id_pc + 32'd4;
    assign id_opcode    = id_instr[6:0];
    assign id_rd_addr   = id_instr[11:7];
    assign id_funct3    = id_instr[14:12];
    assign id_rs1_addr  = id_instr[19:15];
    assign id_rs2_addr  = id_instr[24:20];
    assign id_funct7    = id_instr[31:25];

    // immediate generation
    assign id_imm_i = {{20{id_instr[31]}}, id_instr[31:20]};
    assign id_imm_s = {{20{id_instr[31]}}, id_instr[31:25], id_instr[11:7]};
    assign id_imm_b = {{19{id_instr[31]}}, id_instr[31], id_instr[7],
                        id_instr[30:25], id_instr[11:8], 1'b0};
    assign id_imm_u = {id_instr[31:12], 12'd0};
    assign id_imm_j = {{11{id_instr[31]}}, id_instr[31], id_instr[19:12],
                        id_instr[20], id_instr[30:21], 1'b0};

    always_comb begin
        case (id_imm_sel)
            3'b001:  id_imm = id_imm_i;
            3'b010:  id_imm = id_imm_s;
            3'b011:  id_imm = id_imm_b;
            3'b100:  id_imm = id_imm_u;
            3'b101:  id_imm = id_imm_j;
            default: id_imm = 32'd0;
        endcase
    end

    control_unit CU (
        .instr    (id_instr),
        .reg_we   (id_reg_we),
        .mem_we   (id_mem_we),
        .mem_re   (id_mem_re),
        .alu_src  (id_alu_src),
        .wb_sel   (id_wb_sel),
        .branch   (id_branch),
        .jump     (id_jump),
        .alu_ctrl (id_alu_ctrl),
        .imm_sel  (id_imm_sel)
    );

    register_file RF (
        .clk (clk),
        .we  (wb_reg_we),
        .rs1 (id_rs1_addr),
        .rs2 (id_rs2_addr),
        .rd  (wb_rd_addr),
        .wd  (wb_data),
        .rd1 (id_rs1_data),
        .rd2 (id_rs2_data)
    );

    // ID/EX pipeline register
    id_ex_reg ID_EX (
        .clk         (clk),
        .rst         (rst),
        .flush       (id_ex_flush),
        .id_pc       (id_pc),
        .id_reg_we   (id_reg_we),
        .id_mem_we   (id_mem_we),
        .id_mem_re   (id_mem_re),
        .id_alu_src  (id_alu_src),
        .id_wb_sel   (id_wb_sel),
        .id_branch   (id_branch),
        .id_jump     (id_jump),
        .id_alu_ctrl (id_alu_ctrl),
        .id_funct3   (id_funct3),
        .id_rs1_data (id_rs1_data),
        .id_rs2_data (id_rs2_data),
        .id_rs1_addr (id_rs1_addr),
        .id_rs2_addr (id_rs2_addr),
        .id_rd_addr  (id_rd_addr),
        .id_imm      (id_imm),
        .id_opcode   (id_opcode),
        .ex_pc       (ex_pc),
        .ex_reg_we   (ex_reg_we),
        .ex_mem_we   (ex_mem_we),
        .ex_mem_re   (ex_mem_re),
        .ex_alu_src  (ex_alu_src),
        .ex_wb_sel   (ex_wb_sel),
        .ex_branch   (ex_branch),
        .ex_jump     (ex_jump),
        .ex_alu_ctrl (ex_alu_ctrl),
        .ex_funct3   (ex_funct3),
        .ex_rs1_data (ex_rs1_data),
        .ex_rs2_data (ex_rs2_data),
        .ex_rs1_addr (ex_rs1_addr),
        .ex_rs2_addr (ex_rs2_addr),
        .ex_rd_addr  (ex_rd_addr),
        .ex_imm      (ex_imm),
        .ex_opcode   (ex_opcode)
    );


    // EX STAGE
    // =========================================================

    assign ex_pc_plus4 = ex_pc + 32'd4;

    // forwarding muxes for ALU operand A
    always_comb begin
        case (forward_a)
            2'b00:   ex_fwd_a = ex_rs1_data;      // no forward
            2'b01:   ex_fwd_a = wb_data;           // from WB
            2'b10:   ex_fwd_a = mem_alu_result;    // from MEM
            default: ex_fwd_a = ex_rs1_data;
        endcase
    end

    // forwarding muxes for ALU operand B
    always_comb begin
        case (forward_b)
            2'b00:   ex_fwd_b = ex_rs2_data;      // no forward
            2'b01:   ex_fwd_b = wb_data;           // from WB
            2'b10:   ex_fwd_b = mem_alu_result;    // from MEM
            default: ex_fwd_b = ex_rs2_data;
        endcase
    end

    // ALU input A: PC for AUIPC/JAL, forwarded rs1 otherwise
    assign ex_alu_a = (ex_opcode == 7'b0010111 ||
                       ex_opcode == 7'b1101111) ? ex_pc : ex_fwd_a;

    // ALU input B: immediate or forwarded rs2
    assign ex_alu_b = ex_alu_src ? ex_imm : ex_fwd_b;

    alu ALU (
        .a        (ex_alu_a),
        .b        (ex_alu_b),
        .alu_ctrl (ex_alu_ctrl),
        .result   (ex_alu_result),
        .zero     (ex_alu_zero)
    );

    // branch resolution
    logic ex_alu_bit0;
    assign ex_alu_bit0 = ex_alu_result[0];

    always_comb begin
        ex_branch_taken = 0;
        if (ex_branch) begin
            case (ex_funct3)
                3'b000: ex_branch_taken = ex_alu_zero;
                3'b001: ex_branch_taken = ~ex_alu_zero;
                3'b100: ex_branch_taken = ex_alu_bit0;
                3'b101: ex_branch_taken = ~ex_alu_bit0;
                3'b110: ex_branch_taken = ex_alu_bit0;
                3'b111: ex_branch_taken = ~ex_alu_bit0;
                default: ex_branch_taken = 0;
            endcase
        end
    end

    // branch and jump target computation
    assign ex_pc_branch = ex_pc + ex_imm;
    assign ex_pc_jump   = (ex_opcode == 7'b1100111) ?
                           (ex_fwd_a + ex_imm) & ~32'd1 :  // JALR
                            ex_pc + ex_imm;                 // JAL

    // forward unit
    forward_unit FU (
        .ex_rs1_addr (ex_rs1_addr),
        .ex_rs2_addr (ex_rs2_addr),
        .mem_rd_addr (mem_rd_addr),
        .mem_reg_we  (mem_reg_we),
        .wb_rd_addr  (wb_rd_addr),
        .wb_reg_we   (wb_reg_we),
        .forward_a   (forward_a),
        .forward_b   (forward_b)
    );

    // EX/MEM pipeline register
    ex_mem_reg EX_MEM (
        .clk           (clk),
        .rst           (rst),
        .ex_reg_we     (ex_reg_we),
        .ex_mem_we     (ex_mem_we),
        .ex_mem_re     (ex_mem_re),
        .ex_wb_sel     (ex_wb_sel),
        .ex_funct3     (ex_funct3),
        .ex_alu_result (ex_alu_result),
        .ex_alu_zero   (ex_alu_zero),
        .ex_rs2_data   (ex_fwd_b),
        .ex_rd_addr    (ex_rd_addr),
        .ex_pc_plus4   (ex_pc_plus4),
        .mem_reg_we    (mem_reg_we),
        .mem_mem_we    (mem_mem_we),
        .mem_mem_re    (mem_mem_re),
        .mem_wb_sel    (mem_wb_sel),
        .mem_funct3    (mem_funct3),
        .mem_alu_result(mem_alu_result),
        .mem_alu_zero  (mem_alu_zero),
        .mem_rs2_data  (mem_rs2_data),
        .mem_rd_addr   (mem_rd_addr),
        .mem_pc_plus4  (mem_pc_plus4)
    );


    // MEM STAGE
    // =========================================================

    data_memory DMEM (
        .clk    (clk),
        .we     (mem_mem_we),
        .re     (mem_mem_re),
        .addr   (mem_alu_result),
        .wd     (mem_rs2_data),
        .funct3 (mem_funct3),
        .rd     (mem_read_data),
        .is_io  (is_io)
    );

    // IO write enable — only write to UART when address is in IO region
    assign uart_we = mem_mem_we && is_io;

    uart_mem_map #(.CLKS_PER_BIT(CLKS_PER_BIT)) UART_MAP (
        .clk         (clk),
        .rst         (rst),
        .we          (uart_we),
        .addr        (mem_alu_result),
        .wd          (mem_rs2_data),
        .rd          (uart_rd),
        .uart_tx_pin (uart_tx_pin)
    );
    

    // MEM/WB pipeline register
    
        // select read data from RAM or UART based on address
    logic [31:0] mem_read_data_mux;
    assign mem_read_data_mux = is_io ? uart_rd : mem_read_data;
    mem_wb_reg MEM_WB (
        .clk            (clk),
        .rst            (rst),
        .mem_reg_we     (mem_reg_we),
        .mem_wb_sel     (mem_wb_sel),
        .mem_rd_addr    (mem_rd_addr),
        .mem_alu_result (mem_alu_result),
        .mem_read_data  (mem_read_data_mux),
        .mem_pc_plus4   (mem_pc_plus4),
        .wb_reg_we      (wb_reg_we),
        .wb_wb_sel      (wb_wb_sel),
        .wb_rd_addr     (wb_rd_addr),
        .wb_alu_result  (wb_alu_result),
        .wb_read_data   (wb_read_data),
        .wb_pc_plus4    (wb_pc_plus4)
    );


    // WB STAGE
    // =========================================================

    assign wb_data = (wb_wb_sel == 2'b01) ? wb_read_data  :
                     (wb_wb_sel == 2'b10) ? wb_pc_plus4   :
                                             wb_alu_result;


    // HAZARD UNIT
    // =========================================================

    hazard_unit HU (
        .ex_mem_re    (ex_mem_re),
        .ex_rd_addr   (ex_rd_addr),
        .id_rs1_addr  (id_rs1_addr),
        .id_rs2_addr  (id_rs2_addr),
        .ex_branch    (ex_branch),
        .ex_jump      (ex_jump),
        .branch_taken (ex_branch_taken),
        .pc_stall     (pc_stall),
        .if_id_stall  (if_id_stall),
        .if_id_flush  (if_id_flush),
        .id_ex_flush  (id_ex_flush)
    );

endmodule