module decoder(
    input [31:0] instruction,
    output reg [4:0] rd,
    output reg [4:0] rs1,
    output reg [4:0] rs2,
    output reg [6:0] funct7,
    output reg [2:0] funct3,
    output reg [31:0] imm,
    output reg [6:0] opcode
);
always_comb begin
    rd=5'd0;
    rs1=5'd0;
    rs2=5'd0;
    funct7=7'd0;
    funct3=3'd0;
    imm=32'd0; 
    opcode= instruction[6:0];   
    case(opcode)
        7'b0110011: begin  //R type Instructions
            funct7 = instruction[31:25];
            rs2 = instruction[24:20];
            rs1 = instruction[19:15];
            rd = instruction[11:7];
            funct3= instruction[14:12];
        end
        7'b0010011:begin    //I type Instructions
            funct3= instruction[14:12];
            rd=instruction[11:7];
            rs1=instruction[19:15];
            rs2=instruction[24:20];
            imm={{20{instruction[31]}},instruction[31:20]};
        end
        7'b1100011:begin    //B type Instructions
            funct3= instruction[14:12];
            rd=instruction[11:7];
            rs1=instruction[19:15];
            rs2=instruction[24:20];
            imm={{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
        end
        7'b0100011:begin    //S type Instructions
            funct3=instruction[14:12];
            rs2=instruction[24:20];
            rs1=instruction[19:15];
            imm={{20{instruction[31]}},instruction[31:25],instruction[11:7]};
        end
        7'b1101111:begin    //J type Instructions
            rd=instruction[11:7];
            imm={{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
        end
        7'b0110111:begin   //U type Instructions
            imm={instruction[31:12],12'b0};
            rd=instruction[11:7];
        end
        7'b0010111:begin  // U type for AUIPC instruction
            imm={instruction[31:12],12'b0};
            rd=instruction[11:7];
        end
        7'b01100111:begin  // I type for JALR instruction
            funct3= instruction[14:12];
            rd=instruction[11:7];
            rs1=instruction[19:15];
            imm={{20{instruction[31]}},instruction[31:20]};
        end
        default: begin
            rd=5'd0;
            rs1=5'd0;
            rs2=5'd0;
            funct7=7'd0;
            funct3=3'd0;
            imm=32'd0;
        end



    endcase
end

endmodule
