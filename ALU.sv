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
    0001: Res=


    endcase
    
end





endmodule