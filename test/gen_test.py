#!/usr/bin/env python3
"""Build a directed RV32I test, emit ROM init + expected register values."""
from asm import *

P, EXP, MEXP = [], {}, {}
def e(instr, note=""): P.append((instr, note)); return len(P)-1
def idx(): return len(P)

M32 = 0xFFFFFFFF

# ---------------- phase 1: ALU / immediates ----------------
e(addi("x1","x0",5));            EXP[1]  = 5
e(addi("x2","x0",3));            EXP[2]  = 3
e(add ("x3","x1","x2"));         EXP[3]  = 8
e(sub ("x4","x1","x2"));         EXP[4]  = 2
e(and_("x5","x1","x2"));         EXP[5]  = 5 & 3
e(or_ ("x6","x1","x2"));         EXP[6]  = 5 | 3
e(xor_("x7","x1","x2"));         EXP[7]  = 5 ^ 3
e(sll ("x8","x1","x2"));         EXP[8]  = 5 << 3
e(srl ("x9","x1","x2"));         EXP[9]  = 5 >> 3
e(slt ("x10","x2","x1"));        EXP[10] = 1                    # 3 < 5 signed
e(addi("x11","x0",-1));          EXP[11] = M32
e(sltu("x12","x11","x1"));       EXP[12] = 0                    # 0xFFFFFFFF < 5 unsigned? no
e(slt ("x13","x11","x1"));       EXP[13] = 1                    # -1 < 5 signed? yes
e(srai("x14","x11",1));          EXP[14] = M32                  # -1 >>> 1 == -1
e(srli("x15","x11",28));         EXP[15] = 0xF

# ---------------- phase 1b: OP-IMM variants + SRA ----------------
# All 31 registers already carry expectations, so these park their results in
# data memory instead. x20 is scratch here; phase 3 overwrites it later.
def chk(word, instr, want, note=""):
    """emit `instr` (result in x20), store it to data word `word`, expect `want`"""
    e(instr, note); e(sw("x20", word*4, "x0")); MEXP[word] = want & M32

chk( 8, slti ("x20","x11",0),     1,          "SLTI  -1 < 0 signed")
chk( 9, slti ("x20","x0",-1),     0,          "SLTI  neg imm -> exercises funct7 zeroing")
chk(10, sltiu("x20","x11",5),     0,          "SLTIU 0xFFFFFFFF < 5 unsigned = false")
chk(11, xori ("x20","x1",-1),     5 ^ M32,    "XORI  neg imm")
chk(12, ori  ("x20","x1",8),      5 | 8,      "ORI")
chk(13, andi ("x20","x11",0xF0),  0xF0,       "ANDI")
chk(14, slli ("x20","x1",4),      5 << 4,     "SLLI")
chk(15, sra  ("x20","x11","x2"),  M32,        "SRA   -1 >>> 3 stays -1")
chk(16, srl  ("x20","x11","x2"),  M32 >> 3,   "SRL   logical, for contrast with SRA")

# ---------------- phase 2: LUI / AUIPC ----------------
e(lui("x16",0xABCDE));           EXP[16] = 0xABCDE000
auipc_i = idx()
e(auipc("x17",0x1));             EXP[17] = (auipc_i*4 + 0x1000) & M32

# ---------------- phase 3: loads / stores ----------------
e(addi("x18","x0",0x7F));        EXP[18] = 0x7F
e(sw("x18",0,"x0"))
e(lw("x19",0,"x0"));             EXP[19] = 0x7F

# four SBs into one word -> tests store lane placement
e(addi("x20","x0",0x11))
e(sb("x20",4,"x0"))
e(addi("x20","x0",0x22))
e(sb("x20",5,"x0"))
e(addi("x20","x0",0x33))
e(sb("x20",6,"x0"))
e(addi("x20","x0",0x44));        EXP[20] = 0x44
e(sb("x20",7,"x0"))
e(lw("x21",4,"x0"));             EXP[21] = 0x44332211   # little-endian assembly

# byte loads at different lanes
e(lb ("x22",4,"x0"));            EXP[22] = 0x11
e(lb ("x23",7,"x0"));            EXP[23] = 0x44

