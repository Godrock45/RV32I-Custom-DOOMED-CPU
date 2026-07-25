module control(
    input logic [6:0] Opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    output logic RegWrite,
    output logic AluSrc,
    output logic MemRead,
    output logic MemWrite
    output logic MemToReg
    output logic [3:0]AluCtrl,
    output logic Branch,
    output logic Jump
);
always_comb begin
    RegWrite=0;
    AluSrc=0;
    MemRead=0;
    MemWrite=0;
    MemToReg=0;
    Branch=0;
    Jump=0


    case(Opcode)
        7'b0110011:




    endcase

end





endmodule