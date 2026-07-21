module decoder(
    input [31:0] instruction
    output reg [4:0] rd,
    output reg [4:0] rs1,
    output reg [4:0] rs2,
    output reg [6:0] funct7,

);
reg [6:0] opcode;
assign opcode= instruction[6:0];

always_comb begin
    case(opcode)
        7'b0000001: begin
            rd = instruction[11:7];
            rs1 = instruction[19:15];
            rs2 = instruction[24:20];
            funct7 = instruction[31:25];
        end


    endcase
end




endmodule