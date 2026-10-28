# DOOMED RV32I Datapath

A 32-bit RISC-V processor written from scratch in SystemVerilog, built toward running DOOM. This README documents how the 5-stage pipelined core is wired. Every wire name, instance name, width and control value below comes from [`rtl/`](rtl/).

| Drawing | Top module | ISA | Timing | Rev · date |
|---|---|---|---|---|
| DOOMED RV32I Datapath | `top_wire` in [`rtl/top.sv`](rtl/top.sv), 11 instances | RV32I, 37 instructions | 5-stage pipeline: IF ID EX MEM WB | v2.0-pipelined, RTL at `e0307c3`, 2026-09-10 |

**Status:** all 37 RV32I base integer instructions pass the directed test, 46/46 assertions at every padding level.
**Next:** toolchain, `riscv-tests`, memory map and framebuffer, then DOOM.

```
rtl/       12 SystemVerilog modules: the processor
verif/     self-checking test harness; verif/metrics/ measures CPI, Fmax and area
results/   archived pass/fail tables, CPI and synthesis results
docs/      architecture reference, test plan, status and roadmap, metrics
```

[Schematic](#schematic) · [Instruction paths](#instruction-paths) · [ISA](#01-the-isa) · [Design decisions](#02-design-decisions) · [vs single-cycle](#03-against-the-single-cycle-core) · [Reference tables](#04-reference-tables) · [Glue logic](#05-glue-logic) · [Open items](#06-open-items) · [Running it](#running-it) · [Roadmap](#roadmap)

---

## Schematic

![top_wire five-stage datapath: PC, instruction ROM, decoder, register file, forwarding and operand muxes, ALU, comparator, data memory, load extend and write-back mux, with control on top and next-PC logic below](docs/datapath.svg)

**Fig. 1** `top_wire` is a classic five-stage pipeline. Control decodes once in ID, rides the pipeline registers, and every branch or jump resolves in EX.

Data flows left to right. Control, hazard and forwarding units sit in the top band. Next-PC and flush logic sit in the bottom band. Write-back (`wb_data`, `wb_rd`, `wb_RegWrite`) and `next_pc` loop back on their own lanes.

| Drawn as | Means |
|---|---|
| solid ink with an arrow | data or address wire |
| dashed blue | control signal, labelled where it lands |
| dotted grey | wired, but nothing uses it yet (the debug outputs, tied to 0) |
| filled dot | junction. A crossing without a dot is not a connection |
| small triangle on a bottom edge | clocked element |
| flag | net label. It joins the wire with the same name |
| trapezoid | mux. Small numbers mark the inputs |

## Instruction paths

The wires each instruction class uses in Fig. 1. Examples are words from the test program in [`rtl/ROM.sv`](rtl/ROM.sv). Paths assume no hazard in flight, so `stall = 0` and `fwd_a = fwd_b = 00`.

| Class | Example | Encoding | Path | What sets it apart |
|---|---|---|---|---|
| R-type | `add x3, x1, x2` | `0x002081B3` | `ex_rd1` and `ex_rd2` through both forwarding muxes into the ALU. The result rides EX/MEM and MEM/WB and returns as `wb_data`. | AluSrcA 0, AluSrc 0. AluCtrl = `{funct7[5], funct3}`: `0000` ADD, `1000` SUB, `1101` SRA, `0010` SLT |
| I-arith | `addi x1, x0, 5` | `0x00500093` | `ex_rd1` on operand A, `ex_imm` on operand B, then write-back of `wb_alu_res`. | AluSrc 1. The decoder zeroes funct7 except for shifts, so `srai x14, x11, 1` (`0x4015D713`) still gets `1101` |
| Load | `lw x21, 4(x0)` | `0x00402A83` | rs1 + imm forms `mem_alu_res`. Memory returns the word at `addr[9:2]`, `load_extend` picks the lane, and `wb_load_data` goes back to `rd`. | MemRead 1 arms the load-use check in `hz`. MemToReg 1. `lbu x25, 8(x0)` (`0x00804C83`) zero-fills one byte |
| Store | `sw x18, 0(x0)` | `0x01202023` | rs1 + imm is the address. `fwd_rd2` rides EX/MEM as `mem_rd2` to the memory's `dat` port. | MemWrite 1, RegWrite 0. `sb x20, 4(x0)` (`0x01400223`) writes one lane picked by `addr[1:0]` |
| Branch | `beq x1, x1, 8` | `0x00108463` | The ALU computes `ex_pc + imm` while the comparator checks `fwd_rd1` against `fwd_rd2`. `next_pc = ex_cmp ? ex_alu_res : if_pc_plus4`. | AluSrcA 1, AluSrc 1, `{Branch,Jump}` = 10, `flush = ex_cmp`. `bltu x1, x11, 8` (`0x00B0E463`) compares unsigned |
| JAL | `jal x29, 8` | `0x00800EEF` | The ALU computes `ex_pc + imm` and it goes straight to the PC. `pc_plus4` rides to WB as the link value. | AluSrcA 1, `{Branch,Jump}` = 01, flush 1, Jump selects `wb_pc_plus4` |
| JALR | `jalr x30, 12(x5)` | `0x00C28F67` | The ALU computes rs1 + imm. `& ~32'd1` clears bit 0 on the way to the PC. | `{Branch,Jump}` = 11, flush 1, Jump selects `wb_pc_plus4` |
| LUI | `lui x16, 0xABCDE` | `0xABCDE837` | rs1 is `x0`, so the ALU computes `0 + imm` on the normal path. | AluSrcA 0, AluSrc 1 |
| AUIPC | `auipc x17, 0x1` | `0x00001897` | `ex_pc` on operand A, `ex_imm` on operand B. | AluSrcA 1, the only bit that differs from LUI |

---

## 01 The ISA

RV32I base integer set. Every example encoding below is a word from the test program in [`rtl/ROM.sv`](rtl/ROM.sv).

| Property | Value |
|---|---|
| Word size | 32 bit |
| Instructions | 37: R 10, I 15, S 3, B 6, U 2, J 1 |
| Formats | 6: R I S B U J |
| Registers | `x0` to `x31`. `x0` reads 0 and drops writes |
| Instruction ROM | 16,384 words, indexed by `PC[15:2]` |
| Data memory | 256 words (1 KB), indexed by `addr[9:2]` |
| Byte lanes | little-endian, lane = `addr[1:0]` |
| Control word | 9 signals, 12 bits (`AluCtrl` is 4 of them) |
| ALU code | `{funct7[5], funct3}`, 10 operations |
| Not decoded | `ECALL`, `EBREAK`. No CSRs, so they act as no-ops |
| `FENCE` | no-op, all controls 0 |
| Directed test | 46 / 46 at PAD 0, 1, 2 and 4 |

### Formats

```
     31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
R   |       funct7       |     rs2      |     rs1      | funct3 |      rd      |       opcode       |
I   |             imm[11:0]             |     rs1      | funct3 |      rd      |       opcode       |
S   |     imm[11:5]      |     rs2      |     rs1      | funct3 |   imm[4:0]   |       opcode       |
B   |12|    imm[10:5]    |     rs2      |     rs1      | funct3 |  imm[4:1] |11|       opcode       |
U   |                         imm[31:12]                        |      rd      |       opcode       |
J   |20|          imm[10:1]          |11|       imm[19:12]      |      rd      |       opcode       |
```

In B and J, the 1-bit cells are imm[12], imm[11] and imm[20].

### Field to wire to destination

| Field | Bits | Decoder port → wire | Destinations |
|---|---|---|---|
| opcode | `[6:0]` | `opcode` → `id_opcode` | `pnp.Opcode` |
| rd | `[11:7]` | `rd` → `id_rd` | `ex_rd` → `mem_rd` → `wb_rd` → `npn.rd`. Also `hz` (`ex_rd`) and `fwd` (`mem_rd`, `wb_rd`) |
| funct3 | `[14:12]` | `funct3` → `id_funct3` | `pnp`. `ex_funct3` → `mph`. `mem_funct3` → `meme`, `ext` |
| rs1 | `[19:15]` | `rs1` → `id_rs1` | `npn.rs1`, `hz`. `ex_rs1` → `fwd` |
| rs2 | `[24:20]` | `rs2` → `id_rs2` | `npn.rs2`, `hz`. `ex_rs2` → `fwd` |
| funct7 | `[31:25]` | `funct7` → `id_funct7` | `pnp`, where `funct7[5]` becomes `AluCtrl[3]`. Zeroed except for R-type and I-type shifts |
| imm | by format | `imm` → `id_imm` | `ex_imm` → operand B mux, input 1 |

### Instructions

| Mnemonic | Fmt | Opcode | funct3 | funct7 | RTL | Example | Encoding |
|---|---|---|---|---|---|---|---|
| **ADD** | R | `0110011` | `000` | `0000000` | `rd = rs1 + rs2` | `add x3, x1, x2` | `0x002081B3` |
| **SUB** | R | `0110011` | `000` | `0100000` | `rd = rs1 - rs2` | `sub x4, x1, x2` | `0x40208233` |
| **SLL** | R | `0110011` | `001` | `0000000` | `rd = rs1 << rs2[4:0]` | `sll x8, x1, x2` | `0x00209433` |
| **SLT** | R | `0110011` | `010` | `0000000` | `rd = (rs1 <s rs2) ? 1 : 0` | `slt x10, x2, x1` | `0x00112533` |
| **SLTU** | R | `0110011` | `011` | `0000000` | `rd = (rs1 <u rs2) ? 1 : 0` | `sltu x12, x11, x1` | `0x0015B633` |
| **XOR** | R | `0110011` | `100` | `0000000` | `rd = rs1 ^ rs2` | `xor x7, x1, x2` | `0x0020C3B3` |
| **SRL** | R | `0110011` | `101` | `0000000` | `rd = rs1 >> rs2[4:0]` | `srl x9, x1, x2` | `0x0020D4B3` |
| **SRA** | R | `0110011` | `101` | `0100000` | `rd = rs1 >>> rs2[4:0]` | `sra x20, x11, x2` | `0x4025DA33` |
| **OR** | R | `0110011` | `110` | `0000000` | `rd = rs1 \| rs2` | `or x6, x1, x2` | `0x0020E333` |
| **AND** | R | `0110011` | `111` | `0000000` | `rd = rs1 & rs2` | `and x5, x1, x2` | `0x0020F2B3` |
| **ADDI** | I | `0010011` | `000` | · | `rd = rs1 + imm` | `addi x1, x0, 5` | `0x00500093` |
| **SLTI** | I | `0010011` | `010` | · | `rd = (rs1 <s imm) ? 1 : 0` | `slti x20, x11, 0` | `0x0005AA13` |
| **SLTIU** | I | `0010011` | `011` | · | `rd = (rs1 <u imm) ? 1 : 0` | `sltiu x20, x11, 5` | `0x0055BA13` |
| **XORI** | I | `0010011` | `100` | · | `rd = rs1 ^ imm` | `xori x20, x1, -1` | `0xFFF0CA13` |
| **ORI** | I | `0010011` | `110` | · | `rd = rs1 \| imm` | `ori x20, x1, 8` | `0x0080EA13` |
| **ANDI** | I | `0010011` | `111` | · | `rd = rs1 & imm` | `andi x20, x11, 0xF0` | `0x0F05FA13` |
| **SLLI** | I | `0010011` | `001` | `0000000` | `rd = rs1 << shamt` | `slli x20, x1, 4` | `0x00409A13` |
| **SRLI** | I | `0010011` | `101` | `0000000` | `rd = rs1 >> shamt` | `srli x15, x11, 28` | `0x01C5D793` |
| **SRAI** | I | `0010011` | `101` | `0100000` | `rd = rs1 >>> shamt` | `srai x14, x11, 1` | `0x4015D713` |
| **LB** | I | `0000011` | `000` | · | `rd = sext(M[rs1+imm][7:0])` | `lb x22, 4(x0)` | `0x00400B03` |
| **LH** | I | `0000011` | `001` | · | `rd = sext(M[rs1+imm][15:0])` | `lh x26, 14(x0)` | `0x00E01D03` |
| **LW** | I | `0000011` | `010` | · | `rd = M[rs1+imm]` | `lw x21, 4(x0)` | `0x00402A83` |
| **LBU** | I | `0000011` | `100` | · | `rd = zext(M[rs1+imm][7:0])` | `lbu x25, 8(x0)` | `0x00804C83` |
| **LHU** | I | `0000011` | `101` | · | `rd = zext(M[rs1+imm][15:0])` | `lhu x27, 14(x0)` | `0x00E05D83` |
| **JALR** | I | `1100111` | `000` | · | `rd = pc+4; pc = (rs1+imm) & ~1` | `jalr x30, 12(x5)` | `0x00C28F67` |
| **SB** | S | `0100011` | `000` | · | `M[rs1+imm][7:0] = rs2[7:0]` | `sb x20, 4(x0)` | `0x01400223` |
| **SH** | S | `0100011` | `001` | · | `M[rs1+imm][15:0] = rs2[15:0]` | `sh x11, 14(x0)` | `0x00B01723` |
| **SW** | S | `0100011` | `010` | · | `M[rs1+imm] = rs2` | `sw x18, 0(x0)` | `0x01202023` |
| **BEQ** | B | `1100011` | `000` | · | `if (rs1 == rs2) pc += imm` | `beq x1, x1, 8` | `0x00108463` |
| **BNE** | B | `1100011` | `001` | · | `if (rs1 != rs2) pc += imm` | `bne x1, x2, 8` | `0x00209463` |
| **BLT** | B | `1100011` | `100` | · | `if (rs1 <s rs2) pc += imm` | `blt x11, x1, 8` | `0x0015C463` |
| **BGE** | B | `1100011` | `101` | · | `if (rs1 >=s rs2) pc += imm` | `bge x1, x2, 8` | `0x0020D463` |
| **BLTU** | B | `1100011` | `110` | · | `if (rs1 <u rs2) pc += imm` | `bltu x1, x11, 8` | `0x00B0E463` |
| **BGEU** | B | `1100011` | `111` | · | `if (rs1 >=u rs2) pc += imm` | `bgeu x11, x1, 8` | `0x0015F463` |
| **LUI** | U | `0110111` | · | · | `rd = imm << 12` | `lui x16, 0xABCDE` | `0xABCDE837` |
| **AUIPC** | U | `0010111` | · | · | `rd = pc + (imm << 12)` | `auipc x17, 0x1` | `0x00001897` |
| **JAL** | J | `1101111` | · | · | `rd = pc+4; pc += imm` | `jal x29, 8` | `0x00800EEF` |
| FENCE | I | `0001111` | `000` | · | no-op | all controls 0 | · |
| ECALL | I | `1110011` | `000` | · | not implemented | decodes as a no-op | `0x00000073` |
| EBREAK | I | `1110011` | `000` | · | not implemented | decodes as a no-op | `0x00100073` |

---

## 02 Design decisions

Why the wiring looks the way it does, and what each choice costs.

### ISA

**The ALU code is two instruction fields glued together.** `AluCtrl = {funct7[5], funct3}`, so R-type and I-type arithmetic share one decode with no lookup table. `funct7[5]` is the bit that splits ADD from SUB and SRL from SRA.

*Watch out:* `funct7[0]` is ignored. MUL (`funct7 = 0000001`, `funct3 = 000`) would decode as ADD, so the M extension needs a wider code.

**The decoder zeroes every field a format does not have.** `rs1` stays `x0` for U and J, `funct7` stays 0 for non-shift I-type, and `rd`, `rs1` and `rs2` are 0 where unused. This keeps `hz` and `fwd` from matching a register the instruction never named.

*Trade-off:* correctness leans on decoder defaults. Any new opcode has to follow the same rule.

**LUI costs no hardware.** With `rs1 = x0`, the ALU computes `0 + imm` through the normal path. AUIPC sets `AluSrcA = 1` to add the PC instead, and that is the only control bit that differs between them.

*Trade-off:* LUI depends on `x0` reading as zero through the forwarding mux. It holds because `fwd` ignores `rd = 0`.

**Negative immediates cannot select SUB.** `addi x11, x0, -1` has `instruction[30]` set. Without the funct7 zeroing it would decode as AluCtrl `1000`. The directed test covers this with SLTI and XORI on negative immediates.

*Trade-off:* shifts keep funct7 so SRAI works. The rule is an exception list inside the decoder.

**FENCE, ECALL and EBREAK pass through as no-ops.** `control` leaves all nine outputs at 0 for opcodes `0001111` and `1110011`. FENCE is correct as a no-op on an in-order core with no caches.

*Room to grow:* EBREAK is the planned halt for `riscv-tests`. `halt` is tied to 0 today.

### Datapath

**One ALU computes every PC-relative target.** JAL, branches and AUIPC set `AluSrcA = 1` to put `ex_pc` on operand A. The branch condition comes from the separate comparator, so the ALU is free on branches. Only PC + 4 has its own adder.

*Trade-off:* branches resolve in EX. Each taken branch or jump flushes two instructions, which is 25–35% of cycles in ordinary loops.

**`{Branch, Jump}` is the next-PC select, and flush copies it.** Two existing control bits pick among four sources. The flush block uses the same case on the same bits, so the redirect and the squash cannot drift apart.

*Trade-off:* the redirect loop runs forwarding, compare and next-PC in one cycle. That loop sets Fmax at 61.8–65.9 MHz on ECP5-85F speed grade 6.

**Jump doubles as the write-back select.** `Jump` is high for exactly JAL and JALR, the two instructions whose `rd` gets PC + 4. The write-back mux is a priority chain on `MemToReg`, then `Jump`.

*Trade-off:* a fourth write-back source, such as a CSR read, needs a new control bit.

**Control rides the pipeline registers.** `control` decodes once in ID. ID/EX carries all 12 bits, EX/MEM carries 5 and MEM/WB carries 3. `control.sv` did not change when the core was pipelined.

*Watch out:* one of the 5 EX/MEM bits, `mem_MemRead`, is never loaded. See [open items](#06-open-items).

**Forwarding takes `wb_data`, not `wb_alu_res`.** The MEM/WB path forwards the write-back mux output, so load data and link values reach EX at distance 2. EX/MEM is checked first because it holds the newer write.

*Trade-off:* the forwarding compare heads every measured critical path.

**The register file is write-first.** A read of the register being written in the same cycle returns `wd`. That covers RAW at distance 3 without a third bypass path.

*Trade-off:* the reset loop on 32 registers costs about 75% of the core's LUTs.

**The load-use interlock is one stall cycle.** `hz` stalls when the load in EX writes a register the ID instruction reads. PC and IF/ID hold, ID/EX takes a bubble, and the value arrives by MEM/WB forwarding.

*Room to grow:* a store needs rs2 only in MEM. Forwarding load data there would remove the stall, 11% of cycles in `memcpy_naive`.

**Load extension sits outside the memory.** Sign and zero extension are instruction semantics, so `ext` lives on the CPU side. A future bus device returns a raw word and gets the same behaviour.

*Watch out:* both memories read asynchronously, which rules out block RAM. DOOM-sized memory needs a synchronous read and one more cycle in MEM.

---

## 03 Against the single-cycle core

`v1.0-singlecycle` is the verified single-cycle `top.sv` on `main`. `v2.0-pipelined` is this branch.

| | v1.0-singlecycle | v2.0-pipelined |
|---|---|---|
| Tag | `c4ceb59`, 2026-08-11 | `0fae41f`, 2026-09-08 |
| Stages | 1 | 5: IF, ID, EX, MEM, WB |
| Instances | 8: `ad dc tnt pnp npn mph tsmc meme` | 11: adds `ext`, `hz`, `fwd` |
| Net naming | `*_loc` | `if_` `id_` `ex_` `mem_` `wb_` |
| `control.sv` | 9 signals | unchanged |
| PC enable | `pc_en_loc = 1'b1` | `~stall` |
| Next PC | nested ternary on `Jump_loc`, `Branch_loc` with `PC_loc + 4` | case on `{ex_Branch, ex_Jump}` with `if_pc_plus4`; flush mirrors it |
| Comparator inputs | `rd1_loc`, `rd2_loc` | `fwd_rd1`, `fwd_rd2` |
| Load extension | inline in `top.sv` (`b`, `h`, `load_data`) | `load_extend` module, instance `ext` |
| Register read | plain array read | write-first bypass |
| Hazard logic | none needed | 2 forwarding paths, load-use stall, branch flush |
| Debug ports | driven from `PC_loc`, `IR_loc`, `RegWrite_loc`, `rd_loc`, `wd_loc` | tied to 0 |
| CPI | 1 by construction | 1.000–2.178 over 9 workloads |
| Fmax, ECP5-85F-6 | not measured | 61.8–65.9 MHz post-route |
| Area, ECP5 | not measured | 3,931 LUT4 + 1,549 FF |
| Directed test | 43 / 43 | 46 / 46 at PAD 0, 1, 2, 4 |

Measurement method and the what-if builds: [`docs/METRICS.md`](docs/METRICS.md).

---

## 04 Reference tables

### Control truth table ([`control.sv`](rtl/control.sv))

| Class | Opcode | RegWrite | AluSrc | AluSrcA | MemRead | MemWrite | MemToReg | Branch | Jump | AluCtrl |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|
| R-type | `0110011` | **1** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `{f7[5],f3}` |
| I-arith | `0010011` | **1** | **1** | 0 | 0 | 0 | 0 | 0 | 0 | `{f7[5],f3}` |
| Load | `0000011` | **1** | **1** | 0 | **1** | 0 | **1** | 0 | 0 | `0000` |
| Store | `0100011` | 0 | **1** | 0 | 0 | **1** | 0 | 0 | 0 | `0000` |
| Branch | `1100011` | 0 | **1** | **1** | 0 | 0 | 0 | **1** | 0 | `0000` |
| JAL | `1101111` | **1** | **1** | **1** | 0 | 0 | 0 | 0 | **1** | `0000` |
| JALR | `1100111` | **1** | **1** | 0 | 0 | 0 | 0 | **1** | **1** | `0000` |
| LUI | `0110111` | **1** | **1** | 0 | 0 | 0 | 0 | 0 | 0 | `0000` |
| AUIPC | `0010111` | **1** | **1** | **1** | 0 | 0 | 0 | 0 | 0 | `0000` |
| FENCE | `0001111` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `1111` |
| ECALL, EBREAK | `1110011` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `1111` |

### Next-PC select ([`top.sv:128`](rtl/top.sv#L128))

| `{ex_Branch, ex_Jump}` | `next_pc` | `flush` | Used by |
|---|---|---|---|
| `00` | `if_pc_plus4` | 0 | everything else |
| `01` | `ex_alu_res` | **1** | JAL |
| `10` | `ex_cmp ? ex_alu_res : if_pc_plus4` | `ex_cmp` | B-type |
| `11` | `ex_alu_res & ~32'd1` | **1** | JALR |

### Write-back select ([`top.sv:185`](rtl/top.sv#L185))

| `wb_MemToReg` | `wb_Jump` | `wb_data` | Used by |
|:-:|:-:|---|---|
| **1** | x | `wb_load_data` | loads |
| 0 | **1** | `wb_pc_plus4` | JAL, JALR |
| 0 | 0 | `wb_alu_res` | R, I-arith, LUI, AUIPC |

Stores and branches also land on `wb_alu_res`, but `wb_RegWrite = 0` drops the write.

### ALU operations ([`ALU.sv`](rtl/ALU.sv))

| AluCtrl | Op | Res | Used by |
|---|---|---|---|
| `0000` | ADD | `OpA + OpB` | ADD, ADDI, loads, stores, branch and jump targets, LUI, AUIPC |
| `1000` | SUB | `OpA - OpB` | SUB |
| `0001` | SLL | `OpA << OpB[4:0]` | SLL, SLLI |
| `0010` | SLT | `$signed(OpA) < $signed(OpB)` | SLT, SLTI |
| `0011` | SLTU | `OpA < OpB` | SLTU, SLTIU |
| `0100` | XOR | `OpA ^ OpB` | XOR, XORI |
| `0101` | SRL | `OpA >> OpB[4:0]` | SRL, SRLI |
| `1101` | SRA | `$signed(OpA) >>> OpB[4:0]` | SRA, SRAI |
| `0110` | OR | `OpA \| OpB` | OR, ORI |
| `0111` | AND | `OpA & OpB` | AND, ANDI |
| other | default | `32'b0` | `1111` is control's reset value: FENCE, ECALL, EBREAK, unknown opcodes |

### Hazard selects ([`forward.sv`](rtl/forward.sv), [`hazard.sv`](rtl/hazard.sv))

| Signal | Value | Source | When |
|---|---|---|---|
| `fwd_a` / `fwd_b` | `00` | `ex_rd1` / `ex_rd2` | no match |
| `fwd_a` / `fwd_b` | `01` | `mem_alu_res` | `mem_RegWrite && mem_rd != 0 && mem_rd == ex_rs1` (or `ex_rs2`) |
| `fwd_a` / `fwd_b` | `10` | `wb_data` | else `wb_RegWrite && wb_rd != 0 && wb_rd == ex_rs1` (or `ex_rs2`) |
| `stall` | `1` | `hz` | `ex_MemRead && ex_rd != 0 && (ex_rd == id_rs1 \|\| ex_rd == id_rs2)` |

### Pipeline registers ([`top.sv:79-182`](rtl/top.sv#L79-L182))

| Register | Bits | Carries | Clears on | Holds on |
|---|---|---|---|---|
| IF/ID | 96 | `id_pc`, `id_pc_plus4`, `id_instr` | `rst`, `flush` | `stall` |
| ID/EX | 190 | `ex_pc`, `ex_pc_plus4`, `ex_rd1`, `ex_rd2`, `ex_imm`, `ex_rs1`, `ex_rs2`, `ex_rd`, `ex_funct3`, `ex_AluCtrl`, 8 one-bit controls | `rst`, `flush`, `stall` | never |
| EX/MEM | 109 | `mem_alu_res`, `mem_rd2`, `mem_pc_plus4`, `mem_rd`, `mem_funct3`, `mem_RegWrite`, `mem_MemRead`, `mem_MemWrite`, `mem_MemToReg`, `mem_Jump` | `rst` | never |
| MEM/WB | 104 | `wb_alu_res`, `wb_load_data`, `wb_pc_plus4`, `wb_rd`, `wb_RegWrite`, `wb_MemToReg`, `wb_Jump` | `rst` | never |

### Modules

| Instance | Module | File | Role | Ports → top-level wires |
|---|---|---|---|---|
| `ad` | `PrgCo` | [`rtl/PC.sv`](rtl/PC.sv) | program counter, holds when `pc_en = 0` | `pc_en ← ~stall`, `next_pc ← next_pc`, `pc → if_pc` |
| `dc` | `ROME` | [`rtl/ROM.sv`](rtl/ROM.sv) | instruction ROM, async read | `PC ← if_pc`, `IR → if_instr` |
| `tnt` | `decoder` | [`rtl/decoder.sv`](rtl/decoder.sv) | field slicing, immediate assembly | `instruction ← id_instr`; `opcode`, `funct3`, `funct7`, `rs1`, `rs2`, `rd`, `imm → id_*` |
| `pnp` | `control` | [`rtl/control.sv`](rtl/control.sv) | opcode to 9 control signals | `Opcode`, `funct3`, `funct7 ← id_*`; `RegWrite … MemToReg → id_*` |
| `npn` | `registers` | [`rtl/registers.sv`](rtl/registers.sv) | 32 × 32 register file, write-first | `rs1`, `rs2 ← id_rs*`; `rd ← wb_rd`; `wd ← wb_data`; `we ← wb_RegWrite`; `rd1`, `rd2 → id_rd*` |
| `mph` | `comparator` | [`rtl/cmp.sv`](rtl/cmp.sv) | branch condition per funct3 | `OpA ← fwd_rd1`, `OpB ← fwd_rd2`, `funct3 ← ex_funct3`, `cmp → ex_cmp` |
| `tsmc` | `ALU` | [`rtl/ALU.sv`](rtl/ALU.sv) | 10 operations | `OpA ← ex_opA`, `OpB ← ex_opB`, `ALUCtrl ← ex_AluCtrl`, `Res → ex_alu_res` |
| `meme` | `memory` | [`rtl/data_mem.sv`](rtl/data_mem.sv) | 256 × 32 data RAM, byte/half/word writes | `addr ← mem_alu_res`, `dat ← mem_rd2`, `funct3 ← mem_funct3`, `write_ena ← mem_MemWrite`, `mem_dat → mem_dat` |
| `ext` | `load_extend` | [`rtl/load_extend.sv`](rtl/load_extend.sv) | lane select, sign or zero extend | `mem_dat ← mem_dat`, `addr_lo ← mem_alu_res[1:0]`, `funct3 ← mem_funct3`, `load_data → mem_load_data` |
| `hz` | `hazard` | [`rtl/hazard.sv`](rtl/hazard.sv) | load-use interlock | `ex_MemRead`, `ex_rd`, `id_rs1`, `id_rs2 → stall` |
| `fwd` | `forward` | [`rtl/forward.sv`](rtl/forward.sv) | operand bypass select | `ex_rs1`, `ex_rs2`, `mem_rd`, `wb_rd`, `mem_RegWrite`, `wb_RegWrite → fwd_a`, `fwd_b` |

---

## 05 Glue logic

The `assign` statements in `top_wire`, copied from [`rtl/top.sv`](rtl/top.sv) lines 77, 124–125, 185 and 190–195:

```systemverilog
    assign if_pc_plus4 = if_pc + 32'd4;
        assign ex_opA=ex_AluSrcA?ex_pc:fwd_rd1;
        assign ex_opB=ex_AluSrc?ex_imm:fwd_rd2;
        assign wb_data=(wb_MemToReg)?wb_load_data:wb_Jump?wb_pc_plus4:wb_alu_res;
    assign dbg_pc      = 0;
    assign dbg_instr   = 0;
    assign dbg_reg_we  = 0;
    assign dbg_rd      = 0;
    assign dbg_wb_data = 0;
    assign halt        = 0;
```

The forwarding muxes, next-PC mux and flush are `always_comb` blocks, lines 111–152:

```systemverilog
        always_comb begin
            case(fwd_a)
                2'b01:   fwd_rd1 = mem_alu_res;   // from EX/MEM
                2'b10:   fwd_rd1 = wb_data;       // from MEM/WB (mux output, not wb_alu_res)
                default: fwd_rd1 = ex_rd1;
            endcase
            case(fwd_b)
                2'b01:   fwd_rd2 = mem_alu_res;
                2'b10:   fwd_rd2 = wb_data;
                default: fwd_rd2 = ex_rd2;
            endcase
        end

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

        always_comb begin
            unique case({ex_Branch,ex_Jump})
                2'b01:
                    flush=1'b1;
                2'b10:
                    flush=ex_cmp;
                2'b11:
                    flush=1'b1;
                default:
                    flush=1'b0;        
            endcase
        end
```

---

## 06 Open items

Things in the code that look unfinished or wrong, most urgent first.

1. **EX/MEM never loads `mem_MemRead`.** `bug` [`top.sv:156-169`](rtl/top.sv#L156-L169) declares and resets `mem_MemRead` but leaves it out of the else branch, so it stays 0. Nothing reads it yet. A bus read strobe or a MEM-stage load forward built on it would silently never fire.
2. **The debug ports are tied to 0.** `bug` [`top.sv:190-195`](rtl/top.sv#L190-L195). `tb_check.sv` prints `FINAL PC` from `dbg_pc`, so it always shows `00000000`. `tb_wave.sv` and `tb_basic.sv` log commits only when `dbg_reg_we` is 1, so the pipelined build logs nothing. Driving them from `wb_RegWrite`, `wb_rd` and `wb_data` would restore the commit log.
3. **ECALL and EBREAK run as no-ops, and `halt` is 0.** `gap` [`control.sv:50-52`](rtl/control.sv#L50-L52) leaves every output at 0 for opcode `1110011`. `riscv-tests` needs a clean stop, and [`STATUS.md`](docs/STATUS.md) plans EBREAK as the halt.
4. **Misaligned stores are dropped without a trace.** `gap` [`data_mem.sv:20-29`](rtl/data_mem.sv#L20-L29) skips SH with `addr[0] = 1` and SW with `addr[1:0] != 00`. There is no trap. Addresses past 1 KB wrap through `addr[9:2]`, and fetches past 64 KB wrap through `PC[15:2]`.
5. **MUL would decode as ADD.** `gap` `AluCtrl` only sees `funct7[5]`. The M extension, needed for DOOM, uses `funct7 = 0000001`, so `control` has to look at `funct7[0]` before MUL and DIV land.
6. **Stores stall on a load they do not need yet.** `perf` [`hazard.sv:18`](rtl/hazard.sv#L18) compares `id_rs2` for stores, though store data is read in MEM. This costs 11% of cycles on `memcpy_naive`.
7. **Flush and stall clear whole registers.** `perf` [`top.sv:80`](rtl/top.sv#L80) and [`top.sv:93`](rtl/top.sv#L93) clear every bit of IF/ID and ID/EX, about 286 flip-flops of fanout. Clearing only the control bits brings it to 38 and recovers the Fmax lost when the register-file reset goes.
8. **The docs describe the single-cycle wiring in places.** `docs` [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) §3 says `MemRead` has no consumer; it now feeds `hz` as `ex_MemRead`. §6 says `rs1` and `rs2` ride ID/EX with no consumer; `fwd` uses them. §1 says `pc_en` is reserved; it carries `~stall`.
9. **A stale comment in `control.sv`.** `docs` [`control.sv:98-99`](rtl/control.sv#L98-L99) describes the `taken = Branch & cmp` bug. `top.sv` already avoids it with the case on `{ex_Branch, ex_Jump}`.

---

## Running it

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) and Python 3.

**Full verification:**

```sh
cd verif && sh run.sh
```

```
checked 46 values, 0 failures
```

`PAD=N sh run.sh` inserts N `nop`s after every instruction. A correct pipeline passes at every level, which turns padding into a bisector for hazard bugs. See [`results/README.md`](results/README.md).

**Waveform demo** (30-instruction program):

```sh
cd verif && sh run_wave.sh
```

Writes `verif/wave.vcd`. Open it in GTKWave, Surfer or VaporView. Signals worth watching, under `dut`:

| Group | Signals |
|---|---|
| flow | `if_pc`, `id_instr`, `ex_pc` |
| pipeline control | `stall`, `flush` |
| forwarding | `fwd_a`, `fwd_b`, and `ex_rd1` next to `fwd_rd1` |
| datapath | `ex_alu_res`, `wb_data` |

| Harness file | Purpose |
|---|---|
| `verif/asm.py` | RV32I assembler with encoders for all six formats |
| `verif/gen_test.py` | builds the directed test program and its expected register and memory state |
| `verif/gen_demo.py` | builds the short demo program for waveform viewing |
| `verif/tb_check.sv` | runs to completion and dumps all registers and memory |
| `verif/tb_wave.sv` | same, plus VCD output |
| `verif/check.py` | diffs simulator state against expectations |

**Metrics:** CPI, Fmax, critical path and area, with the what-if builds, in [`docs/METRICS.md`](docs/METRICS.md). Reproduce them with the scripts in [`verif/metrics/`](verif/metrics/).

More docs: [architecture](docs/ARCHITECTURE.md) · [test plan](docs/TESTPLAN.md) · [status and roadmap](docs/STATUS.md) · [build narrative](docs/NARRATIVE.md)

## Roadmap

- [x] Single-cycle RV32I core
- [x] Sub-word loads and stores with sign and zero extension
- [x] Self-checking test harness, 46/46
- [x] 5-stage pipeline: forwarding, load-use interlock, branch flush
- [ ] Toolchain: `riscv-none-elf-gcc`, linker script, hex conversion
- [ ] `ECALL` / `EBREAK` and minimal CSRs
- [ ] `riscv-tests`: 40/40 `rv32ui`
- [ ] Differential co-simulation against Spike
- [ ] M extension (`MUL` / `DIV`)
- [ ] Memory map, framebuffer, timer, keyboard
- [ ] Run a game on it
- [ ] Run DOOM on it

The reasoning behind the order is in [`docs/STATUS.md`](docs/STATUS.md).
