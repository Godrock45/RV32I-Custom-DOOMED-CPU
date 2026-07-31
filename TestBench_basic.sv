module test1(

);
reg clk;

initial clk=0;
always #5 clk=~clk;

initial begin

    rst=1;
    #20;
    rst=0;
  #2000 $finish;
end
initial $dumpfile("wave.vcd");
initial $dumpvars(0,tb);




endmodule