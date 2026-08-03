#!/usr/bin/env python3
"""Tiny RV32I assembler -> hex words, enough to build directed tests."""

R = {f"x{i}": i for i in range(32)}

def s(v, bits):           # sign-fit check
    lo, hi = -(1 << (bits-1)), (1 << (bits-1)) - 1
    assert lo <= v <= hi, f"imm {v} out of range for {bits} bits"
    return v & ((1 << bits) - 1)

def rtype(f7, rs2, rs1, f3, rd, op):
    return (f7<<25)|(R[rs2]<<20)|(R[rs1]<<15)|(f3<<12)|(R[rd]<<7)|op
def itype(imm, rs1, f3, rd, op):
    return (s(imm,12)<<20)|(R[rs1]<<15)|(f3<<12)|(R[rd]<<7)|op
def shtype(f7, sh, rs1, f3, rd, op):
    return (f7<<25)|(sh<<20)|(R[rs1]<<15)|(f3<<12)|(R[rd]<<7)|op
def stype(imm, rs2, rs1, f3, op):
    i = s(imm,12)
    return ((i>>5)<<25)|(R[rs2]<<20)|(R[rs1]<<15)|(f3<<12)|((i&0x1f)<<7)|op
def btype(imm, rs2, rs1, f3, op):
    i = s(imm,13)
    return (((i>>12)&1)<<31)|(((i>>5)&0x3f)<<25)|(R[rs2]<<20)|(R[rs1]<<15)|\
           (f3<<12)|(((i>>1)&0xf)<<8)|(((i>>11)&1)<<7)|op
def utype(imm, rd, op):
    return ((imm & 0xfffff)<<12)|(R[rd]<<7)|op
def jtype(imm, rd, op):
    i = s(imm,21)
    return (((i>>20)&1)<<31)|(((i>>1)&0x3ff)<<21)|(((i>>11)&1)<<20)|\
           (((i>>12)&0xff)<<12)|(R[rd]<<7)|op

OP, OPIMM, LOAD, STORE, BRANCH, JAL_, JALR_, LUI_, AUIPC_ = \
    0x33, 0x13, 0x03, 0x23, 0x63, 0x6f, 0x67, 0x37, 0x17

def add (d,a,b): return rtype(0x00,b,a,0,d,OP)
def sub (d,a,b): return rtype(0x20,b,a,0,d,OP)
def sll (d,a,b): return rtype(0x00,b,a,1,d,OP)
def slt (d,a,b): return rtype(0x00,b,a,2,d,OP)
def sltu(d,a,b): return rtype(0x00,b,a,3,d,OP)
def xor_(d,a,b): return rtype(0x00,b,a,4,d,OP)
def srl (d,a,b): return rtype(0x00,b,a,5,d,OP)
def sra (d,a,b): return rtype(0x20,b,a,5,d,OP)
def or_ (d,a,b): return rtype(0x00,b,a,6,d,OP)
def and_(d,a,b): return rtype(0x00,b,a,7,d,OP)

def addi(d,a,i): return itype(i,a,0,d,OPIMM)
def slti (d,a,i): return itype(i,a,2,d,OPIMM)
def sltiu(d,a,i): return itype(i,a,3,d,OPIMM)
def xori(d,a,i): return itype(i,a,4,d,OPIMM)
def ori (d,a,i): return itype(i,a,6,d,OPIMM)
def andi(d,a,i): return itype(i,a,7,d,OPIMM)
def slli(d,a,i): return shtype(0x00,i,a,1,d,OPIMM)
def srli(d,a,i): return shtype(0x00,i,a,5,d,OPIMM)
def srai(d,a,i): return shtype(0x20,i,a,5,d,OPIMM)

def lb (d,i,a): return itype(i,a,0,d,LOAD)
def lh (d,i,a): return itype(i,a,1,d,LOAD)
def lw (d,i,a): return itype(i,a,2,d,LOAD)
def lbu(d,i,a): return itype(i,a,4,d,LOAD)
def lhu(d,i,a): return itype(i,a,5,d,LOAD)

def sb(v,i,a): return stype(i,v,a,0,STORE)
def sh(v,i,a): return stype(i,v,a,1,STORE)
def sw(v,i,a): return stype(i,v,a,2,STORE)

def beq (a,b,o): return btype(o,b,a,0,BRANCH)
def bne (a,b,o): return btype(o,b,a,1,BRANCH)
def blt (a,b,o): return btype(o,b,a,4,BRANCH)
def bge (a,b,o): return btype(o,b,a,5,BRANCH)
def bltu(a,b,o): return btype(o,b,a,6,BRANCH)
def bgeu(a,b,o): return btype(o,b,a,7,BRANCH)

def jal (d,o):   return jtype(o,d,JAL_)
def jalr(d,i,a): return itype(i,a,0,d,JALR_)
def lui (d,i):   return utype(i,d,LUI_)
def auipc(d,i):  return utype(i,d,AUIPC_)
def nop():       return addi("x0","x0",0)
