module memory(
    input clk,
    input [31:0]addr,
    input [31:0]dat,
    input logic [2:0]funct3,
    input write_ena,
    output logic [31:0]mem_dat
);
reg [31:0] memistan [255:0];
always_comb begin
    mem_dat=memistan[addr[9:2]];
end

always_ff @(posedge clk) begin
    if(write_ena) begin
        case(funct3)
        3'b000:begin
            memistan[addr[9:2]][8*addr[1:0]+:8]<=dat[7:0];
        end
        3'b001:begin
            memistan[addr[9:2]][16*addr[1]+:16]<=dat[15:0];
        end
        3'b010:begin
            memistan[addr[9:2]]<=dat;
        end
        endcase
    end
end

endmodule