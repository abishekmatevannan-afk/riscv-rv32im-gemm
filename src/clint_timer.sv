// Machine timer (the timer half of a RISC-V CLINT), memory-mapped at 0xFFFF4000
//
//   0xFFFF4000  mtime     [31:0]   R/W  counts up by 1 every clock cycle
//   0xFFFF4004  mtime     [63:32]  R/W
//   0xFFFF4008  mtimecmp  [31:0]   R/W
//   0xFFFF400C  mtimecmp  [63:32]  R/W
//
// timer_irq (mip.MTIP) is high while mtime >= mtimecmp. It is registered: the
// 64-bit compare is a long carry chain, and feeding it straight into the trap
// logic would put it on the trap -> flush path that timing closure had to fix.
// The interrupt therefore rises (and clears) one cycle after the compare
// changes, which the privileged spec allows.
//
// mtimecmp resets to all ones, so no interrupt fires until software arms it.
// To move mtimecmp without a spurious interrupt between the two 32-bit
// stores, write the low word to all ones first, then the high word, then the
// low word.
//
// Reads and writes come from the MEM stage like the PMU. Writes arrive through
// the one-shot mem_mmio_we, so a store held in MEM by a stall writes once.

module clint_timer (
    input  logic        clk,
    input  logic        rst,

    input  logic        we,          // store to this block, one cycle per instruction
    input  logic [31:0] addr,        // byte address (only [3:2] decoded)
    input  logic [31:0] wd,
    output logic [31:0] rd,

    output logic        timer_irq    // mip.MTIP
);

    logic [63:0] mtime;
    logic [63:0] mtimecmp;

    always_ff @(posedge clk) begin
        if (rst) begin
            mtime     <= 64'd0;
            mtimecmp  <= 64'hFFFF_FFFF_FFFF_FFFF;
            timer_irq <= 1'b0;
        end else begin
            // A write to an mtime half replaces it; the other half keeps counting.
            mtime <= mtime + 64'd1;
            if (we) begin
                case (addr[3:2])
                    2'd0: mtime[31:0]     <= wd;
                    2'd1: mtime[63:32]    <= wd;
                    2'd2: mtimecmp[31:0]  <= wd;
                    2'd3: mtimecmp[63:32] <= wd;
                endcase
            end
            timer_irq <= (mtime >= mtimecmp);
        end
    end

    always_comb begin
        case (addr[3:2])
            2'd0: rd = mtime[31:0];
            2'd1: rd = mtime[63:32];
            2'd2: rd = mtimecmp[31:0];
            2'd3: rd = mtimecmp[63:32];
        endcase
    end

endmodule
