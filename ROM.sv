module ROME(
    input [31:0]PC,
    output [31:0] IR
);
reg [31:0] registan [16383:0];
initial begin
    registan[0]=32'h00500093;
    registan[1]=32'h00300113;
    registan[2]=32'h002081B3;
    registan[3]=32'h00302023;
    registan[4]=32'h00002203;
    registan[5]=32'h00418463;
    registan[6]=32'h06300293;
    registan[7]=32'h00000063;

end
assign IR=registan[PC[15:2]];


endmodule