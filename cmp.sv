module comparator(
    input logic [31:0]OpA,
    input logic [31:0]OpB,
    input logic [2:0]funct3,
    output logic cmp
);
    always_comb begin
        case(funct3)
            3'b000:
            cmp=(OpA==OpB);
            3'b001:
            cmp=(OpA!=OpB);
            3'b100:
            cmp=($signed(OpA)<$signed(OpB));
            3'b101:
            cmp=($signed(OpA)>=$signed(OpB));
            3'b110:
            cmp=(OpA<OpB);
            3'b111:
            cmp=(OpA>=OpB);
            default:
            cmp=0;
        endcase

    end


endmodule