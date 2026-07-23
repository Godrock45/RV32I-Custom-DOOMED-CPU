module ALU(
    input logic [31:0] OpA,
    input logic [31:0] OpB,
    input logic [3:0] ALUCtrl,
    output logic [31:0] Res,
);

always_comb begin
    case(ALUCtrl)
    1000: Res=OpA+OpB;
    1001: Res=OpA-OpB;
    0001: Res=OpA << (OpB[5:0]);
    0010: Res=$signed(OpA)<$signed(OpB);
    0011: Res=OpA<OpB;
    0100: Res= OpA^OpB;
    0101: Res= OpA >> OpB[5:0];
    1101: Res= {OpA[31],OpA[30:0]>>OpB[4:0]};
    0110: Res= OpA|OpB;
    0111: Res= OpA&OpB;
    default:
    Res=0;
    endcase
    
end





endmodule