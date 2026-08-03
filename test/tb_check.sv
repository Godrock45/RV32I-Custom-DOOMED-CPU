`timescale 1ns/1ps
module tb_check;
    logic clk, rst;
    logic [31:0] dbg_pc, dbg_instr, dbg_wb_data;
    logic [4:0]  dbg_rd;
    logic        dbg_reg_we, halt;
    integer i;

    top_wire dut(.clk(clk),.rst(rst),.dbg_pc(dbg_pc),.dbg_instr(dbg_instr),
                 .dbg_rd(dbg_rd),.dbg_reg_we(dbg_reg_we),
                 .dbg_wb_data(dbg_wb_data),.halt(halt));

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; #20; rst = 0;
        #6000;
        $display("=== FINAL PC = %08h ===", dbg_pc);
        for (i = 0; i < 32; i = i + 1)
            $display("REG %0d %08x", i, dut.npn.registers[i]);
        for (i = 0; i < 32; i = i + 1)
            $display("MEM %0d %08x", i, dut.meme.memistan[i]);
        $finish;
    end
endmodule
