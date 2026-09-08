# Architecture Reference

Everything the design does, and why. Companion to the README.

---

## 1. Modules

| file | module | stage | role |
|---|---|---|---|
| `PC.sv` | `PrgCo` | IF | program counter, `pc_en` reserved for stalls |
| `ROM.sv` | `ROME` | IF | instruction memory, async read, `PC[15:2]` |
| `decoder.sv` | `decoder` | ID | field extraction + immediate reassembly |
| `control.sv` | `control` | ID | opcode to 9 control signals, pure combinational |
| `registers.sv` | `registers` | **ID + WB** | 32x32 regfile, `x0` write-guarded |
| `cmp.sv` | `comparator` | EX | branch condition, signed/unsigned |
| `ALU.sv` | `ALU` | EX | 10 ops, `{funct7[5], funct3}` encoded |
| `data_mem.sv` | `memory` | MEM | byte/half/word, misalignment guards |
| `load_extend.sv` | `load_extend` | MEM | lane select + sign/zero extension |
| `top.sv` | `top_wire` | all | wiring, muxes, pipeline registers |

`registers` is the only module living in two stages: reads in ID, write port in WB.

---

## 2. Design decisions, and why

**One ALU serves every PC-relative target.** JAL, branches and AUIPC all need `PC + imm`.
Instead of a dedicated branch-target adder, `AluSrcA` steers `PC` onto the ALU A input.
The ALU is idle on branches anyway, because the comparator is a separate unit, so the
adder would have been dead silicon. Only `PC + 4` gets its own adder, since JAL and JALR
need the target and the link value in the same cycle.

**`AluSrcA` is the only bit separating LUI from AUIPC.** Every other control signal is
identical between them. LUI computes `0 + imm`, AUIPC computes `PC + imm`.

**LUI costs no extra hardware.** The decoder leaves `rs1 = 0` for U-type and J-type, and
`x0` is hardwired zero, so the ALU produces `0 + imm` through the normal path. No third
mux input, no extra control bit.

**The decoder zeroing is load-bearing, not hygiene.** Three things depend on it:

- `rs1 = 0` on U/J so LUI works through `x0`
- `funct7 = 0` on non-shift I-type, so `addi x1, x0, -1` does not decode as SUB. Its
  immediate `0xFFF` sets `instruction[30]`, which is `funct7[5]`.
- `rd`, `rs1`, `rs2` zeroed on formats that lack them, so the forwarding and hazard units
  cannot match on a register the instruction never referenced.

**Writeback needs no dedicated selector.** `Jump` is high for exactly JAL and JALR, which
are precisely the two instructions whose `rd` receives `PC + 4`. The existing signal does
the job a wider mux select would have.

**`control` never sees datapath values.** Its inputs are only `opcode`, `funct3`, `funct7`.
That is why it pipelines unchanged: control signals ride the pipeline registers as data,
and hazard logic, which needs `rd`/`rs1`/`rs2`, lives in its own module.

**Load extension sits on the CPU side of memory.** Sign versus zero extension is instruction
semantics, not storage behaviour. Putting it inside `memory` would force every future
peripheral on a bus to reimplement it.

---

## 3. Control signals

Nine outputs, five destinations.

| signal | width | consumer | meaning |
|---|---|---|---|
| `RegWrite` | 1 | `registers.we` (WB) | write `rd` |
| `AluSrcA` | 1 | OpA mux (EX) | 1 = PC, 0 = rd1 |
| `AluSrc` | 1 | OpB mux (EX) | 1 = imm, 0 = rd2 |
| `AluCtrl` | 4 | `ALU` (EX) | operation select |
| `Branch` | 1 | next-PC mux (EX) | paired with `Jump` |
| `Jump` | 1 | next-PC mux **and** writeback mux | double duty |
| `MemRead` | 1 | nothing yet | memory reads unconditionally |
| `MemWrite` | 1 | `memory.write_ena` (MEM) | store |
| `MemToReg` | 1 | writeback mux (WB) | select load data |

`funct3` bypasses control entirely: decoder feeds `comparator`, `memory` and `load_extend` directly.

### Full decode table

| opcode | type | AluSrcA | AluSrc | AluCtrl | Br | Jmp | MemRd | MemWr | M2R | RegWr |
|---|---|---|---|---|---|---|---|---|---|---|
| `0110011` | R | rd1 | rd2 | `{f7[5],f3}` | 0 | 0 | 0 | 0 | 0 | 1 |
| `0010011` | I-arith | rd1 | imm | `{f7[5],f3}` | 0 | 0 | 0 | 0 | 0 | 1 |
| `0000011` | LOAD | rd1 | imm | ADD | 0 | 0 | 1 | 0 | **1** | 1 |
| `0100011` | STORE | rd1 | imm | ADD | 0 | 0 | 0 | **1** | 0 | 0 |
| `1100011` | BRANCH | **PC** | imm | ADD | **1** | 0 | 0 | 0 | 0 | 0 |
| `1101111` | JAL | **PC** | imm | ADD | 0 | **1** | 0 | 0 | 0 | 1 |
| `1100111` | JALR | rd1 | imm | ADD | **1** | **1** | 0 | 0 | 0 | 1 |
| `0110111` | LUI | rd1 (= x0) | imm | ADD | 0 | 0 | 0 | 0 | 0 | 1 |
| `0010111` | AUIPC | **PC** | imm | ADD | 0 | 0 | 0 | 0 | 0 | 1 |

### `{Branch, Jump}` is the next-PC select

