module ROME(
    input [31:0]PC;
    output [31:0] IR;
);
 reg [255:0] registan [31:0];
always_comb begin
    IR<=registan[PC];
end


endmodule