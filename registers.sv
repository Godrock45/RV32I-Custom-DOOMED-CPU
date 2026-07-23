module registers(
    input clk,
    input we,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0]rd,
    input [31:0]wd
    output logic [31:0] rd1,
    output logic [31:0] rd2
);
logic [31:0] registers[31:0];
always @ begin
    if(we)begin
        registers[rd]=wd;
    end
    rd1=registers[rs1];
    rd2=registers[rs2];
end


endmodule