# sign vs zero extension on a negative byte
e(sb("x11",8,"x0"))                                     # byte 8 = 0xFF
e(lb ("x24",8,"x0"));            EXP[24] = M32          # sign-extended
e(lbu("x25",8,"x0"));            EXP[25] = 0xFF         # zero-extended

# halfword, high lane (byte addr 14 -> addr[1]=1)
e(sh("x11",14,"x0"))                                    # half at 14 = 0xFFFF
e(lh ("x26",14,"x0"));           EXP[26] = M32
e(lhu("x27",14,"x0"));           EXP[27] = 0xFFFF

# ---------------- phase 4: branches ----------------
# x28 counts poison that executed -> must stay 0.
# x9 counts must-execute fall-throughs (starts at 0 from srl) -> must equal #nottaken.
EXP[28] = 0
_nt = 0
def taken(mk):        # MUST take: +8 skips the poison
    e(mk(8)); e(addi("x28","x28",1), "poison (branch should skip)")
def nottaken(mk):     # must NOT take: +8 would skip the counter, which we'd detect
    global _nt; _nt += 1
    e(mk(8)); e(addi("x9","x9",1), "must execute"); e(nop())

taken(lambda o: beq ("x1","x1",o))
taken(lambda o: bne ("x1","x2",o))
taken(lambda o: blt ("x11","x1",o))      # -1 < 5   signed
taken(lambda o: bge ("x1","x2",o))       #  5 >= 3
taken(lambda o: bltu("x1","x11",o))      #  5 < 0xFFFFFFFF unsigned
taken(lambda o: bgeu("x11","x1",o))      # 0xFFFFFFFF >= 5 unsigned
taken(lambda o: bge ("x1","x1",o))       # equal -> BGE takes
taken(lambda o: bgeu("x1","x1",o))       # equal -> BGEU takes

nottaken(lambda o: beq ("x1","x2",o))
nottaken(lambda o: bne ("x1","x1",o))
nottaken(lambda o: blt ("x1","x11",o))   #  5 < -1 signed? no
nottaken(lambda o: bltu("x11","x1",o))   # 0xFFFFFFFF < 5 unsigned? no
EXP[9] = _nt                             # srl left it 0; each fall-through adds 1

# ---------------- phase 5: JAL / JALR ----------------
jal_i = idx()
e(jal("x29",8));                 EXP[29] = (jal_i*4 + 4) & M32   # link
e(addi("x28","x28",1), "poison")                                 # must be skipped

# JALR: land two instructions ahead using a computed address
jalr_setup = idx()
e(auipc("x5", 0))                                  # x5 = PC of this instr
EXP[5] = None                                      # overwritten, checked below
jalr_i = idx()
e(jalr("x30", (jalr_i - jalr_setup)*4 + 8, "x5")); EXP[30] = (jalr_i*4 + 4) & M32
e(addi("x28","x28",1), "poison")                                 # must be skipped

land = idx()
e(addi("x31","x0",0x2A));        EXP[31] = 0x2A     # sentinel: we got here

# recompute x5 expectation (auipc x5,0 at jalr_setup)
EXP[5] = (jalr_setup*4) & M32

# ---------------- halt ----------------
halt_i = idx()
e(beq("x0","x0",0), "self-loop")

# ---------------- emit ----------------
with open("ROM_test.sv","w") as f:
    f.write("module ROME(\n    input [31:0]PC,\n    output [31:0] IR\n);\n")
    f.write("reg [31:0] registan [255:0];\ninitial begin\n")
    for i,(w,note) in enumerate(P):
        f.write(f"    registan[{i}]=32'h{w:08X};" + (f"  // {note}\n" if note else "\n"))
    f.write("end\nassign IR=registan[PC[9:2]];\nendmodule\n")

with open("expected.txt","w") as f:
    for r in sorted(EXP):
        f.write(f"REG {r} {EXP[r]:08x}\n")
    for w in sorted(MEXP):
        f.write(f"MEM {w} {MEXP[w]:08x}\n")

print(f"{len(P)} instructions, halt at index {halt_i} (pc=0x{halt_i*4:X})")
print(f"landing index {land}, jal at {jal_i}, jalr at {jalr_i}")
print(f"checking {len(EXP)} registers, {len(MEXP)} memory words")
