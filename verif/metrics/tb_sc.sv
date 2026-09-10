// Independent instruction counter using the v1.0 single-cycle core.
// Single-cycle means CPI = 1 exactly, so cycles in the window == instructions.
// Same window definition as tb_perf: from PC == START up to (not including) PC == HALT.
`timescale 1ns/1ps
module tb_sc;
    logic clk = 0, rst = 1;
    logic [31:0] dbg_pc, dbg_instr, dbg_wb_data; logic [4:0] dbg_rd; logic dbg_reg_we, halt;
    top_wire dut(.clk(clk),.rst(rst),.dbg_pc(dbg_pc),.dbg_instr(dbg_instr),.dbg_rd(dbg_rd),
                 .dbg_reg_we(dbg_reg_we),.dbg_wb_data(dbg_wb_data),.halt(halt));
    always #5 clk = ~clk;

    integer START, HALTPC, n, k, dsum;
    reg active, seen;
    initial begin
        if (!$value$plusargs("START=%d", START))  START  = 0;
        if (!$value$plusargs("HALT=%d",  HALTPC)) HALTPC = 0;
        active = 0; seen = 0; n = 0;
        #20 rst = 0;
        #5000000 $display("TIMEOUT"); $finish;
    end

    always @(posedge clk) if (!rst) begin
        if (!active && !seen && dut.PC_loc == START) active = 1;
        if (active && dut.PC_loc == HALTPC) begin
            dsum = 0;
            for (k = 64; k < 128; k = k + 1) dsum = dsum + dut.meme.memistan[k];
            $display("SC n=%0d s0=%0d dsum=%0d", n, dut.npn.registers[8], dsum);
            $finish;
        end
        if (active) n = n + 1;
    end
endmodule
