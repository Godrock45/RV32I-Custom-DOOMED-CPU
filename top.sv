module top_wire(
    input clk,
    input rst,
    //debug assist
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic dbg_reg_we,
    output logic [4:0] dbg_rd,
    output logic [31:0] dbg_wb_data,
    output logic halt
    );

    reg [31:0] next_PC_loc,PC_loc;
    reg [31:0] IR_loc;
    reg pc_en_loc;
    reg [4:0] rd_loc;
    reg [4:0] rs1_loc;
    reg [4:0] rs2_loc;
    reg [6:0] funct7_loc;
    reg [2:0] funct3_loc;
    reg [31:0] imm_loc;
    reg [6:0] opcode_loc;
    reg RegWrite_loc;
    reg AluSrc_loc;
    reg MemRead_loc;
    reg MemWrite_loc;
    reg [3:0]AluCtrl_loc;
    reg Branch_loc;
    reg Jump_loc;
    reg AluSrcA_loc;
    reg MemToReg_loc;
    reg [31:0]wd_loc;
    reg [31:0] rd1_loc;
    reg [31:0] rd2_loc;
    reg cmp_loc;
    reg [31:0]res_loc;
    reg [31:0]mem_dat_loc;
    reg [31:0]addr_loc;
    reg [31:0]dat_loc;











    PrgCo ad(.clk(clk),.rst(rst),.pc_en(pc_en_loc),.next_pc(next_PC_loc),.pc(PC_loc));
    ROME dc(.PC(PC_loc),.IR(IR_loc));
    decoder tnt(.instruction(IR_loc),.imm(imm_loc),.rd(rd_loc),.rs1(rs1_loc),.rs2(rs2_loc),.funct7(funct7_loc),.funct3(funct3_loc));
    control pnp(.Opcode(opcode_loc),.funct3(funct3_loc),.funct7(funct7_loc),.RegWrite(RegWrite_loc),.AluSrc(AluSrc_loc),.MemRead(MemRead_loc),.MemWrite(MemWrite_loc),.AluCtrl(AluCtrl_loc),.Branch(Branch_loc),.Jump(Jump_loc),.AluSrcA(AluSrcA_loc),.MemToReg(MemToReg_loc));
    registers npn(.clk(clk),.rst(rst),.we(RegWrite_loc),.rs1(rs1_loc),.rs2(rs2_loc),.rd(rd_loc),.wd(wd_loc),.rd1(rd1_loc),.rd2(rd2_loc));
    comparator mph(.OpA(rd1_loc),.OpB(rd2_loc),.funct3(funct3_loc),.cmp(cmp_loc));
    ALU tsmc(.OpA(rd1_loc),.OpB(rd2_loc),.AluCtrl(AluCtrl_loc),.Res(res_loc));
    memory meme(.clk(clk),.addr(addr_loc),.dat(dat_loc),.funct3(funct3_loc),.write_ena(MemWrite_loc),.mem_dat(mem_dat_loc));

    assign rs1_loc=AluSrcA_loc?PC_loc:rd1_loc;
    assign r2_loc=AluSrc_loc?imm_loc:rd2_loc;
    assign next_PC_loc=(Jump_loc&Branch_loc)?(res_loc&~32'd1):(~Jump_loc&Branch_loc)?((cmp_loc)?res_loc:(PC_loc+32'b4)):(Jump_loc&~Branch_loc)?res_loc:(PC_loc+32'b4);
    assign addr_loc=(MemToReg|MemWrite)?res_loc:32'b0;
    assign dat_loc=(MemWrite_loc)?rd2_loc:32'b0;
    




endmodule