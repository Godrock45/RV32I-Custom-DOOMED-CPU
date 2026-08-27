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


    // Fetch
    logic [31:0] if_pc,if_pc_plus4,if_instr,next_pc;

    // IF/ID
    logic [31:0]id_pc,id_pc_plus4,id_instr

    // ID
    logic[6:0] id_opcode, id_funct7;
    logic[2:0] id_funct3;
    logic[4:0] id_rs1,id_rs2,id_rd;
    logic[31:0]id_imm,id_rd1,id_rd2;
    logic id_RegWrite,id_AluSrc,id_AluSrcA,id_MemRead,id_MemWrite,id_MemToReg,id_Branch,id_Jump;
    logic [3:0] id_AluCtrl;

    // ID/EX
    logic [31:0] ex_pc, ex_pc_plus4, ex_rd1, ex_rd2, ex_imm;
    logic [4:0] ex_rs1, ex_rs2, ex_rd;
    logic [2:0] ex_funct3;
    logic [3:0] ex_AluCtrl;
    logic ex_RegWrite, ex_AluSrc, ex_AluSrcA, ex_MemRead, ex_MemWrite, ex_MemToReg, ex_Branch, ex_Jump;
    logic [31:0] ex_opA,ex_opB,ex_alu_res;
    logic ex_cmp;

    // EX/MEM
    logic [31:0] mem_alu_res, mem_rd2, mem_pc_plus4, mem_dat, mem_load_data;
    logic [4:0] mem_rd;
    logic [2:0] mem_funct3;
    logic mem_RegWrite, mem_MemRead, mem_MemWrite, mem_MemToReg, mem_Jump;

    // MEM/WB

    logic [31:0] wb_alu_res, wb_load_data, wb_pc_plus4, wb_data;
    logic [4:0] wb_rd;
    logic wb_RegWrite, wb_MemToReg, wb_Jump;

    
    
    






















































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
    logic [31:0] load_data;






    PrgCo ad(.clk(clk),.rst(rst),.pc_en(pc_en_loc),.next_pc(next_pc),.pc(if_pc));
    ROME dc(.PC(if_pc),.IR(if_instr));
    decoder tnt(.instruction(id_instr),.opcode(id_opcode),.imm(id_imm),.rd(id_rd),.rs1(id_rs1),.rs2(id_rs2),.funct7(id_funct7),.funct3(id_funct3));
    control pnp(.Opcode(id_opcode),.funct3(id_funct3),.funct7(id_funct7),.RegWrite(id_RegWrite),.AluSrc(id_AluSrc),.MemRead(id_MemRead),.MemWrite(id_MemWrite),.AluCtrl(id_AluCtrl),.Branch(id_Branch),.Jump(id_Jump),.AluSrcA(id_AluSrcA),.MemToReg(id_MemToReg));
    registers npn(.clk(clk),.rst(rst),.we(wb_RegWrite),.rs1(id_rs1),.rs2(id_rs2),.rd(wb_rd),.wd(wb_data),.rd1(id_rd1),.rd2(id_rd2));
    comparator mph(.OpA(ex_rd1),.OpB(ex_rd2),.funct3(ex_funct3),.cmp(ex_cmp));
    ALU tsmc(.OpA(ex_opA),.OpB(ex_opB),.ALUCtrl(ex_AluCtrl),.Res(ex_alu_res));
    memory meme(.clk(clk),.addr(mem_alu_res),.dat(mem_rd2),.funct3(mem_funct3),.write_ena(mem_MemWrite),.mem_dat(mem_dat));
    load_extend ext(.mem_dat(mem_dat),.addr_lo(mem_funct3),.load_data(mem_load_data));




    assign b=mem_dat_loc[8*res_loc[1:0]+:8];
    assign h=mem_dat_loc[16*res_loc[1]+:16];
    always_comb begin
        case(funct3_loc)
            3'b000:
                load_data={{24{b[7]}},b[7:0]};
            3'b001:
                load_data={{16{h[15]}},h[15:0]};
            3'b010:
                load_data=mem_dat_loc;
            3'b100:
                load_data={24'b0,b[7:0]};
            3'b101:
                load_data={16'b0,h[15:0]};
            default:
                load_data=32'b0;
        endcase
    end






















    assign pc_en_loc=1'b1;
    assign OpA_loc=AluSrcA_loc?PC_loc:rd1_loc;
    assign OpB_loc=AluSrc_loc?imm_loc:rd2_loc;
    assign next_PC_loc=(Jump_loc&Branch_loc)?(res_loc&~32'd1):(~Jump_loc&Branch_loc)?((cmp_loc)?res_loc:(PC_loc+32'd4)):(Jump_loc&~Branch_loc)?res_loc:(PC_loc+32'd4);
    assign addr_loc=res_loc;
    assign dat_loc=rd2_loc;
    assign wd_loc=(MemToReg_loc)?load_data:Jump_loc?(PC_loc+32'd4):res_loc;




    //debug assignments
    assign dbg_pc      = PC_loc;
    assign dbg_instr   = IR_loc;    
    assign dbg_reg_we  = RegWrite_loc;
    assign dbg_rd      = rd_loc;
    assign dbg_wb_data = wd_loc;
    assign halt        = 1'b0;




endmodule