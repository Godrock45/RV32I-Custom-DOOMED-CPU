module ROME(
    input [31:0]PC,
    output [31:0] IR
);
 reg [31:0] registan [255:0];
assign IR=registan[PC[7:0]];


endmodule