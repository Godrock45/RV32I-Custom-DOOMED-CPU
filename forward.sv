// Forwarding unit.
//
// The consumer is always EX. A producer can still be in flight in EX/MEM
// (1 instruction ahead) or MEM/WB (2 ahead). Distance 3 is already handled by
// the write-first read ports in registers.sv, and 4+ is in the array.
//
// EX/MEM is checked FIRST: if two instructions both wrote the same register,
// the one in MEM is the more recent, so it holds the value that should win.
module forward(
    input  logic [4:0] ex_rs1,
    input  logic [4:0] ex_rs2,
    input  logic [4:0] mem_rd,
    input  logic [4:0] wb_rd,
    input  logic       mem_RegWrite,
    input  logic       wb_RegWrite,
    output logic [1:0] fwd_a,        // 00 = ex_rd1, 01 = EX/MEM, 10 = MEM/WB
    output logic [1:0] fwd_b
);

    always_comb begin
        fwd_a = 2'b00;
        if      (mem_RegWrite && mem_rd != 5'd0 && mem_rd == ex_rs1) fwd_a = 2'b01;
        else if (wb_RegWrite  && wb_rd  != 5'd0 && wb_rd  == ex_rs1) fwd_a = 2'b10;

        fwd_b = 2'b00;
        if      (mem_RegWrite && mem_rd != 5'd0 && mem_rd == ex_rs2) fwd_b = 2'b01;
        else if (wb_RegWrite  && wb_rd  != 5'd0 && wb_rd  == ex_rs2) fwd_b = 2'b10;
    end

endmodule
