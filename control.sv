module control(
    input logic [6:0] Opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    output logic RegWrite,
    output logic AluSrc,
    output logic MemRead,
    output logic MemWrite,
    output logic MemToReg,
    output logic [3:0]AluCtrl,
    output logic Branch,
    output logic Jump
);
always_comb begin
    RegWrite=0;
    AluCtrl=4'b1111;
    AluSrc=0;
    MemRead=0;
    MemWrite=0;
    MemToReg=0;
    Branch=0;
    Jump=0;
    case(Opcode)
        7'b0110011:begin
            AluCtrl={funct7[5],funct3};
            RegWrite=1;
            AluSrc=0;
        end
        7'b0010011:begin
            AluCtrl={funct7[5],funct3};
            RegWrite=1;
            AluSrc=1;
        end
        7'b0000011:begin
            AluCtrl=4'b0000;
            AluSrc=1;
            RegWrite=1;
            MemToReg=1;
            MemRead=1;
        end
        7'b1100111:begin            // JALR if JUMP&&RegWrite do rd=PC+4 and load PC with ALU_Res&~1;
            AluCtrl=4'b0000;
            AluSrc=1;
            RegWrite=1;
            Jump=1;
            Branch=1;
        end
        7'b1110011:begin
            
        end
        7'b0001111:begin
            
        end




    endcase

end



//Wrong: taken = Branch & comparator_result → this fires the comparator on JALR (11) too, and you're back to the garbage-rs2 bug.
//Right: taken = (Branch & ~Jump) & comparator_result, or better, a clean case({Branch,Jump})

endmodule