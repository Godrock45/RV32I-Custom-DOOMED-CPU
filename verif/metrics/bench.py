#!/usr/bin/env python3
"""CPI microbenchmarks. Each isolates one pipeline behaviour.

Writes, into the current directory:
  ROM_<name>.sv   module ROME, 1024 words, indexed by PC[11:2]
  manifest.txt    name start_pc halt_pc expected_s0 expected_dsum   (-1 = not checked)

The measurement window runs from the instruction at start_pc reaching EX until
the halt self-loop reaches EX, so setup code such as array fills is excluded.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from asm import *          # verif/asm.py

M32 = 0xFFFFFFFF

class Prog:
    def __init__(s, name): s.name, s.items, s.labels = name, [], {}
    def L(s, lab):   s.labels[lab] = len(s.items)
    def I(s, word):  s.items.append(lambda i, L, w=word: w)
    def B(s, mk, a, b, lab): s.items.append(lambda i, L: mk(a, b, (L[lab] - i) * 4))
    def J(s, rd, lab):       s.items.append(lambda i, L: jal(rd, (L[lab] - i) * 4))
    def halt(s): s.L("halt"); s.I(beq("x0", "x0", 0))
    def words(s): return [f(i, s.labels) for i, f in enumerate(s.items)]

def fill(p, n, alternate=False):
    """data[0..n-1] = 1..n  (or 3,7,3,7... if alternate). Outside the window."""
    p.I(addi("x10", "x0", 0)); p.I(addi("x11", "x0", n))
    p.I(addi("x12", "x0", 3 if alternate else 1))
    p.L("fill")
    p.I(sw("x12", 0, "x10"))
    p.I(xori("x12", "x12", 4) if alternate else addi("x12", "x12", 1))
    p.I(addi("x10", "x10", 4)); p.I(addi("x11", "x11", -1))
    p.B(bne, "x11", "x0", "fill")

W = []   # (Prog, expected_s0, expected_dsum)

# 1. dependent ALU chain: every instruction consumes the previous result.
#    Exercises EX/MEM->EX forwarding every cycle. No memory, no branches.
p = Prog("alu_chain"); p.L("start"); p.I(addi("x8", "x0", 1)); v = 1
for k in range(120):
    if   k % 3 == 0: p.I(add ("x8", "x8", "x8")); v = (v + v) & M32
    elif k % 3 == 1: p.I(xori("x8", "x8", 0x55)); v = v ^ 0x55
    else:            p.I(addi("x8", "x8", 3));    v = (v + 3) & M32
p.halt(); W.append((p, v, None))

# 2. array sum, naive: the add consumes the load immediately -> 1 load-use stall/iter
p = Prog("sum_naive"); fill(p, 64); p.L("start")
p.I(addi("x10", "x0", 0)); p.I(addi("x11", "x0", 64)); p.I(addi("x8", "x0", 0))
p.L("loop")
p.I(lw("x5", 0, "x10")); p.I(add("x8", "x8", "x5"))
p.I(addi("x10", "x10", 4)); p.I(addi("x11", "x11", -1))
p.B(bne, "x11", "x0", "loop"); p.halt(); W.append((p, 2080, None))

# 3. array sum, scheduled: independent work hoisted between load and use
p = Prog("sum_sched"); fill(p, 64); p.L("start")
p.I(addi("x10", "x0", 0)); p.I(addi("x11", "x0", 64)); p.I(addi("x8", "x0", 0))
p.L("loop")
p.I(lw("x5", 0, "x10")); p.I(addi("x10", "x10", 4)); p.I(addi("x11", "x11", -1))
p.I(add("x8", "x8", "x5"))
p.B(bne, "x11", "x0", "loop"); p.halt(); W.append((p, 2080, None))

# 4. array sum, unrolled x4 and scheduled: amortises the taken-branch penalty
p = Prog("sum_unroll4"); fill(p, 64); p.L("start")
p.I(addi("x10", "x0", 0)); p.I(addi("x11", "x0", 64)); p.I(addi("x8", "x0", 0))
p.L("loop")
p.I(lw("x5", 0, "x10")); p.I(lw("x6", 4, "x10")); p.I(lw("x7", 8, "x10")); p.I(lw("x28", 12, "x10"))
p.I(add("x8", "x8", "x5")); p.I(add("x8", "x8", "x6"))
p.I(add("x8", "x8", "x7")); p.I(add("x8", "x8", "x28"))
p.I(addi("x10", "x10", 16)); p.I(addi("x11", "x11", -4))
p.B(bne, "x11", "x0", "loop"); p.halt(); W.append((p, 2080, None))

# 5. memcpy, naive: the store's data register is the just-loaded value -> stalls
p = Prog("memcpy_naive"); fill(p, 64); p.L("start")
p.I(addi("x10", "x0", 0)); p.I(addi("x12", "x0", 256)); p.I(addi("x11", "x0", 64))
p.L("loop")
p.I(lw("x5", 0, "x10")); p.I(sw("x5", 0, "x12"))
p.I(addi("x10", "x10", 4)); p.I(addi("x12", "x12", 4)); p.I(addi("x11", "x11", -1))
p.B(bne, "x11", "x0", "loop"); p.halt(); W.append((p, None, 2080))

# 6. memcpy, scheduled: one instruction between load and store
p = Prog("memcpy_sched"); fill(p, 64); p.L("start")
p.I(addi("x10", "x0", 0)); p.I(addi("x12", "x0", 256)); p.I(addi("x11", "x0", 64))
p.L("loop")
p.I(lw("x5", 0, "x10")); p.I(addi("x10", "x10", 4)); p.I(sw("x5", 0, "x12"))
p.I(addi("x12", "x12", 4)); p.I(addi("x11", "x11", -1))
p.B(bne, "x11", "x0", "loop"); p.halt(); W.append((p, None, 2080))

# 7. call/return: jal + jalr every iteration
p = Prog("call_ret"); p.L("start")
p.I(addi("x11", "x0", 32)); p.I(addi("x8", "x0", 0))
p.L("loop")
p.J("x1", "func"); p.I(addi("x11", "x11", -1))
p.B(bne, "x11", "x0", "loop"); p.J("x0", "halt")
p.L("func"); p.I(addi("x8", "x8", 1)); p.I(jalr("x0", 0, "x1"))
p.halt(); W.append((p, 32, None))

# 8. data-dependent branch, ~50% taken: count elements >= 5 in 3,7,3,7,...
p = Prog("branchy"); fill(p, 64, alternate=True); p.L("start")
p.I(addi("x10", "x0", 0)); p.I(addi("x11", "x0", 64)); p.I(addi("x8", "x0", 0)); p.I(addi("x9", "x0", 5))
p.L("loop")
p.I(lw("x5", 0, "x10")); p.I(addi("x10", "x10", 4)); p.I(addi("x11", "x11", -1))
p.B(blt, "x5", "x9", "skip"); p.I(addi("x8", "x8", 1))
p.L("skip"); p.B(bne, "x11", "x0", "loop"); p.halt(); W.append((p, 32, None))

with open("manifest.txt", "w", newline="\n") as man:
    for p, es0, eds in W:
        ws = p.words()
        assert len(ws) <= 1024
        with open(f"ROM_{p.name}.sv", "w") as f:
            f.write("// generated by verif/metrics/bench.py -- do not edit\n")
            f.write("module ROME(input [31:0] PC, output [31:0] IR);\n")
            f.write("reg [31:0] m [1023:0];\ninteger k;\ninitial begin\n")
            f.write("  for (k = 0; k < 1024; k = k + 1) m[k] = 32'h00000013;\n")
            for i, w in enumerate(ws):
                f.write(f"  m[{i}] = 32'h{w:08X};\n")
            f.write("end\nassign IR = m[PC[11:2]];\nendmodule\n")
        man.write(f"{p.name} {p.labels['start']*4} {p.labels['halt']*4} "
                  f"{es0 if es0 is not None else -1} {eds if eds is not None else -1}\n")
        print(f"{p.name:14s} {len(ws):4d} words  start=0x{p.labels['start']*4:03X}  halt=0x{p.labels['halt']*4:03X}")
