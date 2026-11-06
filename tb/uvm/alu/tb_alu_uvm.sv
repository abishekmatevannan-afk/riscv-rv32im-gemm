import uvm_pkg::*;
`include "uvm_macros.svh"
import alu_pkg::*;

    module tb_alu_uvm;
    logic clk;

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
     end

     // interface Instance
     alu_if inf(clk);

     // DUT Instance
     // Architectural Decision: Connects strictly to the five combinational ports 
     // present in alu.sv. 'clk' and 'valid' exist purely within the UVM 
     // infrastructure to synchronize driver/monitor transaction boundaries.
        alu dut (
            .a(inf.a),
            .b(inf.b),
            .alu_ctrl(inf.alu_ctrl),
            .result(inf.result),
            .zero(inf.zero)
        );

    initial begin
        // Restrict interface scope strictly to components under the test top hierarchy
        uvm_config_db#(virtual alu_if)::set(null, "uvm_test_top.*", "vif", inf);

        // Run the UVM test
        run_test();
        end
    endmodule