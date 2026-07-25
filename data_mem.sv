module memory(
    input clk,
    input [31:0]addr,
    input [31:0]dat,
    input write_ena,
    output logic [31:0]mem_dat
);
reg [31:0] memistan [255:0];
always_comb begin
    if(~write_ena) begin
    mem_dat=memistan[addr[9:2]];
    end
end

always_ff @(posedge clk) begin
    if(write_ena) begin
        memistan[addr[9:2]]<=dat;
    end
end







endmodule