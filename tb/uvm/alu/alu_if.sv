interface alu_if(input logic clk);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ----------------------------------------------------
  // Signals
  // ----------------------------------------------------
  logic        valid;
  logic [31:0] a;
  logic [31:0] b;
  logic [3:0]  alu_ctrl;
  logic [31:0] result;
  logic        zero;

  // ----------------------------------------------------
  // Driver Clocking Block
  // ----------------------------------------------------
  // Architectural Decision: This block omits 'result' and 'zero' because the 
  // driver's sole responsibility is to apply stimulus to the design inputs. 
  // It must not drive or interact with the DUT's output response lines.
  clocking drv_cb @(posedge clk);
    output valid;
    output a;
    output b;
    output alu_ctrl;
  endclocking

  // ----------------------------------------------------
  // Monitor Clocking Block
  // ----------------------------------------------------
  clocking mon_cb @(posedge clk);
    input valid;
    input a;
    input b;
    input alu_ctrl;
    input result;
    input zero;
  endclocking

  // ----------------------------------------------------
  // Assertions (SVA)
  // ----------------------------------------------------
  // Plan §5: Whenever valid is high, zero must equal (result == 0).
  //
  // Architectural Decision on Sampling Phase: SystemVerilog concurrent assertions 
  // evaluate expressions using values sampled in the Preponed region (effectively `#1step`). 
  // Consequently, at a given posedge clk, this assertion evaluates the transaction 
  // driven *one edge earlier*. It does not check the value driven at the exact same edge, 
  // as the newly driven values have not yet propagated to the Preponed sampling window.
  a_zero: assert property (@(posedge clk) valid |-> zero == (result == 32'b0))
    else begin
      `uvm_error("ALU_IF_SVA", $sformatf(
        "Zero flag mismatch! valid=%b, zero=%b, result=%h", 
        $sampled(valid), $sampled(zero), $sampled(result)
      ))
    end

endinterface
