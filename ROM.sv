module ROME(
    input [31:0]PC,
    output [31:0] IR
);
reg [31:0] registan [255:0];
initial begin
    $readmemh("program.hex",registan);
end
assign IR=registan[PC[9:2]];


endmodule