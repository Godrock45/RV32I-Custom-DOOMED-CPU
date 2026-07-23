module ALU(
    input logic [31:0] OpA,
    input logic [31:0] OpB,
    input logic [3:0] ALUCtrl,
    output logic [31:0] Res,
);

always_comb begin
    case(ALUCtrl)
    1000: Res=OpA+OpB;                          //ADD
    1001: Res=OpA-OpB;                          //SUB
    0001: Res=OpA << (OpB[4:0]);                //SLL
    0010: Res={31'b0,$signed(OpA)<$signed(OpB)};//SLT
    0011: Res=OpA<OpB;                          //SLTU
    0100: Res= OpA^OpB;                         //XOR
    0101: Res= OpA >> OpB[4:0];                 //SRL
    1101: Res= {OpA[31],OpA[30:0]>>OpB[4:0]};   //SRA
    0110: Res= OpA|OpB;                         //OR
    0111: Res= OpA&OpB;                         //AND
    default:
    Res=32'b0;
    endcase
    
end





endmodule