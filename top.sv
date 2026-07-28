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

    logic [31:0] next_PC_loc,PC_loc;
    logic [31:0] IR_loc;
    logic pc_en_loc;
    logic [4:0] rd_loc;
    logic [4:0] rs1_loc;
    logic [4:0] rs2_loc;
    logic [6:0] funct7_loc;
    logic [2:0] funct3_loc;
    logic [31:0] imm_loc;
    logic [6:0] opcode_loc;
    logic RegWrite_loc;
    logic AluSrc_loc;
    logic MemRead_loc;
    logic MemWrite_loc;
    logic [3:0] AluCtrl_loc;
    logic Branch_loc;
    logic Jump_loc;
    logic AluSrcA_loc;
    logic MemToReg_loc;
    logic [31:0] wd_loc;
    logic [31:0] rd1_loc;
    logic [31:0] rd2_loc;
    logic cmp_loc;
    logic [31:0] res_loc;
    logic [31:0] mem_dat_loc;
    logic [31:0] addr_loc;
    logic [31:0] dat_loc;
    logic [31:0] OpA_loc,OpB_loc;
    logic [7:0] b;
    logic [15:0]h;








    PrgCo ad(.clk(clk),.rst(rst),.pc_en(pc_en_loc),.next_pc(next_PC_loc),.pc(PC_loc));
    ROME dc(.PC(PC_loc),.IR(IR_loc));
    decoder tnt(.instruction(IR_loc),.opcode(opcode_loc),.imm(imm_loc),.rd(rd_loc),.rs1(rs1_loc),.rs2(rs2_loc),.funct7(funct7_loc),.funct3(funct3_loc));
    control pnp(.Opcode(opcode_loc),.funct3(funct3_loc),.funct7(funct7_loc),.RegWrite(RegWrite_loc),.AluSrc(AluSrc_loc),.MemRead(MemRead_loc),.MemWrite(MemWrite_loc),.AluCtrl(AluCtrl_loc),.Branch(Branch_loc),.Jump(Jump_loc),.AluSrcA(AluSrcA_loc),.MemToReg(MemToReg_loc));
    registers npn(.clk(clk),.rst(rst),.we(RegWrite_loc),.rs1(rs1_loc),.rs2(rs2_loc),.rd(rd_loc),.wd(wd_loc),.rd1(rd1_loc),.rd2(rd2_loc));
    comparator mph(.OpA(rd1_loc),.OpB(rd2_loc),.funct3(funct3_loc),.cmp(cmp_loc));
    ALU tsmc(.OpA(OpA_loc),.OpB(OpB_loc),.AluCtrl(AluCtrl_loc),.Res(res_loc));
    memory meme(.clk(clk),.addr(addr_loc),.dat(dat_loc),.funct3(funct3_loc),.write_ena(MemWrite_loc),.mem_dat(mem_dat_loc));

    assign b=memy[8*res_loc[1:0]+:8];
    assign h=memy[16*res_loc[1]+:16];
    case(funct3_loc)
        3'b000:
            load_data={24'b0,mem_dat_loc[7:0]};
        3'b001:
            load_data={16'b0,mem_dat_loc[15:0]};
        3'b010:
            load_data=mem_dat_loc;
        3'b100:
            load_data={24{mem_dat_loc[7]},mem_dat_loc[7:0]};
        3'b101:
            load_data={16{mem_dat_loc[15]},mem_dat_loc[15:0]};
        default:
            load_data=32'b0;
    endcase

    assign pc_en_loc=1'b1;
    assign OpA=AluSrcA_loc?PC_loc:rd1_loc;
    assign OpB=AluSrc_loc?imm_loc:rd2_loc;
    assign next_PC_loc=(Jump_loc&Branch_loc)?(res_loc&~32'd1):(~Jump_loc&Branch_loc)?((cmp_loc)?res_loc:(PC_loc+32'd4)):(Jump_loc&~Branch_loc)?res_loc:(PC_loc+32'd4);
    assign addr_loc=res_loc;
    assign dat_loc=rd2_loc;
    assign wd_loc=(MemtoReg_loc)?load_data:Jump_loc?(PC_loc+32'd4):res_loc;





endmodule