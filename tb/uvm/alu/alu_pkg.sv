package alu_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ----------------------------------------------------
  // Transaction Item Class
  // ----------------------------------------------------
  class alu_item extends uvm_sequence_item;
    `uvm_object_utils(alu_item)

    // Random stimulus inputs (Driver fields)
    rand logic [31:0] a;
    rand logic [31:0] b;
    rand logic [3:0]  alu_ctrl;

    // Monitored response outputs (Monitor fields)
    logic [31:0] result;
    logic        zero;

    // Workaround for the Verilator/Z3 solver: non-rand knobs to disable baseline distribution
    // profiles. This prevents Z3 from conflicting with inline constraints ('with {}')
    // inside directed test sequences.
    bit ctrl_dist_en = 1'b1;
    bit ab_dist_en   = 1'b1;

    // ----------------------------------------------------
    // Constraints
    // ----------------------------------------------------
    
    // Soft constraint for general data distribution on 'a' and 'b'
    // 'a' hit rate adjusted to ~50% corner values per plan updates.
    constraint c_data_dist {
      ab_dist_en -> soft a dist {
        32'h0000_0000 := 7,
        32'h0000_0001 := 7,
        32'h7FFF_FFFF := 7,
        32'h8000_0000 := 7,
        32'hFFFF_FFFF := 7,
        32'h5555_5555 := 7,
        32'hAAAA_AAAA := 7,
        [32'h0000_0002 : 32'h7FFF_FFFE] :/ 25,
        [32'h8000_0001 : 32'hFFFF_FFFE] :/ 25
      };

      // Architectural Decision: This baseline distribution applies to 'b' 
      // ONLY when the operation is not a shift. This mutual exclusion prevents 
      // the Z3 solver (as used by Verilator) from generating overlapping bit-slice
      // conflicts that result in randomization failures.
      (ab_dist_en && !(alu_ctrl inside {4'h5, 4'h6, 4'h7})) -> soft b dist {
        32'h0000_0000 := 7,
        32'h0000_0001 := 7,
        32'h7FFF_FFFF := 7,
        32'h8000_0000 := 7,
        32'hFFFF_FFFF := 7,
        32'h5555_5555 := 7,
        32'hAAAA_AAAA := 7,
        [32'h0000_0002 : 32'h7FFF_FFFE] :/ 25,
        [32'h8000_0001 : 32'hFFFF_FFFE] :/ 25
      };
    }

    // Soft constraint for operation code distribution
    // Legal codes: 0x0 to 0xA (95%). Illegal codes: 0xB to 0xF (5%).
    // Architectural Decision: Uses ':/' instead of ':=' to evenly distribute 
    // the target probability aggregate across the entire subset array.
    constraint c_ctrl_dist {
      ctrl_dist_en -> soft alu_ctrl dist {
        [4'h0 : 4'hA] :/ 95,
        [4'hB : 4'hF] :/ 5
      };
    }

    // Soft conditional shift constraint
    // 4'h5 = SLL, 4'h6 = SRL, 4'h7 = SRA
    constraint c_shift_behavior {
      (ab_dist_en && alu_ctrl inside {4'h5, 4'h6, 4'h7}) -> {
        soft b[4:0] dist {
          5'd0  := 30,
          5'd1  := 30,
          5'd31 := 30,
          [5'd2 : 5'd30] :/ 10
        };

        soft b[31:5] dist {
          27'd0 := 70,
          [27'd1 : {27{1'b1}}] :/ 30
        };
      }
    }

    // ----------------------------------------------------
    // Methods
    // ----------------------------------------------------
    function new(string name = "alu_item");
      super.new(name);
    endfunction

    virtual function string convert2string();
      return $sformatf("alu_ctrl=%h a=%h b=%h | result=%h zero=%b", 
                       alu_ctrl, a, b, result, zero);
    endfunction
  endclass


  // ----------------------------------------------------
  // Driver Class
  // ----------------------------------------------------
  class alu_driver extends uvm_driver #(alu_item);
    `uvm_component_utils(alu_driver)

    virtual alu_if vif;

    function new(string name = "alu_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual alu_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("DRV", "Could not obtain virtual interface handle 'vif' from config_db")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      // Initialize inputs using the driver clocking block
      vif.drv_cb.valid    <= 1'b0;
      vif.drv_cb.a        <= 32'b0;
      vif.drv_cb.b        <= 32'b0;
      vif.drv_cb.alu_ctrl <= 4'b0;

      forever begin
        seq_item_port.get_next_item(req);
        drive_item(req);
        seq_item_port.item_done();
      end
    endtask

    virtual task drive_item(alu_item item);
      @(vif.drv_cb);
      vif.drv_cb.valid    <= 1'b1;
      vif.drv_cb.a        <= item.a;
      vif.drv_cb.b        <= item.b;
      vif.drv_cb.alu_ctrl <= item.alu_ctrl;
      
      // Fix for Bug 2 Part 2: Explicitly clear valid on the trailing clock edge 
      // so idle cycles don't inherit a lingering 'valid == 1' signal state.
      @(vif.drv_cb);
      vif.drv_cb.valid    <= 1'b0;
    endtask
  endclass


  // ----------------------------------------------------
  // Monitor Class
  // ----------------------------------------------------
  class alu_monitor extends uvm_monitor;
    `uvm_component_utils(alu_monitor)

    virtual alu_if vif;
    uvm_analysis_port #(alu_item) ap;

    function new(string name = "alu_monitor", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db#(virtual alu_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("MON", "Could not obtain virtual interface handle 'vif' from config_db")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      forever begin
        alu_item item;
        
        @(vif.mon_cb);
        
        // Fix for Bug 1 & Bug 2 Part 1: Monitor only extracts data and publishes 
        // a transaction when 'valid' is high. Idle clock cycles are ignored.
        if (vif.mon_cb.valid === 1'b1) begin
          item = alu_item::type_id::create("item");
          item.a        = vif.mon_cb.a;
          item.b        = vif.mon_cb.b;
          item.alu_ctrl = vif.mon_cb.alu_ctrl;
          item.result   = vif.mon_cb.result;
          item.zero     = vif.mon_cb.zero;

          ap.write(item);
        end
      end
    endtask
  endclass


  // ----------------------------------------------------
  // Agent Class
  // ----------------------------------------------------
  class alu_agent extends uvm_agent;
    `uvm_component_utils(alu_agent)

    uvm_sequencer #(alu_item) sequencer;
    alu_driver                driver;
    alu_monitor               monitor;

    function new(string name = "alu_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      
      monitor = alu_monitor::type_id::create("monitor", this);
      
      if (get_is_active() == UVM_ACTIVE) begin
        sequencer = uvm_sequencer#(alu_item)::type_id::create("sequencer", this);
        driver    = alu_driver::type_id::create("driver", this);
      end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (get_is_active() == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
      end
    endfunction
  endclass

  // ----------------------------------------------------
  // Scoreboard Class
  // ----------------------------------------------------
  // Architectural Decision: Extending uvm_subscriber #(alu_item) provides an embedded, 
  // typed uvm_analysis_export out-of-the-box. This allows the monitor's analysis port 
  // (ap) to connect directly to the scoreboard without requiring a separate macro 
  // declaration or custom TLM implementation.

  class alu_scoreboard extends uvm_subscriber #(alu_item);
    `uvm_component_utils(alu_scoreboard)

    // Counters for verification metrics
    int num_checked = 0;
    int num_failed  = 0;

    function new(string name = "alu_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Purely behavioral reference model for ALU operations based on RV32I spec.
    // Deliberately avoiding rtl syntax ($signed, $unsigned, >>> etc.) so that scoreboard stays independent 
    // from rtl ALU as a copied model would share similar syntax bugs
    virtual function void write(alu_item t);
      logic [31:0] exp_result;
      logic        exp_zero;
      logic [4:0]  shamt;

      shamt = t.b[4:0]; // shift amount is lower 5 bits of b

      case (t.alu_ctrl)
        4'h0: exp_result = t.a + t.b;    // ADD
        4'h1: exp_result = t.a - t.b;    // SUB
        4'h2: exp_result = t.a & t.b;    // AND
        4'h3: exp_result = t.a | t.b;    // OR
        4'h4: exp_result = t.a ^ t.b;    // XOR
        4'h5: exp_result = t.a << shamt; // SLL
        4'h6: exp_result = t.a >> shamt; // SRL
        4'h7: begin                      // SRA
          if (t.a[31] == 1'b1 && shamt != 0) begin
            // Create a mask with the upper 'shamt' bits set to 1, then OR with the logical right shift
            exp_result = (32'hFFFF_FFFF << (32 - shamt)) | (t.a >> shamt);
          end else begin
            exp_result = t.a >> shamt;
          end
        end
        // SLT manual signed comparison without $signed()
        4'h8: begin
          if (t.a[31] != t.b[31]) begin
            // Signs are different: the one with the set sign bit (negative) is smaller
            exp_result = (t.a[31] == 1'b1) ? 32'd1 : 32'd0;
          end else begin
            // Signs are the same: a simple unsigned subtraction reveals relative magnitude
            exp_result = (t.a < t.b) ? 32'd1 : 32'd0;
          end
        end
        4'h9: exp_result = (t.a < t.b) ? 32'd1 : 32'd0; // SLTU
        4'hA: exp_result = t.b;                          // LUI
        default: exp_result = 32'd0;                     // Invalid operation code
      endcase

      exp_zero = (exp_result == 32'h0);
      num_checked++;

      // Perform cross comparison of both calculated outputs and log any mismatches
      if ((t.result !== exp_result) || (t.zero !== exp_zero)) begin
        num_failed++;
        `uvm_error("ALU_SCB_MISMATCH", $sformatf(
          "MISMATCH detected!\n  Observed: %s\n  Expected: result=%h zero=%b | alu_ctrl=%h",
          t.convert2string(), exp_result, exp_zero, t.alu_ctrl
        ))
      end
    endfunction

    // Phase checks to guarantee that the testbench actually evaluated traffic
    virtual function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (num_checked == 0) begin
        `uvm_error("ALU_SCB_NO_TRAFFIC", "Zero transactions were processed by the scoreboard! Check monitor/driver connectivity.")
      end
    endfunction

    // Print summary report targeting regression logs
    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("ALU_SCB_REPORT", $sformatf(
        "\n----------------------------------------\nALU Scoreboard Report:\n  Transactions Checked: %0d\n  Transactions Failed:  %0d\n----------------------------------------",
        num_checked, num_failed
      ), UVM_LOW)
    endfunction
  endclass

  // ----------------------------------------------------
  // Random Sequence Class
  // ----------------------------------------------------
  class alu_rand_seq extends uvm_sequence #(alu_item);
    `uvm_object_utils(alu_rand_seq)

    int unsigned n = 20;

    function new(string name = "alu_rand_seq");
      super.new(name);
    endfunction

    virtual task body();
      alu_item item;
      repeat (n) begin
        item = alu_item::type_id::create("item");
        start_item(item);
        if (!item.randomize()) begin
          `uvm_fatal("SEQ", "Randomization failed!")
        end
        finish_item(item);
      end
    endtask
  endclass

  // ----------------------------------------------------
  // Coverage Collector Class
  // ----------------------------------------------------
  // Architectural Decision: Extending uvm_subscriber #(alu_item) allows this component
  // to tap into the monitor's analysis stream in parallel with the scoreboard, capturing
  // operational statistics without altering transaction flows.
  class alu_coverage extends uvm_subscriber #(alu_item);
    `uvm_component_utils(alu_coverage)

    // Storage handle for the currently evaluated transaction transaction
    alu_item item;

    // ----------------------------------------------------
    // Covergroup Definition (plan section 6)
    // ----------------------------------------------------
    // This simulator (Verilator) ignores 'ignore_bins ... binsof()' inside a cross (COVERIGN), so the
    // excluded bins would still count as holes. Instead, each op group gets its own
    // opcode coverpoint restricted with 'iff', and a cross only samples when every
    // coverpoint in it is enabled. No cross contains a bin that can't be hit.
    covergroup alu_cg;
      option.per_instance = 1;

      // Every opcode, legal and illegal
      cp_alu_ctrl: coverpoint item.alu_ctrl {
        bins legal_ops[]   = {[4'h0 : 4'hA]};
        bins illegal_ops[] = {[4'hB : 4'hF]};
      }

      // --------------------------------------------------
      // Opcode groups, each enabled only for its own ops
      // --------------------------------------------------
      // ADD, SUB, AND, OR, XOR, SLT, SLTU: both operands matter
      cp_op_rr: coverpoint item.alu_ctrl iff (item.alu_ctrl inside {[4'h0 : 4'h4], 4'h8, 4'h9}) {
        bins op[] = {[4'h0 : 4'h4], 4'h8, 4'h9};
      }

      // SLL, SRL, SRA
      cp_op_sh: coverpoint item.alu_ctrl iff (item.alu_ctrl inside {4'h5, 4'h6, 4'h7}) {
        bins op[] = {4'h5, 4'h6, 4'h7};
      }

      // All legal ops, for the zero-flag cross
      cp_op_legal: coverpoint item.alu_ctrl iff (item.alu_ctrl <= 4'hA) {
        bins op[] = {[4'h0 : 4'hA]};
      }

      // --------------------------------------------------
      // Operand A Interest Groups
      // --------------------------------------------------
      cp_a_corners: coverpoint item.a {
        bins zero       = {32'h0000_0000};
        bins one        = {32'h0000_0001};
        bins max_pos    = {32'h7FFF_FFFF};
        bins min_neg    = {32'h8000_0000};
        bins minus_one  = {32'hFFFF_FFFF};
        bins alt_01     = {32'h5555_5555};
        bins alt_10     = {32'hAAAA_AAAA};
        bins default_val = default;
      }

      // --------------------------------------------------
      // Operand B General Interest Groups
      // --------------------------------------------------
      // Active strictly during NON-SHIFT operations
      cp_b_general: coverpoint item.b iff (!(item.alu_ctrl inside {4'h5, 4'h6, 4'h7})) {
        bins zero       = {32'h0000_0000};
        bins one        = {32'h0000_0001};
        bins max_pos    = {32'h7FFF_FFFF};
        bins min_neg    = {32'h8000_0000};
        bins minus_one  = {32'hFFFF_FFFF};
        bins alt_01     = {32'h5555_5555};
        bins alt_10     = {32'hAAAA_AAAA};
        bins default_val = default;
      }

      // LUI: only b matters (corner C6), so it gets its own coverpoint instead of a cross
      cp_b_lui: coverpoint item.b iff (item.alu_ctrl == 4'hA) {
        bins zero       = {32'h0000_0000};
        bins one        = {32'h0000_0001};
        bins max_pos    = {32'h7FFF_FFFF};
        bins min_neg    = {32'h8000_0000};
        bins minus_one  = {32'hFFFF_FFFF};
        bins alt_01     = {32'h5555_5555};
        bins alt_10     = {32'hAAAA_AAAA};
      }

      // --------------------------------------------------
      // Operand B Shift-specific Groups
      // --------------------------------------------------
      // Shift Amount Low Slices (b[4:0]) - Active strictly during SHIFT operations
      cp_b_shamt: coverpoint item.b[4:0] iff (item.alu_ctrl inside {4'h5, 4'h6, 4'h7}) {
        bins min_shift  = {5'd0};
        bins one_shift  = {5'd1};
        bins max_shift  = {5'd31};
        bins mid_shifts = {[5'd2 : 5'd30]};
      }

      // Upper bits b[31:5] - must be ignored by the shift (corner C1)
      cp_b_upper: coverpoint item.b[31:5] iff (item.alu_ctrl inside {4'h5, 4'h6, 4'h7}) {
        bins clean_zero   = {27'd0};
        bins dirty_values = {[27'd1 : {27{1'b1}}]};
      }

      // --------------------------------------------------
      // Output coverage
      // --------------------------------------------------
      cp_zero: coverpoint item.zero {
        bins clear = {1'b0};
        bins set   = {1'b1};
      }

      // Illegal opcodes must always return 0, so zero must be set (corner C9)
      cp_zero_illegal: coverpoint item.zero iff (item.alu_ctrl > 4'hA) {
        bins set = {1'b1};
      }

      // --------------------------------------------------
      // Cross Coverage Specifications
      // --------------------------------------------------
      // Register ops x a class x b class: 7 x 7 x 7 = 343 bins (C4, C5, C8)
      x_rr: cross cp_op_rr, cp_a_corners, cp_b_general;

      // Shift ops x a class x shift amount x upper bits: 3 x 7 x 4 x 2 = 168 bins (C1-C3)
      x_sh: cross cp_op_sh, cp_a_corners, cp_b_shamt, cp_b_upper;

      // Every legal op must produce both zero = 0 and zero = 1: 11 x 2 = 22 bins (C7)
      x_zero: cross cp_op_legal, cp_zero;
    endgroup

    // ----------------------------------------------------
    // Component Methods
    // ----------------------------------------------------
    function new(string name = "alu_coverage", uvm_component parent = null);
      super.new(name, parent);
      alu_cg = new();
    endfunction

    virtual function void write(alu_item t);
      this.item = t;
      alu_cg.sample();
    endfunction

    // Print calculated instance metric percentage directly to logging output
    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("ALU_COV_REPORT", $sformatf(
        "\n----------------------------------------\nALU Functional Coverage:\n  Instance Coverage: %3.2f%%\n----------------------------------------",
        alu_cg.get_inst_coverage()
      ), UVM_LOW)
    endfunction
  endclass

  // ----------------------------------------------------
  // Environment Class
  // ----------------------------------------------------
  class alu_env extends uvm_env;
    `uvm_component_utils(alu_env)

    alu_agent      agent;
    alu_scoreboard sb;
    alu_coverage   cov; // added instance pointer

    function new(string name = "alu_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = alu_agent::type_id::create("agent", this);
      sb    = alu_scoreboard::type_id::create("sb", this);
      cov   = alu_coverage::type_id::create("cov", this); // Instance built here
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(sb.analysis_export);
      agent.monitor.ap.connect(cov.analysis_export); // Parallel destination binded
    endfunction
  endclass

  // ----------------------------------------------------
  // Smoke Test Class
  // ----------------------------------------------------
  class alu_smoke_test extends uvm_test;
    `uvm_component_utils(alu_smoke_test)

    alu_env env;
    int unsigned num_txns = 20;  // transactions per run; derived tests change this

    function new(string name = "alu_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = alu_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      alu_rand_seq seq;

      // Drain time (2 clock periods, no timescale) lets the monitor sample the last item
      phase.get_objection().set_drain_time(this, 20);
      phase.raise_objection(this);

      seq = alu_rand_seq::type_id::create("seq");
      seq.n = num_txns;
      seq.start(env.agent.sequencer);
      
      phase.drop_objection(this);
    endtask
  endclass

  // ----------------------------------------------------
  // Random Regression Test
  // ----------------------------------------------------
  // Same env and sequence as the smoke test, 10,000 transactions instead of 20.
  // Inherits everything from alu_smoke_test and only changes the count.
  class alu_rand_test extends alu_smoke_test;
    `uvm_component_utils(alu_rand_test)

    function new(string name = "alu_rand_test", uvm_component parent = null);
      super.new(name, parent);
      num_txns = 10000;
    endfunction
  endclass

endpackage
