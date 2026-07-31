`timescale 1ns/1ps
module test1(

);
logic clk,rst;
logic [31:0] dbg_pc,dbg_instr,dbg_wb_data;
logic [4:0] dbg_rd;
logic dbg_reg_we, halt;
top_wire dut(.clk(clk),.rst(rst),.dbg_pc(dbg_pc),.dbg_instr(dbg_instr),.dbg_rd(dbg_rd),.dbg_reg_we(dbg_reg_we),.dbg_wb_data(dbg_wb_data),.halt(halt));

initial clk=0;
always #5 clk=~clk;

initial begin

    rst=1;
    #20;
    rst=0;
  #2000 $finish;
end

always @(posedge clk) if (!rst && dbg_reg_we && dbg_rd != 0)
    $display("%0t pc=%08h instr=%08h x%0d <= %08h",
             $time, dbg_pc, dbg_instr, dbg_rd, dbg_wb_data);
             
initial $dumpfile("wave.vcd");
initial $dumpvars(0,test1);




endmodule