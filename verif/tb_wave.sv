// Waveform-oriented testbench: same program as tb_check, but dumps a VCD
// and prints a one-line commit log. Open wave.vcd in GTKWave.
`timescale 1ns/1ps
module tb_wave;
    logic clk, rst;
    logic [31:0] dbg_pc, dbg_instr, dbg_wb_data;
    logic [4:0]  dbg_rd;
    logic        dbg_reg_we, halt;

    top_wire dut(.clk(clk),.rst(rst),.dbg_pc(dbg_pc),.dbg_instr(dbg_instr),
                 .dbg_rd(dbg_rd),.dbg_reg_we(dbg_reg_we),
                 .dbg_wb_data(dbg_wb_data),.halt(halt));

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; #20; rst = 0;
        #400 $finish;               // demo program retires at ~325 ns
    end

    // retired-instruction log
    always @(posedge clk) if (!rst && dbg_reg_we && dbg_rd != 0)
        $display("%6t  pc=%08h  instr=%08h  x%-2d <= %08h",
                 $time, dbg_pc, dbg_instr, dbg_rd, dbg_wb_data);

    initial begin
        $dumpfile("wave.vcd");
        // level 1 + dut scope only: avoids declaring the same net twice
        // (once in tb_wave, once in dut) under one VCD id, which breaks
        // scalar rendering in some viewers.
        $dumpvars(1, tb_wave.dut);
    end
endmodule
