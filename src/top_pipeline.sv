// RV32I 5-Stage Pipelined CPU
// Stages: IF, ID, EX, MEM, WB
// Hazard handling: forwarding, load-use stall, branch flush

module top_pipeline #(
    parameter HEX_FILE = "programs/test1.hex",
    parameter CLKS_PER_BIT = 10416
)(
    input logic clk,
    input logic rst,
    input  logic uart_rx_pin,
    output logic uart_tx_pin
);
    // performance counter signals
    // =========================================================
    logic        is_perf;
    logic [31:0] perf_rd;
    logic        instr_retired;

    // Branch predictor signals
    // =========================================================
    logic        bp_predict_taken;
    logic [31:0] bp_predict_target;
    logic        ex_predict_taken;
    logic [31:0] ex_predict_target;
    logic        ex_jump_mispredict;
    logic        mispredict;

    // UART / IO signals
    // =========================================================
    // io_m_rd   : read data returned by the IO manager (replaces uart_rd)
    // is_uart   : gates the IO manager — same as is_io but excludes PMU
    // is_io     : true for any 0xFFFF.... address (UART and PMU)
    // accel_rd  : read data from the systolic-array accelerator manager
    // is_accel  : true for 0xFFFE.... addresses (systolic array register map)
    logic [31:0] io_m_rd;
    logic        is_uart;
    logic        is_io;
    logic [31:0] accel_rd;
    logic        is_accel;

    // IF STAGE SIGNALS
    // =========================================================
    logic [31:0] if_pc;
    logic [31:0] if_pc_plus4;
    logic [31:0] if_instr;
    logic [31:0] pc_next;
    logic        pc_stall;
    logic        if_is_branch;

    // ID STAGE SIGNALS
    // =========================================================
    logic [31:0] id_pc;
    logic [31:0] id_instr;
    logic [31:0] id_pc_plus4;
    logic        id_predict_taken;
    logic [31:0] id_predict_target;
    logic [6:0]  id_opcode;
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [31:0] id_rs1_data, id_rs2_data;
    logic [31:0] id_imm;
    logic [31:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;

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
    logic [6:0]  ex_funct7;

    logic [31:0] simd_result;
    logic [31:0] simd_result_q;
    logic        simd_valid;
    logic        is_simd;
    logic        simd_busy;
    logic        simd_stall;
    logic [31:0] muldiv_result;
    logic        is_muldiv;
    logic        div_busy;
    logic [31:0] ex_result;

    logic        ex_reg_we, ex_mem_we, ex_mem_re;
    logic        ex_alu_src, ex_branch, ex_jump;
    logic [1:0]  ex_wb_sel;
    logic [3:0]  ex_alu_ctrl;

    logic [31:0] ex_fwd_a, ex_fwd_b, ex_fwd_acc;
    logic [31:0] ex_alu_a, ex_alu_b;
    logic [31:0] ex_alu_result;
    logic        ex_alu_zero;
    logic [31:0] ex_pc_branch, ex_pc_jump;
    logic        ex_branch_taken;

    logic [1:0]  forward_a, forward_b, forward_acc;

    // PMACC: rd is both source (accumulator) and destination
    logic        id_is_pmacc;
    logic        ex_is_pmacc;
    logic [31:0] id_acc_data;       // RF third-port read (rd register value)
    logic [31:0] id_acc_data_fwd;   // WB-bypassed accumulator value
    logic [31:0] ex_acc_data;       // Latched through ID/EX register

    // cache signals
    logic        cache_stall;
    logic        cache_hit;
    logic        cache_miss;
    logic [31:0] cache_rd;

    // pipeline stall signals
    logic        id_ex_stall;
    logic        ex_mem_stall;
    logic        mem_wb_stall;

    // MEM STAGE SIGNALS
    // =========================================================
    logic [31:0] mem_alu_result;
    logic        mem_alu_zero;
    logic [31:0] mem_rs2_data;
    logic [4:0]  mem_rd_addr;
    logic [31:0] mem_pc_plus4;
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

    // icache signals
    logic        icache_stall;
    logic        icache_hit;
    logic        icache_miss;
    logic [31:0] icache_rd;
    logic        ic_mem_re;
    logic [31:0] ic_mem_addr;
    logic [31:0] ic_mem_rd;

    // EXCEPTION AND CSR SIGNALS
    // =========================================================
    logic        ex_illegal, ex_ecall, ex_ebreak, ex_mret;
    logic        ex_csr_we;
    logic [11:0] ex_csr_addr;
    logic [2:0]  ex_csr_funct3;
    logic        id_illegal, id_ecall, id_ebreak, id_mret;
    logic        id_csr_we;
    logic [11:0] id_csr_addr;
    logic [2:0]  id_csr_funct3;
    logic        trap;
    logic [31:0] trap_cause, trap_epc;
    logic [31:0] csr_rd;
    logic [31:0] mtvec_out, mepc_out;
    logic        mie_global, meie;
    logic        ext_irq;
    logic        ex_valid;
    logic        uart_irq;
    logic        id_valid;

    // AXI4-Lite fabric signals
    // =========================================================
    // icache manager → interconnect (AR/R only)
    logic        ic_m_arvalid, ic_m_arready;
    logic [31:0] ic_m_araddr;
    logic        ic_m_rvalid,  ic_m_rready;
    logic [31:0] ic_m_rdata;
    logic [1:0]  ic_m_rresp;

    // dcache manager → interconnect (AW/W/B/AR/R)
    logic        dc_m_awvalid, dc_m_awready;
    logic [31:0] dc_m_awaddr;
    logic        dc_m_wvalid,  dc_m_wready;
    logic [31:0] dc_m_wdata;
    logic [3:0]  dc_m_wstrb;
    logic        dc_m_bvalid,  dc_m_bready;
    logic [1:0]  dc_m_bresp;
    logic        dc_m_arvalid, dc_m_arready;
    logic [31:0] dc_m_araddr;
    logic        dc_m_rvalid,  dc_m_rready;
    logic [31:0] dc_m_rdata;
    logic [1:0]  dc_m_rresp;

    // IO manager → interconnect (AW/W/B/AR/R)
    logic        io_m_awvalid, io_m_awready;
    logic [31:0] io_m_awaddr;
    logic        io_m_wvalid,  io_m_wready;
    logic [31:0] io_m_wdata;
    logic [3:0]  io_m_wstrb;
    logic        io_m_bvalid,  io_m_bready;
    logic [1:0]  io_m_bresp;
    logic        io_m_arvalid, io_m_arready;
    logic [31:0] io_m_araddr;
    logic        io_m_rvalid,  io_m_rready;
    logic [31:0] io_m_rdata;
    logic [1:0]  io_m_rresp;

    // interconnect → ISRAM subordinate (s0, read-only)
    logic        s0_arvalid, s0_arready;
    logic [31:0] s0_araddr;
    logic        s0_rvalid,  s0_rready;
    logic [31:0] s0_rdata;
    logic [1:0]  s0_rresp;

    // interconnect → DSRAM subordinate (s1, read/write)
    logic        s1_awvalid, s1_awready;
    logic [31:0] s1_awaddr;
    logic        s1_wvalid,  s1_wready;
    logic [31:0] s1_wdata;
    logic [3:0]  s1_wstrb;
    logic        s1_bvalid,  s1_bready;
    logic [1:0]  s1_bresp;
    logic        s1_arvalid, s1_arready;
    logic [31:0] s1_araddr;
    logic        s1_rvalid,  s1_rready;
    logic [31:0] s1_rdata;
    logic [1:0]  s1_rresp;

    // interconnect → UART subordinate (s2, read/write)
    logic        s2_awvalid, s2_awready;
    logic [31:0] s2_awaddr;
    logic        s2_wvalid,  s2_wready;
    logic [31:0] s2_wdata;
    logic [3:0]  s2_wstrb;
    logic        s2_bvalid,  s2_bready;
    logic [1:0]  s2_bresp;
    logic        s2_arvalid, s2_arready;
    logic [31:0] s2_araddr;
    logic        s2_rvalid,  s2_rready;
    logic [31:0] s2_rdata;
    logic [1:0]  s2_rresp;

    // accel manager → interconnect (AW/W/B/AR/R)
    logic        ac_m_awvalid, ac_m_awready;
    logic [31:0] ac_m_awaddr;
    logic        ac_m_wvalid,  ac_m_wready;
    logic [31:0] ac_m_wdata;
    logic [3:0]  ac_m_wstrb;
    logic        ac_m_bvalid,  ac_m_bready;
    logic [1:0]  ac_m_bresp;
    logic        ac_m_arvalid, ac_m_arready;
    logic [31:0] ac_m_araddr;
    logic        ac_m_rvalid,  ac_m_rready;
    logic [31:0] ac_m_rdata;
    logic [1:0]  ac_m_rresp;

    // interconnect → parallel MAC subordinate (s3, 0xFFFE, read/write)
    logic        s3_awvalid, s3_awready;
    logic [31:0] s3_awaddr;
    logic        s3_wvalid,  s3_wready;
    logic [31:0] s3_wdata;
    logic [3:0]  s3_wstrb;
    logic        s3_bvalid,  s3_bready;
    logic [1:0]  s3_bresp;
    logic        s3_arvalid, s3_arready;
    logic [31:0] s3_araddr;
    logic        s3_rvalid,  s3_rready;
    logic [31:0] s3_rdata;
    logic [1:0]  s3_rresp;

    // systolic manager → interconnect (AW/W/B/AR/R)
    logic        sy_m_awvalid, sy_m_awready;
    logic [31:0] sy_m_awaddr;
    logic        sy_m_wvalid,  sy_m_wready;
    logic [31:0] sy_m_wdata;
    logic [3:0]  sy_m_wstrb;
    logic        sy_m_bvalid,  sy_m_bready;
    logic [1:0]  sy_m_bresp;
    logic        sy_m_arvalid, sy_m_arready;
    logic [31:0] sy_m_araddr;
    logic        sy_m_rvalid,  sy_m_rready;
    logic [31:0] sy_m_rdata;
    logic [1:0]  sy_m_rresp;

    // interconnect → systolic array subordinate (s4, 0xFFFD, read/write)
    logic        s4_awvalid, s4_awready;
    logic [31:0] s4_awaddr;
    logic        s4_wvalid,  s4_wready;
    logic [31:0] s4_wdata;
    logic [3:0]  s4_wstrb;
    logic        s4_bvalid,  s4_bready;
    logic [1:0]  s4_bresp;
    logic        s4_arvalid, s4_arready;
    logic [31:0] s4_araddr;
    logic        s4_rvalid,  s4_rready;
    logic [31:0] s4_rdata;
    logic [1:0]  s4_rresp;

    logic [31:0] systolic_m_rd;
    logic        is_systolic;

    // dcache → dcache manager intermediate wires
    // (replaces old dmem_* wires that went directly to data_memory)
    logic        dmem_we, dmem_re;
    logic [31:0] dmem_addr, dmem_wd, dmem_rd;
    logic [2:0]  dmem_funct3;


    // IF STAGE
    // =========================================================

    assign if_pc_plus4  = if_pc + 32'd4;
    assign if_is_branch = (if_instr[6:0] == 7'b1100011);

    assign ex_jump_mispredict = ex_jump &&
                                (!ex_predict_taken || ex_predict_target != ex_pc_jump);

    assign pc_next = trap                ? mtvec_out  :
                     ex_mret             ? mepc_out   :
                     ex_jump_mispredict  ? ex_pc_jump :
                     mispredict          ? (ex_branch_taken ? ex_pc_branch : ex_pc_plus4) :
                     bp_predict_taken    ? bp_predict_target :
                                          if_pc_plus4;

    program_counter PC (
        .clk     (clk),
        .rst     (rst),
        .stall   (pc_stall),
        .pc_we   (1'b1),
        .pc_next (pc_next),
        .pc      (if_pc)
    );

    branch_predictor BP (
        .clk             (clk),
        .rst             (rst),
        .if_pc           (if_pc),
        .predict_taken   (bp_predict_taken),
        .predict_target  (bp_predict_target),
        .ex_branch       (ex_branch || ex_jump),
        .ex_pc           (ex_pc),
        .ex_actual_taken (ex_branch ? ex_branch_taken : 1'b1),
        .ex_actual_target(ex_jump   ? ex_pc_jump      : ex_pc_branch)
    );

    // AXI4-Lite fabric
    // =========================================================
    // icache manager: converts icache mem_re/mem_addr to AR/R channels
    axi4_lite_icache_manager ICACHE_MGR (
        .mem_re  (ic_mem_re),
        .mem_addr(ic_mem_addr),
        .mem_rd  (ic_mem_rd),
        .arvalid (ic_m_arvalid), .araddr(ic_m_araddr), .arready(ic_m_arready),
        .rvalid  (ic_m_rvalid),  .rdata (ic_m_rdata),
        .rresp   (ic_m_rresp),   .rready(ic_m_rready)
    );

    // dcache manager: converts dcache mem_we/mem_re/mem_addr to AXI channels
    axi4_lite_dcache_manager DCACHE_MGR (
        .mem_we  (dmem_we),
        .mem_re  (dmem_re),
        .mem_addr(dmem_addr),
        .mem_wd  (dmem_wd),
        .mem_rd  (dmem_rd),
        .awvalid (dc_m_awvalid), .awaddr(dc_m_awaddr), .awready(dc_m_awready),
        .wvalid  (dc_m_wvalid),  .wdata (dc_m_wdata),
        .wstrb   (dc_m_wstrb),   .wready(dc_m_wready),
        .bvalid  (dc_m_bvalid),  .bresp (dc_m_bresp),  .bready(dc_m_bready),
        .arvalid (dc_m_arvalid), .araddr(dc_m_araddr), .arready(dc_m_arready),
        .rvalid  (dc_m_rvalid),  .rdata (dc_m_rdata),
        .rresp   (dc_m_rresp),   .rready(dc_m_rready)
    );

    // IO manager: generates AXI transactions for UART loads and stores.
    // Purely combinational — UART sub responds same cycle (rvalid=arvalid),
    // so the pipeline timing is identical to the old direct connection.
    assign is_uart  = is_io && !is_perf;
    assign is_accel    = (mem_alu_result[31:16] == 16'hFFFE);
    assign is_systolic = (mem_alu_result[31:16] == 16'hFFFD);

    axi4_lite_accel_manager ACCEL_MGR (
        .accel_active(is_accel),
        .mem_re      (mem_mem_re),
        .mem_we      (mem_mem_we),
        .mem_addr    (mem_alu_result),
        .mem_wdata   (mem_rs2_data),
        .accel_rd    (accel_rd),
        .arvalid     (ac_m_arvalid), .arready(ac_m_arready), .araddr(ac_m_araddr),
        .rvalid      (ac_m_rvalid),  .rready (ac_m_rready),
        .rdata       (ac_m_rdata),   .rresp  (ac_m_rresp),
        .awvalid     (ac_m_awvalid), .awready(ac_m_awready), .awaddr(ac_m_awaddr),
        .wvalid      (ac_m_wvalid),  .wready (ac_m_wready),
        .wdata       (ac_m_wdata),   .wstrb  (ac_m_wstrb),
        .bvalid      (ac_m_bvalid),  .bready (ac_m_bready)
    );

    axi4_lite_accel_manager SYSTOLIC_MGR (
        .accel_active(is_systolic),
        .mem_re      (mem_mem_re),
        .mem_we      (mem_mem_we),
        .mem_addr    (mem_alu_result),
        .mem_wdata   (mem_rs2_data),
        .accel_rd    (systolic_m_rd),
        .arvalid     (sy_m_arvalid), .arready(sy_m_arready), .araddr(sy_m_araddr),
        .rvalid      (sy_m_rvalid),  .rready (sy_m_rready),
        .rdata       (sy_m_rdata),   .rresp  (sy_m_rresp),
        .awvalid     (sy_m_awvalid), .awready(sy_m_awready), .awaddr(sy_m_awaddr),
        .wvalid      (sy_m_wvalid),  .wready (sy_m_wready),
        .wdata       (sy_m_wdata),   .wstrb  (sy_m_wstrb),
        .bvalid      (sy_m_bvalid),  .bready (sy_m_bready)
    );

    axi4_lite_io_manager IO_MGR (
        .io_active (is_uart),
        .mem_re    (mem_mem_re),
        .mem_we    (mem_mem_we),
        .mem_addr  (mem_alu_result),
        .mem_wdata (mem_rs2_data),
        .io_rd     (io_m_rd),
        .arvalid   (io_m_arvalid), .arready(io_m_arready), .araddr(io_m_araddr),
        .rvalid    (io_m_rvalid),  .rready (io_m_rready),
        .rdata     (io_m_rdata),   .rresp  (io_m_rresp),
        .awvalid   (io_m_awvalid), .awready(io_m_awready), .awaddr(io_m_awaddr),
        .wvalid    (io_m_wvalid),  .wready (io_m_wready),
        .wdata     (io_m_wdata),   .wstrb  (io_m_wstrb),
        .bvalid    (io_m_bvalid),  .bready (io_m_bready)
    );

    // interconnect: icache→ISRAM, dcache→DSRAM, IO manager→UART, accel→systolic
    axi4_lite_interconnect XBAR (
        // M0: icache → S0: ISRAM
        .m0_arvalid(ic_m_arvalid), .m0_arready(ic_m_arready),
        .m0_araddr (ic_m_araddr),
        .m0_rvalid (ic_m_rvalid),  .m0_rready (ic_m_rready),
        .m0_rdata  (ic_m_rdata),   .m0_rresp  (ic_m_rresp),

        // M1: dcache → S1: DSRAM
        .m1_awvalid(dc_m_awvalid), .m1_awready(dc_m_awready), .m1_awaddr(dc_m_awaddr),
        .m1_wvalid (dc_m_wvalid),  .m1_wready (dc_m_wready),
        .m1_wdata  (dc_m_wdata),   .m1_wstrb  (dc_m_wstrb),
        .m1_bvalid (dc_m_bvalid),  .m1_bready (dc_m_bready),  .m1_bresp (dc_m_bresp),
        .m1_arvalid(dc_m_arvalid), .m1_arready(dc_m_arready), .m1_araddr(dc_m_araddr),
        .m1_rvalid (dc_m_rvalid),  .m1_rready (dc_m_rready),
        .m1_rdata  (dc_m_rdata),   .m1_rresp  (dc_m_rresp),

        // M2: IO manager → S2: UART subordinate
        .m2_awvalid(io_m_awvalid), .m2_awready(io_m_awready), .m2_awaddr(io_m_awaddr),
        .m2_wvalid (io_m_wvalid),  .m2_wready (io_m_wready),
        .m2_wdata  (io_m_wdata),   .m2_wstrb  (io_m_wstrb),
        .m2_bvalid (io_m_bvalid),  .m2_bready (io_m_bready),  .m2_bresp (io_m_bresp),
        .m2_arvalid(io_m_arvalid), .m2_arready(io_m_arready), .m2_araddr(io_m_araddr),
        .m2_rvalid (io_m_rvalid),  .m2_rready (io_m_rready),
        .m2_rdata  (io_m_rdata),   .m2_rresp  (io_m_rresp),

        // M3: accel manager → S3: parallel MAC
        .m3_awvalid(ac_m_awvalid), .m3_awready(ac_m_awready), .m3_awaddr(ac_m_awaddr),
        .m3_wvalid (ac_m_wvalid),  .m3_wready (ac_m_wready),
        .m3_wdata  (ac_m_wdata),   .m3_wstrb  (ac_m_wstrb),
        .m3_bvalid (ac_m_bvalid),  .m3_bready (ac_m_bready),  .m3_bresp (ac_m_bresp),
        .m3_arvalid(ac_m_arvalid), .m3_arready(ac_m_arready), .m3_araddr(ac_m_araddr),
        .m3_rvalid (ac_m_rvalid),  .m3_rready (ac_m_rready),
        .m3_rdata  (ac_m_rdata),   .m3_rresp  (ac_m_rresp),

        // M4: systolic manager → S4: systolic array
        .m4_awvalid(sy_m_awvalid), .m4_awready(sy_m_awready), .m4_awaddr(sy_m_awaddr),
        .m4_wvalid (sy_m_wvalid),  .m4_wready (sy_m_wready),
        .m4_wdata  (sy_m_wdata),   .m4_wstrb  (sy_m_wstrb),
        .m4_bvalid (sy_m_bvalid),  .m4_bready (sy_m_bready),  .m4_bresp (sy_m_bresp),
        .m4_arvalid(sy_m_arvalid), .m4_arready(sy_m_arready), .m4_araddr(sy_m_araddr),
        .m4_rvalid (sy_m_rvalid),  .m4_rready (sy_m_rready),
        .m4_rdata  (sy_m_rdata),   .m4_rresp  (sy_m_rresp),

        // S0: ISRAM
        .s0_arvalid(s0_arvalid), .s0_arready(s0_arready), .s0_araddr(s0_araddr),
        .s0_rvalid (s0_rvalid),  .s0_rready (s0_rready),
        .s0_rdata  (s0_rdata),   .s0_rresp  (s0_rresp),

        // S1: DSRAM
        .s1_awvalid(s1_awvalid), .s1_awready(s1_awready), .s1_awaddr(s1_awaddr),
        .s1_wvalid (s1_wvalid),  .s1_wready (s1_wready),
        .s1_wdata  (s1_wdata),   .s1_wstrb  (s1_wstrb),
        .s1_bvalid (s1_bvalid),  .s1_bready (s1_bready),  .s1_bresp (s1_bresp),
        .s1_arvalid(s1_arvalid), .s1_arready(s1_arready), .s1_araddr(s1_araddr),
        .s1_rvalid (s1_rvalid),  .s1_rready (s1_rready),
        .s1_rdata  (s1_rdata),   .s1_rresp  (s1_rresp),

        // S2: UART subordinate
        .s2_awvalid(s2_awvalid), .s2_awready(s2_awready), .s2_awaddr(s2_awaddr),
        .s2_wvalid (s2_wvalid),  .s2_wready (s2_wready),
        .s2_wdata  (s2_wdata),   .s2_wstrb  (s2_wstrb),
        .s2_bvalid (s2_bvalid),  .s2_bready (s2_bready),  .s2_bresp (s2_bresp),
        .s2_arvalid(s2_arvalid), .s2_arready(s2_arready), .s2_araddr(s2_araddr),
        .s2_rvalid (s2_rvalid),  .s2_rready (s2_rready),
        .s2_rdata  (s2_rdata),   .s2_rresp  (s2_rresp),

        // S3: parallel MAC subordinate
        .s3_awvalid(s3_awvalid), .s3_awready(s3_awready), .s3_awaddr(s3_awaddr),
        .s3_wvalid (s3_wvalid),  .s3_wready (s3_wready),
        .s3_wdata  (s3_wdata),   .s3_wstrb  (s3_wstrb),
        .s3_bvalid (s3_bvalid),  .s3_bready (s3_bready),  .s3_bresp (s3_bresp),
        .s3_arvalid(s3_arvalid), .s3_arready(s3_arready), .s3_araddr(s3_araddr),
        .s3_rvalid (s3_rvalid),  .s3_rready (s3_rready),
        .s3_rdata  (s3_rdata),   .s3_rresp  (s3_rresp),

        // S4: genuine systolic array subordinate
        .s4_awvalid(s4_awvalid), .s4_awready(s4_awready), .s4_awaddr(s4_awaddr),
        .s4_wvalid (s4_wvalid),  .s4_wready (s4_wready),
        .s4_wdata  (s4_wdata),   .s4_wstrb  (s4_wstrb),
        .s4_bvalid (s4_bvalid),  .s4_bready (s4_bready),  .s4_bresp (s4_bresp),
        .s4_arvalid(s4_arvalid), .s4_arready(s4_arready), .s4_araddr(s4_araddr),
        .s4_rvalid (s4_rvalid),  .s4_rready (s4_rready),
        .s4_rdata  (s4_rdata),   .s4_rresp  (s4_rresp)
    );

    // ISRAM: read-only instruction SRAM, initialized from HEX_FILE
    axi4_lite_sram_sub #(
        .DEPTH_WORDS(256),
        .HEX_FILE   (HEX_FILE),
        .READ_ONLY  (1)
    ) ISRAM (
        .clk    (clk),
        .rst    (rst),
        .arvalid(s0_arvalid), .arready(s0_arready), .araddr(s0_araddr),
        .rvalid (s0_rvalid),  .rready (s0_rready),
        .rdata  (s0_rdata),   .rresp  (s0_rresp),
        .awvalid(1'b0), .awready(), .awaddr(32'd0),
        .wvalid (1'b0), .wready (),  .wdata(32'd0), .wstrb(4'd0),
        .bvalid (), .bready(1'b1), .bresp()
    );

    // DSRAM: read/write data SRAM, zero-initialized
    axi4_lite_sram_sub #(
        .DEPTH_WORDS(256),
        .HEX_FILE   (""),
        .READ_ONLY  (0)
    ) DSRAM (
        .clk    (clk),
        .rst    (rst),
        .arvalid(s1_arvalid), .arready(s1_arready), .araddr(s1_araddr),
        .rvalid (s1_rvalid),  .rready (s1_rready),
        .rdata  (s1_rdata),   .rresp  (s1_rresp),
        .awvalid(s1_awvalid), .awready(s1_awready), .awaddr(s1_awaddr),
        .wvalid (s1_wvalid),  .wready (s1_wready),
        .wdata  (s1_wdata),   .wstrb  (s1_wstrb),
        .bvalid (s1_bvalid),  .bready (s1_bready),  .bresp(s1_bresp)
    );

    // UART subordinate: wraps uart_mem_map with an AXI4-Lite interface
    axi4_lite_uart_sub #(.CLKS_PER_BIT(CLKS_PER_BIT)) UART_SUB (
        .clk         (clk),
        .rst         (rst),
        .arvalid     (s2_arvalid), .arready(s2_arready), .araddr(s2_araddr),
        .rvalid      (s2_rvalid),  .rready (s2_rready),
        .rdata       (s2_rdata),   .rresp  (s2_rresp),
        .awvalid     (s2_awvalid), .awready(s2_awready), .awaddr(s2_awaddr),
        .wvalid      (s2_wvalid),  .wready (s2_wready),
        .wdata       (s2_wdata),   .wstrb  (s2_wstrb),
        .bvalid      (s2_bvalid),  .bready (s2_bready),  .bresp (s2_bresp),
        .uart_tx_pin (uart_tx_pin),
        .uart_rx_pin (uart_rx_pin),
        .uart_irq    (uart_irq)
    );

    // Parallel MAC accelerator subordinate at 0xFFFE0000
    parallel_mac_sub ACCEL_SUB (
        .clk    (clk),
        .rst    (rst),
        .arvalid(s3_arvalid), .arready(s3_arready), .araddr(s3_araddr),
        .rvalid (s3_rvalid),  .rready (s3_rready),
        .rdata  (s3_rdata),   .rresp  (s3_rresp),
        .awvalid(s3_awvalid), .awready(s3_awready), .awaddr(s3_awaddr),
        .wvalid (s3_wvalid),  .wready (s3_wready),
        .wdata  (s3_wdata),   .wstrb  (s3_wstrb),
        .bvalid (s3_bvalid),  .bready (s3_bready),  .bresp (s3_bresp)
    );

    // Genuine output-stationary systolic array at 0xFFFD0000
    systolic_array_sub SYSTOLIC_SUB (
        .clk    (clk),
        .rst    (rst),
        .arvalid(s4_arvalid), .arready(s4_arready), .araddr(s4_araddr),
        .rvalid (s4_rvalid),  .rready (s4_rready),
        .rdata  (s4_rdata),   .rresp  (s4_rresp),
        .awvalid(s4_awvalid), .awready(s4_awready), .awaddr(s4_awaddr),
        .wvalid (s4_wvalid),  .wready (s4_wready),
        .wdata  (s4_wdata),   .wstrb  (s4_wstrb),
        .bvalid (s4_bvalid),  .bready (s4_bready),  .bresp (s4_bresp)
    );

    // icache: sits between PC and IF/ID, fills from ISRAM via fabric
    icache ICACHE (
        .clk         (clk),
        .rst         (rst),
        .flush       (if_id_flush),
        .cpu_re      (1'b1),
        .cpu_addr    (if_pc),
        .cpu_rd      (if_instr),
        .icache_stall(icache_stall),
        .icache_hit  (icache_hit),
        .icache_miss (icache_miss),
        .pc_next_i   (pc_next),
        .pc_stall_i  (pc_stall),
        .mem_re      (ic_mem_re),
        .mem_addr    (ic_mem_addr),
        .mem_rd      (ic_mem_rd)
    );

    // IF/ID pipeline register
    if_id_reg IF_ID (
        .clk               (clk),
        .rst               (rst),
        .flush             (if_id_flush),
        .stall             (if_id_stall),
        .if_pc             (if_pc),
        .if_instr          (if_instr),
        .if_predict_taken  (bp_predict_taken),
        .if_predict_target (bp_predict_target),
        .id_pc             (id_pc),
        .id_instr          (id_instr),
        .id_predict_taken  (id_predict_taken),
        .id_predict_target (id_predict_target)
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
        .instr      (id_instr),
        .reg_we     (id_reg_we),
        .mem_we     (id_mem_we),
        .mem_re     (id_mem_re),
        .alu_src    (id_alu_src),
        .wb_sel     (id_wb_sel),
        .branch     (id_branch),
        .jump       (id_jump),
        .alu_ctrl   (id_alu_ctrl),
        .imm_sel    (id_imm_sel),
        .illegal    (id_illegal),
        .ecall      (id_ecall),
        .ebreak     (id_ebreak),
        .mret       (id_mret),
        .csr_we     (id_csr_we),
        .csr_addr   (id_csr_addr),
        .csr_funct3 (id_csr_funct3)
    );

    logic [31:0] id_rs1_data_fwd, id_rs2_data_fwd;

    assign id_rs1_data_fwd = (wb_reg_we && wb_rd_addr != 0 && wb_rd_addr == id_rs1_addr)
                           ? wb_data : id_rs1_data;
    assign id_rs2_data_fwd = (wb_reg_we && wb_rd_addr != 0 && wb_rd_addr == id_rs2_addr)
                           ? wb_data : id_rs2_data;

    // WB bypass for PMACC accumulator: same timing as rs1/rs2 bypass
    assign id_acc_data_fwd = (wb_reg_we && wb_rd_addr != 0 && wb_rd_addr == id_rd_addr)
                           ? wb_data : id_acc_data;

    // PMACC: custom opcode 0001011 (SIMD), funct3=011
    assign id_is_pmacc = (id_opcode == 7'b0001011) && (id_funct3 == 3'b011);
    assign ex_is_pmacc = is_simd && (ex_funct3 == 3'b011);

    assign id_valid = 1'b1;

    register_file RF (
        .clk (clk),
        .rst (rst),
        .we  (wb_reg_we),
        .rs1 (id_rs1_addr),
        .rs2 (id_rs2_addr),
        .rs3 (id_rd_addr),      // third port: rd as accumulator source for PMACC
        .rd  (wb_rd_addr),
        .wd  (wb_data),
        .rd1 (id_rs1_data),
        .rd2 (id_rs2_data),
        .rd3 (id_acc_data)
    );


    id_ex_reg ID_EX (
        .clk           (clk),
        .rst           (rst),
        .flush         (id_ex_flush),
        .id_pc         (id_pc),
        .id_reg_we     (id_reg_we),
        .id_mem_we     (id_mem_we),
        .id_mem_re     (id_mem_re),
        .id_alu_src    (id_alu_src),
        .id_wb_sel     (id_wb_sel),
        .id_branch     (id_branch),
        .id_jump       (id_jump),
        .id_alu_ctrl   (id_alu_ctrl),
        .id_funct3     (id_funct3),
        .id_rs1_data   (id_rs1_data_fwd),
        .id_rs2_data   (id_rs2_data_fwd),
        .id_rs1_addr   (id_rs1_addr),
        .id_rs2_addr   (id_rs2_addr),
        .id_rd_addr    (id_rd_addr),
        .id_imm        (id_imm),
        .id_opcode     (id_opcode),
        .id_illegal    (id_illegal),
        .id_ecall      (id_ecall),
        .id_ebreak     (id_ebreak),
        .id_mret       (id_mret),
        .id_csr_we     (id_csr_we),
        .id_csr_addr   (id_csr_addr),
        .id_csr_funct3 (id_csr_funct3),
        .ex_pc         (ex_pc),
        .ex_reg_we     (ex_reg_we),
        .ex_mem_we     (ex_mem_we),
        .ex_mem_re     (ex_mem_re),
        .ex_alu_src    (ex_alu_src),
        .ex_wb_sel     (ex_wb_sel),
        .ex_branch     (ex_branch),
        .ex_jump       (ex_jump),
        .ex_alu_ctrl   (ex_alu_ctrl),
        .ex_funct3     (ex_funct3),
        .ex_rs1_data   (ex_rs1_data),
        .ex_rs2_data   (ex_rs2_data),
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .ex_rd_addr    (ex_rd_addr),
        .ex_imm        (ex_imm),
        .ex_opcode     (ex_opcode),
        .ex_illegal    (ex_illegal),
        .ex_ecall      (ex_ecall),
        .ex_ebreak     (ex_ebreak),
        .ex_mret       (ex_mret),
        .ex_csr_we     (ex_csr_we),
        .ex_csr_addr   (ex_csr_addr),
        .ex_csr_funct3 (ex_csr_funct3),
        .id_funct7         (id_funct7),
        .ex_funct7         (ex_funct7),
        .id_acc_data       (id_acc_data_fwd),
        .ex_acc_data       (ex_acc_data),
        .id_predict_taken  (id_predict_taken),
        .id_predict_target (id_predict_target),
        .ex_predict_taken  (ex_predict_taken),
        .ex_predict_target (ex_predict_target),
        .id_valid      (id_valid),
        .ex_valid      (ex_valid),
        .stall         (id_ex_stall)
    );


    // EX STAGE
    // =========================================================

    assign ex_pc_plus4 = ex_pc + 32'd4;

    always_comb begin
        case (forward_a)
            2'b00:   ex_fwd_a = ex_rs1_data;
            2'b01:   ex_fwd_a = wb_data;
            2'b10:   ex_fwd_a = mem_alu_result;
            default: ex_fwd_a = ex_rs1_data;
        endcase
    end

    always_comb begin
        case (forward_b)
            2'b00:   ex_fwd_b = ex_rs2_data;
            2'b01:   ex_fwd_b = wb_data;
            2'b10:   ex_fwd_b = mem_alu_result;
            default: ex_fwd_b = ex_rs2_data;
        endcase
    end

    always_comb begin
        case (forward_acc)
            2'b00:   ex_fwd_acc = ex_acc_data;
            2'b01:   ex_fwd_acc = wb_data;
            2'b10:   ex_fwd_acc = mem_alu_result;
            default: ex_fwd_acc = ex_acc_data;
        endcase
    end

    assign ex_alu_a = (ex_opcode == 7'b0010111 ||
                       ex_opcode == 7'b1101111) ? ex_pc : ex_fwd_a;
    assign ex_alu_b = ex_alu_src ? ex_imm : ex_fwd_b;

    alu ALU (
        .a        (ex_alu_a),
        .b        (ex_alu_b),
        .alu_ctrl (ex_alu_ctrl),
        .result   (ex_alu_result),
        .zero     (ex_alu_zero)
    );

    assign is_simd   = (ex_opcode == 7'b0001011);
    assign is_muldiv = (ex_opcode == 7'b0110011) && (ex_funct7 == 7'b0000001);

    mul_div_unit MULDIV (
        .clk    (clk),
        .rst    (rst),
        .a      (ex_fwd_a),
        .b      (ex_fwd_b),
        .funct3 (ex_funct3),
        .start  (is_muldiv),
        .result (muldiv_result),
        .busy   (div_busy)
    );

    simd_alu SIMD (
        .a       (ex_fwd_a),
        .b       (ex_fwd_b),
        .acc     (ex_fwd_acc),   // PMACC accumulator: forwarded rd value
        .funct3  (ex_funct3),
        .funct7  (ex_funct7),
        .result  (simd_result),
        .valid   (simd_valid)
    );

    always_ff @(posedge clk) begin
    if (rst) simd_result_q <= 32'd0;
    else if (simd_stall) simd_result_q <= simd_result;
    end

    // simd_busy is a register, not combinational.  assign simd_busy = is_simd
    // would create an infinite stall: simd_busy=1 → any_stall=1 → id_ex_stall=1
    // → ID/EX holds → is_simd stays 1 forever.  The register self-clears after
    // one cycle, giving exactly one stall per SIMD instruction.
    always_ff @(posedge clk) begin
        if (rst) simd_busy <= 1'b0;
        else if (!(cache_stall || div_busy))
            simd_busy <= is_simd && !simd_busy;
    end

    assign simd_stall = is_simd && !simd_busy;

    logic ex_csr_re;
    assign ex_csr_re = (ex_csr_funct3 != 3'b000);

    assign ex_result = is_simd   ? simd_result_q  :
                       is_muldiv ? muldiv_result   :
                       ex_csr_re ? csr_rd          :
                                   ex_alu_result;

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

    assign ex_pc_branch = ex_pc + ex_imm;
    assign ex_pc_jump   = (ex_opcode == 7'b1100111) ?
                           (ex_fwd_a + ex_imm) & ~32'd1 :
                            ex_pc + ex_imm;

    forward_unit FU (
        .ex_rs1_addr  (ex_rs1_addr),
        .ex_rs2_addr  (ex_rs2_addr),
        .ex_rd_addr   (ex_rd_addr),
        .ex_is_pmacc  (ex_is_pmacc),
        .mem_rd_addr  (mem_rd_addr),
        .mem_reg_we   (mem_reg_we),
        .wb_rd_addr   (wb_rd_addr),
        .wb_reg_we    (wb_reg_we),
        .forward_a    (forward_a),
        .forward_b    (forward_b),
        .forward_acc  (forward_acc)
    );

    ex_mem_reg EX_MEM (
        .clk           (clk),
        .rst           (rst),
        .ex_reg_we     (ex_reg_we),
        .ex_mem_we     (ex_mem_we),
        .ex_mem_re     (ex_mem_re),
        .ex_wb_sel     (ex_wb_sel),
        .ex_funct3     (ex_funct3),
        .ex_alu_result (ex_result),
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
        .mem_pc_plus4  (mem_pc_plus4),
        .stall         (ex_mem_stall)
    );


    // MEM STAGE
    // =========================================================

    // dcache: fills from DSRAM via AXI4-Lite fabric.
    // IO addresses (is_io=1) and accelerator addresses (is_accel=1) bypass the cache.
    dcache DCACHE (
        .clk         (clk),
        .rst         (rst),
        .cpu_we      (mem_mem_we && !is_io && !is_accel && !is_systolic),
        .cpu_re      (mem_mem_re && !is_io && !is_accel && !is_systolic),
        .cpu_addr    (mem_alu_result),
        .cpu_wd      (mem_rs2_data),
        .cpu_funct3  (mem_funct3),
        .cpu_rd      (cache_rd),
        .cache_stall (cache_stall),
        .cache_hit   (cache_hit),
        .cache_miss  (cache_miss),
        .ex_addr_i   (ex_alu_result),
        .ex_stall_i  (ex_mem_stall),
        .mem_we      (dmem_we),
        .mem_re      (dmem_re),
        .mem_addr    (dmem_addr),
        .mem_wd      (dmem_wd),
        .mem_funct3  (dmem_funct3),
        .mem_rd      (dmem_rd),
        .is_io       (is_io)
    );

    // Read data mux: PMU > parallel MAC > systolic > UART > cache
    logic [31:0] mem_read_data_mux;
    assign mem_read_data_mux = is_perf     ? perf_rd      :
                               is_accel    ? accel_rd      :
                               is_systolic ? systolic_m_rd :
                               is_io       ? io_m_rd       :
                                             cache_rd;

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
        .wb_pc_plus4    (wb_pc_plus4),
        .stall          (mem_wb_stall)
    );


    // WB STAGE
    // =========================================================

    assign wb_data = (wb_wb_sel == 2'b01) ? wb_read_data  :
                     (wb_wb_sel == 2'b10) ? wb_pc_plus4   :
                     (wb_wb_sel == 2'b11) ? wb_alu_result :  // was wb_csr_rd, used registered value
                                             wb_alu_result;


    // HAZARD UNIT
    // =========================================================

    hazard_unit HU (
        .clk                (clk),
        .rst                (rst),
        .ex_mem_re          (ex_mem_re),
        .ex_rd_addr         (ex_rd_addr),
        .id_rs1_addr        (id_rs1_addr),
        .id_rs2_addr        (id_rs2_addr),
        .id_rd_addr         (id_rd_addr),
        .id_is_pmacc        (id_is_pmacc),
        .ex_branch          (ex_branch),
        .ex_jump_mispredict (ex_jump_mispredict),
        .branch_taken       (ex_branch_taken),
        .ex_predict_taken   (ex_predict_taken),
        .cache_stall      (cache_stall),
        .div_busy         (div_busy),
        .simd_stall       (simd_stall),
        .icache_stall     (icache_stall),
        .pc_stall         (pc_stall),
        .if_id_stall      (if_id_stall),
        .if_id_flush      (if_id_flush),
        .id_ex_stall      (id_ex_stall),
        .id_ex_flush      (id_ex_flush),
        .ex_mem_stall     (ex_mem_stall),
        .mem_wb_stall     (mem_wb_stall),
        .trap             (trap),
        .ex_mret          (ex_mret),
        .branch_mispredict(mispredict)
    );

    // instruction retired
    assign instr_retired = wb_reg_we;

    // is_io covers all 0xFFFF.... addresses including PMU.
    // is_perf narrows to the PMU sub-range (0xFFFF20xx).
    // The dcache bypasses all is_io addresses.
    // The read mux then selects perf_rd, io_m_rd, or cache_rd in priority order.
    assign is_perf = (mem_alu_result[31:8] == 24'hFFFF20);
    assign is_io   = (mem_alu_result[31:16] == 16'hFFFF);

    perf_counters PERF (
        .clk           (clk),
        .rst           (rst),
        .re            (mem_mem_re && is_perf),
        .addr          (mem_alu_result),
        .rd            (perf_rd),
        .instr_retired (instr_retired),
        .branch_exec   (ex_branch),
        .mispredict    (mispredict),
        .cache_hit     (cache_hit),
        .cache_miss    (cache_miss),
        .icache_hit    (icache_hit),
        .icache_miss   (icache_miss)
    );

    assign ext_irq = uart_irq;

    csr_regfile CSRS (
        .clk          (clk),
        .rst          (rst),
        .csr_we       (ex_csr_we),
        .csr_addr     (ex_csr_addr),
        .csr_wd       (ex_fwd_a),
        .csr_funct3   (ex_csr_funct3[1:0]),
        .csr_rd       (csr_rd),
        .trap         (trap),
        .trap_cause   (trap_cause),
        .trap_epc     (trap_epc),
        .mret         (ex_mret),
        .ext_irq      (ext_irq),
        .mtvec_out    (mtvec_out),
        .mepc_out     (mepc_out),
        .mie_global   (mie_global),
        .meie         (meie)
    );

    exception_unit EU (
        .ex_pc        (ex_pc),
        .ex_valid     (ex_valid),
        .ex_illegal   (ex_illegal),
        .ex_ecall     (ex_ecall),
        .ex_ebreak    (ex_ebreak),
        .ex_mem_re    (ex_mem_re),
        .ex_mem_we    (ex_mem_we),
        .ex_funct3    (ex_funct3),
        .ex_alu_result(ex_alu_result),
        .ext_irq      (ext_irq),
        .mie_global   (mie_global),
        .meie         (meie),
        .trap         (trap),
        .trap_cause   (trap_cause),
        .trap_epc     (trap_epc)
    );

    // SVA: AXI4-Lite awvalid must remain asserted until awready (protocol compliance)
    // |=> expressed as: if awvalid was high and awready was low last cycle,
    // awvalid must still be high this cycle.
    // Shadow registers replace $past() — Icarus Verilog does not implement $past().
    logic prev_dc_m_awvalid, prev_dc_m_awready;
    logic prev_io_m_awvalid, prev_io_m_awready;
    logic prev_sy_m_awvalid, prev_sy_m_awready;
    logic prev_ac_m_awvalid, prev_ac_m_awready;

    always_ff @(posedge clk) begin
        prev_dc_m_awvalid <= dc_m_awvalid;
        prev_dc_m_awready <= dc_m_awready;
        prev_io_m_awvalid <= io_m_awvalid;
        prev_io_m_awready <= io_m_awready;
        prev_sy_m_awvalid <= sy_m_awvalid;
        prev_sy_m_awready <= sy_m_awready;
        prev_ac_m_awvalid <= ac_m_awvalid;
        prev_ac_m_awready <= ac_m_awready;
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            assert (!(prev_dc_m_awvalid && !prev_dc_m_awready) || dc_m_awvalid)
                else $error("SVA FAIL: dc_m_awvalid dropped before dc_m_awready");
            assert (!(prev_io_m_awvalid && !prev_io_m_awready) || io_m_awvalid)
                else $error("SVA FAIL: io_m_awvalid dropped before io_m_awready");
            assert (!(prev_sy_m_awvalid && !prev_sy_m_awready) || sy_m_awvalid)
                else $error("SVA FAIL: sy_m_awvalid dropped before sy_m_awready");
            assert (!(prev_ac_m_awvalid && !prev_ac_m_awready) || ac_m_awvalid)
                else $error("SVA FAIL: ac_m_awvalid dropped before ac_m_awready");
        end
    end

endmodule