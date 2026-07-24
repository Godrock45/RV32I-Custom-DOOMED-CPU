module ROME(
    input [31:0]PC,
    output [31:0] IR
);
initial begin
    $readmemh("program.hex",registan);
end
reg [31:0] registan [255:0];
assign IR=registan[PC[31:2]];


endmodule