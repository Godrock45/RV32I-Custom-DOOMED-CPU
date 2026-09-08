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
    logic [31:0]id_pc,id_pc_plus4,id_instr;

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








    PrgCo ad(.clk(clk),.rst(rst),.pc_en(1'b1),.next_pc(next_pc),.pc(if_pc));
    ROME dc(.PC(if_pc),.IR(if_instr));
    decoder tnt(.instruction(id_instr),.opcode(id_opcode),.imm(id_imm),.rd(id_rd),.rs1(id_rs1),.rs2(id_rs2),.funct7(id_funct7),.funct3(id_funct3));
    control pnp(.Opcode(id_opcode),.funct3(id_funct3),.funct7(id_funct7),.RegWrite(id_RegWrite),.AluSrc(id_AluSrc),.MemRead(id_MemRead),.MemWrite(id_MemWrite),.AluCtrl(id_AluCtrl),.Branch(id_Branch),.Jump(id_Jump),.AluSrcA(id_AluSrcA),.MemToReg(id_MemToReg));
    registers npn(.clk(clk),.rst(rst),.we(id_RegWrite),.rs1(id_rs1),.rs2(id_rs2),.rd(id_rd),.wd(id_data),.rd1(id_rd1),.rd2(id_rd2));
    comparator mph(.OpA(ex_rd1),.OpB(ex_rd2),.funct3(ex_funct3),.cmp(ex_cmp));
    ALU tsmc(.OpA(ex_opA),.OpB(ex_opB),.ALUCtrl(ex_AluCtrl),.Res(ex_alu_res));
    memory meme(.clk(clk),.addr(mem_alu_res),.dat(mem_rd2),.funct3(mem_funct3),.write_ena(mem_MemWrite),.mem_dat(mem_dat));
    load_extend ext(.mem_dat(mem_dat),.addr_lo(mem_funct3),.load_data(mem_load_data));





    //transitions
    assign if_pc_plus4 = if_pc + 32'd4;
    // IF/ID
    always_ff @(posedge clk) begin
        if(rst) begin
            id_pc<=0;
            id_pc_plus4<=0;
            id_instr<=0;
        end else begin
            id_pc<=if_pc;
            id_pc_plus4<=if_pc_plus4;
            id_instr<=if_instr;
    end
    end

    // ID/EX
    always_ff @(posedge clk) begin
        if(rst) begin
            ex_pc<=0;ex_pc_plus4<=0;ex_rd1<=0;ex_rd2<=0;ex_imm<=0;ex_rs1<=0;
            ex_rs2<=0;ex_rd<=0;ex_funct3<=0;ex_AluCtrl<=0;ex_RegWrite<=0;
            ex_AluSrc<=0;ex_AluSrcA<=0;ex_MemRead<=0;ex_MemWrite<=0; ex_MemToReg<=0;
            ex_Branch<=0;ex_Jump<=0;
        end
        else begin
            ex_pc<=id_pc;    ex_pc_plus4<=id_pc_plus4;
            ex_rd1<=id_rd1;  ex_rd2<=id_rd2;    ex_imm<=id_imm;
            ex_rs1<=id_rs1;  ex_rs2<=id_rs2;    ex_rd<=id_rd;
            ex_funct3<=id_funct3;  ex_AluCtrl<=id_AluCtrl;
            ex_RegWrite<=id_RegWrite;   ex_AluSrc<=id_AluSrc;
            ex_AluSrcA<=id_AluSrcA; ex_MemRead<=id_MemRead;
            ex_MemWrite<=id_MemWrite;   ex_MemToReg<=id_MemToReg;
            ex_Branch<=id_Branch;   ex_Jump<=id_Jump;
        end
        end
        assign ex_opA=ex_AluSrcA?ex_pc:ex_rd1;
        assign ex_opB=ex_AluSrc?ex_imm:ex_rd2;
        

        always_comb begin
            unique case({ex_Branch,ex_Jump})
                2'b01:
                    next_pc=ex_alu_res;
                2'b10:
                    next_pc=ex_cmp?ex_alu_res:if_pc_plus4;
                2'b11:
                    next_pc=ex_alu_res&~32'd1;
                default:
                    next_pc=if_pc_plus4;
            endcase
        end
        // -----EX/MEM-----
        always_ff @(posedge clk)begin
            if(rst)begin
                mem_alu_res<=0;  mem_rd2<=0;   mem_pc_plus4<=0;
                mem_rd<=0;       mem_funct3<=0; mem_RegWrite<=0;
                mem_MemRead<=0;  mem_MemToReg<=0; mem_Jump<=0; mem_MemWrite<=0;

            end 
            else begin
                mem_alu_res<=ex_alu_res;   mem_rd2 <=ex_rd2;
                mem_pc_plus4<=ex_pc_plus4;  mem_rd<=ex_rd;
                mem_funct3<=ex_funct3;  mem_RegWrite<=ex_RegWrite; mem_MemWrite<=ex_MemWrite;
                mem_MemToReg<=ex_MemToReg; mem_Jump<=ex_Jump;
            end
        end
        // -----MEM/WB-----
        always_ff @(posedge clk)begin
            if(rst)begin
                wb_alu_res<=0; wb_load_data<=0;  wb_pc_plus4<=0;
                wb_rd<=0; wb_RegWrite<=0;  wb_MemToReg<=0; wb_Jump<=0;
            end
            else begin
                wb_alu_res<=mem_alu_res;    wb_load_data<=mem_load_data;
                wb_pc_plus4<=mem_pc_plus4;  wb_rd<=mem_rd;
                wb_RegWrite<=mem_RegWrite; wb_MemToReg<=mem_MemToReg;
                wb_Jump<=mem_Jump;
            end
        end

        // -----WB-----
        assign wb_data=(wb_MemToReg)?wb_load_data:wb_Jump?(wb_pc_plus4+32'd4):wb_alu_res;
    
    




    /*/debug assignments
    assign dbg_pc      = PC_loc;
    assign dbg_instr   = IR_loc;    
    assign dbg_reg_we  = RegWrite_loc;
    assign dbg_rd      = rd_loc;
    assign dbg_wb_data = wd_loc;
    assign halt        = 1'b0;

*/


endmodule