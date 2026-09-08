module registers(
    input clk,
    input rst,
    input we,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0]rd,
    input [31:0]wd,
    output logic [31:0] rd1,
    output logic [31:0] rd2
);
logic [31:0] registers[31:0];
always_comb begin
    rd1=(we&&rd==rs1&&rs1!=5'd0)?wd:registers[rs1];
    rd2=(we&&rd==rs2&&rs2!=5'd0)?wd:registers[rs2];
end


always_ff @( posedge clk ) begin
    if(rst)begin
        for(int i=0;i<32;i++)begin
            registers[i]<=0;
        end
    end
    else if(we&&rd!=5'b0) begin
        registers[rd]<=wd;
    end
end

endmodule