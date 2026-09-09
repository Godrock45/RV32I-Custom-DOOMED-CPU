module PrgCo(
    input clk,
    input rst,
    input pc_en,
    input [31:0]next_pc,
    output logic [31:0]pc
);
always_ff @(posedge clk) begin
    if(rst)begin
        pc<=0;
    end
    else if(pc_en) begin
        pc<=next_pc;
    end
    else begin
        pc<=pc;
    end
end





endmodule