#!/usr/bin/env python3
"""Stage a synthesisable copy of the core, for one variant, into a directory.

usage:  make_core.py <variant> <outdir>

variants
  baseline      rtl/ exactly as it is
  narrow_flush  flush/stall clear only id_instr and the six side-effecting ID/EX
                control bits, instead of every bit of IF/ID and ID/EX
  noreset       register file without its reset loop, so it maps to distributed RAM
  combo         narrow_flush + noreset

Writes into <outdir>:
  core_synth.sv   top.sv with the two memories hoisted to ports. The real top_wire
                  has no functional outputs (its debug ports are tied to 0), so a
                  synthesiser would delete the whole core as unobservable. Ports are
                  also how the core would ship as IP, with memories as SRAM macros.
  top_sim.sv      the full top_wire for this variant, for simulation with verif/
  the other rtl modules (registers.sv replaced for the noreset variants)
  ecp5.ys  ice40.ys  generic.ys

rtl/ itself is never modified.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.normpath(os.path.join(HERE, "..", "..", "rtl"))
VARIANTS = ("baseline", "narrow_flush", "noreset", "combo")
MODULES = ("ALU", "PC", "control", "cmp", "decoder", "registers", "load_extend", "forward", "hazard")

NARROW = '''    // IF/ID -- data holds on stall; only the instruction word is squashed on flush
    always_ff @(posedge clk) begin
        if (rst) begin
            id_pc <= 0; id_pc_plus4 <= 0;
        end else if (!stall) begin
            id_pc <= if_pc; id_pc_plus4 <= if_pc_plus4;
        end
    end
    always_ff @(posedge clk) begin
        if (rst || flush) id_instr <= 32'd0;
        else if (!stall)  id_instr <= if_instr;
    end

    // ID/EX data -- never flushed: a bubble's data is dead because its control bits are 0
    always_ff @(posedge clk) begin
        if (rst) begin
            ex_pc<=0; ex_pc_plus4<=0; ex_rd1<=0; ex_rd2<=0; ex_imm<=0;
            ex_rs1<=0; ex_rs2<=0; ex_rd<=0; ex_funct3<=0;
            ex_AluCtrl<=0; ex_AluSrc<=0; ex_AluSrcA<=0;
        end else begin
            ex_pc<=id_pc; ex_pc_plus4<=id_pc_plus4; ex_rd1<=id_rd1; ex_rd2<=id_rd2; ex_imm<=id_imm;
            ex_rs1<=id_rs1; ex_rs2<=id_rs2; ex_rd<=id_rd; ex_funct3<=id_funct3;
            ex_AluCtrl<=id_AluCtrl; ex_AluSrc<=id_AluSrc; ex_AluSrcA<=id_AluSrcA;
        end
    end
    // ID/EX control -- only the side-effecting bits are squashed on flush/stall
    always_ff @(posedge clk) begin
        if (rst || flush || stall) begin
            ex_RegWrite<=0; ex_MemRead<=0; ex_MemWrite<=0; ex_MemToReg<=0; ex_Branch<=0; ex_Jump<=0;
        end else begin
            ex_RegWrite<=id_RegWrite; ex_MemRead<=id_MemRead; ex_MemWrite<=id_MemWrite;
            ex_MemToReg<=id_MemToReg; ex_Branch<=id_Branch; ex_Jump<=id_Jump;
        end
    end

'''

def narrow_flush(src):
    try:
        a = src.index("    // IF/ID\n    always_ff")
        c = src.index("        always_comb begin\n            case(fwd_a)")
    except ValueError:
        sys.exit("make_core.py: top.sv no longer has the expected IF/ID ... forwarding-mux "
                 "layout; update narrow_flush() to match")
    return src[:a] + NARROW + src[c:]

def to_core(src):
    hdr = src[src.index("module top_wire("):src.index(");") + 2]
    src = src.replace(hdr, """module core_synth(
    input  logic        clk,
    input  logic        rst,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [2:0]  dmem_funct3,
    output logic        dmem_we,
    input  logic [31:0] dmem_rdata
    );""", 1)
    rom = "ROME dc(.PC(if_pc),.IR(if_instr));"
    assert rom in src, "ROME instance not found in top.sv"
    src = src.replace(rom, "assign imem_addr = if_pc; assign if_instr = imem_rdata;", 1)
    i = src.index("memory meme("); j = src.index(";", i) + 1
    src = src[:i] + ("assign dmem_addr = mem_alu_res; assign dmem_wdata = mem_rd2; "
                     "assign dmem_funct3 = mem_funct3; assign dmem_we = mem_MemWrite; "
                     "assign mem_dat = dmem_rdata;") + src[j:]
    return src[:src.index("//debug assignments")] + src[src.index("endmodule"):]

def noreset(regsrc):
    out = re.sub(r"if\s*\(\s*rst\s*\)\s*begin.*?end\s*else\s+if", "if", regsrc, count=1, flags=re.S)
    assert out != regsrc, "reset branch not found in registers.sv"
    return out

def main():
    if len(sys.argv) != 3 or sys.argv[1] not in VARIANTS:
        sys.exit(__doc__)
    variant, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for m in MODULES:
        shutil.copy(os.path.join(RTL, m + ".sv"), out)
    for ys in ("ecp5.ys", "ice40.ys", "generic.ys"):
        shutil.copy(os.path.join(HERE, ys), out)

    top = open(os.path.join(RTL, "top.sv")).read()
    if variant in ("narrow_flush", "combo"):
        top = narrow_flush(top)
    open(os.path.join(out, "top_sim.sv"), "w").write(top)
    open(os.path.join(out, "core_synth.sv"), "w").write(to_core(top))

    if variant in ("noreset", "combo"):
        reg = open(os.path.join(RTL, "registers.sv")).read()
        open(os.path.join(out, "registers.sv"), "w").write(noreset(reg))
    print(f"staged {variant} into {out}")

if __name__ == "__main__":
    main()