| value | next PC | instructions |
|---|---|---|
| `00` | `PC + 4` | R, I, LUI, AUIPC, load, store |
| `01` | `alu_res` (= `PC + imm`) | JAL |
| `10` | `cmp ? alu_res : PC + 4` | B-type |
| `11` | `alu_res & ~1` | JALR |

### Writeback select

`MemToReg` selects load data, else `Jump` selects `PC + 4`, else the ALU result.

---

## 4. Decoder: live fields per format

Blank means deliberately zeroed.

| format | rd | rs1 | rs2 | funct3 | funct7 | imm |
|---|---|---|---|---|---|---|
| **R** | yes | yes | yes | yes | yes | none |
| **I** | yes | yes | — | yes | shifts only | `[31:20]` sign-extended |
| **S** | — | yes | yes | yes | — | `{[31:25], [11:7]}` |
| **B** | — | yes | yes | yes | — | `{[31], [7], [30:25], [11:8], 0}` |
| **U** | yes | — | — | — | — | `{[31:12], 12 zeros}` |
| **J** | yes | — | — | — | — | `{[31], [19:12], [20], [30:21], 0}` |

The blanks are the load-bearing part. See section 2.

---

## 5. Per-format walkthrough

### R-type, e.g. `add x3, x1, x2`

    IF   fetch, compute PC+4
    ID   decode rs1/rs2/rd/funct3/funct7; regfile reads rd1, rd2;
         control emits AluCtrl = {funct7[5], funct3}
    EX   OpA = rd1, OpB = rd2, ALU produces alu_res
    MEM  pass through
    WB   rd <= alu_res

### I-arith, e.g. `addi x1, x0, -1`

Identical to R-type except `OpB = imm`. The decoder zeroes `funct7` unless the instruction
is a shift, which is what stops a negative immediate from selecting SUB.

### LOAD, e.g. `lb x5, 3(x1)`

    EX   OpA = rd1, OpB = imm, ADD gives the address
    MEM  memory returns the whole word at addr[9:2];
         load_extend picks lane addr[1:0] and extends per funct3
    WB   rd <= load_data          (MemToReg = 1)

### STORE, e.g. `sb x5, 3(x1)`

    EX   address = rd1 + imm; rd2 carries the store data forward
    MEM  memory writes only the addressed lane
         (funct3 picks the width, addr[1:0] picks the lane)
    WB   nothing, RegWrite = 0

### B-type, e.g. `beq x1, x2, offset`

    EX   ALU computes PC + imm (AluSrcA = 1) = branch target
         comparator independently evaluates rd1 vs rd2 per funct3, producing cmp
         {Branch,Jump} = 10, so next_pc = cmp ? alu_res : PC+4
    WB   nothing

The comparator takes **raw rd1/rd2**, not the ALU operand muxes. On a branch those muxes
are carrying PC and imm.

### U-type, `lui` and `auipc`

    LUI    AluSrcA = 0, so OpA = rd1 = x0 = 0, ALU computes 0 + imm
    AUIPC  AluSrcA = 1, so OpA = PC,           ALU computes PC + imm
    WB     rd <= alu_res  for both

One bit apart.

### J-type, `jal x1, offset`

    EX   ALU computes PC + imm = target; {Branch,Jump} = 01, next_pc = alu_res
    WB   rd <= PC + 4     (Jump selects the link value)

### JALR, `jalr x1, offset(x5)`

    EX   AluSrcA = 0, ALU computes rd1 + imm = target
         {Branch,Jump} = 11, next_pc = alu_res & ~1
    WB   rd <= PC + 4

The mask exists because I-type immediates do not force bit 0 to zero the way J-type and
B-type encodings do.

---

## 6. Pipeline register contents

| register | carries |
|---|---|
| **IF/ID** | `pc, pc_plus4, instr` |
| **ID/EX** | `pc, pc_plus4, rd1, rd2, imm, rs1, rs2, rd, funct3` plus all 9 control signals |
| **EX/MEM** | `alu_res, rd2, pc_plus4, rd, funct3` plus `MemRead, MemWrite, MemToReg, RegWrite, Jump` |
| **MEM/WB** | `alu_res, load_data, pc_plus4, rd` plus `RegWrite, MemToReg, Jump` |

The control bundle shrinks at each boundary. EX consumes `AluCtrl`, `AluSrc`, `AluSrcA`
and `Branch`; MEM consumes `MemWrite` and `funct3`.

`rs1` and `rs2` ride ID/EX with no consumer yet. The forwarding unit needs them in Phase 3,
and retrofitting them later means touching every register again.

### Backward paths

These four wires flow against the pipeline, and they are where all the difficulty lives.

| from | to | why |
|---|---|---|
| WB | ID | register file write |
| EX | IF | branch and jump target to the PC |
| EX/MEM | EX | forwarding (Phase 3) |
| MEM/WB | EX | forwarding (Phase 3) |

---

## 7. Status

**Verified** as single-cycle, tag `v1.0-singlecycle`: all 37 base integer instructions,
43 of 43 assertions, at padding levels 0, 1, 2 and 4.

**In progress**, 5-stage pipeline:

- [x] boundary spec
- [ ] four pipeline registers
- [ ] `PAD=4` green, plumbing only
- [ ] branch flush
- [ ] forwarding, EX/MEM to EX and MEM/WB to EX, EX taking priority
- [ ] load-use stall, freeze PC and IF/ID, bubble ID/EX
- [ ] `PAD=0` green

**Not implemented:** `ECALL` and `EBREAK`, which need CSRs and trap handling.
`FENCE` decodes as a no-op, which is spec-correct on a single-core in-order machine
with no caches.
