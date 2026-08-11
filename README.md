# RV32I "DOOMED" CPU

A 32-bit RISC-V processor written from scratch in SystemVerilog.

**Status:** single-cycle core complete — all 37 RV32I base integer instructions implemented and verified, 43/43 assertions passing.
**Next:** 5-stage pipeline with forwarding and hazard detection → `riscv-tests` → run DOOM on it.

---

## What it implements

All 37 base integer instructions, across all six RISC-V encoding formats:

| format | count | instructions |
|---|---|---|
| **R-type** | 10 | `ADD` `SUB` `SLL` `SLT` `SLTU` `XOR` `SRL` `SRA` `OR` `AND` |
| **I-type** | 15 | `ADDI` `SLTI` `SLTIU` `XORI` `ORI` `ANDI` `SLLI` `SRLI` `SRAI` `LB` `LH` `LW` `LBU` `LHU` `JALR` |
| **S-type** | 3 | `SB` `SH` `SW` |
| **B-type** | 6 | `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU` |
| **U-type** | 2 | `LUI` `AUIPC` |
| **J-type** | 1 | `JAL` |

`FENCE` decodes to a no-op, which is spec-correct on a single-core in-order machine with no caches.
`ECALL` / `EBREAK` are not implemented — they require CSRs and trap handling, which arrive alongside `riscv-tests`.

---

## Datapath

```mermaid
flowchart LR
    PC[PC] --> ROM[Instruction<br/>ROM]
    ROM --> DEC[Decoder]
    DEC --> CTRL[Control]
    DEC --> RF[Register<br/>File]

    RF -->|rd1| MA{{AluSrcA}}
    PC --> MA
    RF -->|rd2| MB{{AluSrc}}
    DEC -->|imm| MB

    MA --> ALU[ALU]
    MB --> ALU

    RF -->|rd1, rd2| CMP[Branch<br/>Comparator]
    CMP -->|cmp| NPC{{next-PC mux}}

    ALU -->|res| DM[Data<br/>Memory]
    ALU --> NPC
    NPC --> PC

    DM --> LX[Load<br/>Extend]
    LX --> WB{{writeback mux}}
    ALU --> WB
    PC --> WB
    WB --> RF
```

**Next-PC select** is the 2-bit field `{Branch, Jump}`:

| `{Branch,Jump}` | next PC | instructions |
|---|---|---|
| `00` | `PC + 4` | sequential |
| `01` | `ALU result` (`PC + imm`) | `JAL` |
| `10` | `cmp ? ALU result : PC + 4` | B-type |
| `11` | `ALU result & ~1` | `JALR` |

**Writeback select:** `MemToReg` → load data, else `Jump` → `PC + 4`, else ALU result.

---

## Design decisions

**One ALU for every PC-relative target.** `JAL`, branches, and `AUIPC` all need `PC + imm`. Rather than add a dedicated branch-target adder, a single `AluSrcA` bit steers `PC` onto the ALU's A input. The ALU is idle on branches anyway — the comparison is a separate unit — so the adder would have been redundant hardware. Only `PC + 4` gets its own adder, because `JAL`/`JALR` need the target and the link value in the same cycle.

**`AluSrcA` is the only bit distinguishing `LUI` from `AUIPC`.** Every other control signal is identical between them: `LUI` computes `0 + imm`, `AUIPC` computes `PC + imm`.

**`LUI` costs no extra hardware.** The decoder leaves `rs1 = x0` for U-type and J-type instructions, and `x0` is hardwired zero, so the ALU produces `0 + imm` with no special case. The same default also prevents J/U-type instructions from reading a garbage register out of immediate bits that happen to sit in `instruction[19:15]`.

**Writeback needs no dedicated selector.** `Jump` is high for exactly `JAL` and `JALR` — precisely the two instructions whose `rd` receives `PC + 4` — so the existing signal does the job a wider mux select would have.

**Control is pure instruction decode.** It receives only `opcode`, `funct3`, and `funct7`, never datapath values. The branch comparator is a separate module for this reason, and it keeps control signals cleanly pipelineable.

Result: **9 control signals** total.

---

## Modules

| file | module | role |
|---|---|---|
| `top.sv` | `top_wire` | datapath wiring, muxes, load extend |
| `PC.sv` | `PrgCo` | program counter |
| `ROM.sv` | `ROME` | instruction memory |
| `decoder.sv` | `decoder` | field extraction, immediate reassembly |
| `control.sv` | `control` | opcode → control signals |
| `registers.sv` | `registers` | 32×32 register file, `x0` write-guarded |
| `ALU.sv` | `ALU` | 10 operations, `{funct7[5], funct3}` encoded |
| `cmp.sv` | `comparator` | branch condition, signed/unsigned |
| `data_mem.sv` | `memory` | byte/halfword/word access, misalignment guards |

---

## Verification

`test/` contains a self-checking harness built from scratch:

| file | purpose |
|---|---|
| `asm.py` | RV32I assembler — encoders for all six instruction formats |
| `gen_test.py` | generates a 105-instruction test program + expected register/memory state |
| `gen_demo.py` | generates a short, readable 30-instruction demo for waveform viewing |
| `tb_check.sv` | runs to completion, dumps all registers and memory |
| `tb_wave.sv` | same, plus VCD output and a per-instruction commit log |
| `check.py` | diffs simulator state against expectations |
| `run.sh` | the whole loop in one command |

```sh
cd test && sh run.sh
```

```
checked 43 values, 0 failures
```

### Coverage

- Every one of the 37 instructions executed and its result checked
- All six branch comparisons, **both** taken and correctly not-taken
- Byte placement verified at all four lane offsets — `0x12345678` written by four `SB`s and read back one byte at a time
- Signed vs unsigned comparison (`-1 < 5` is true signed, false unsigned)
- `SRA` vs `SRL` on identical operands, confirming the `{funct7[5], funct3}` decode
- Sign vs zero extension: `LB` and `LBU` on the same byte return `0xFFFFFFFF` and `0x000000FF`

### Edge cases

- `x0` remains zero when written to
- Shift amounts ≥ 32 use only the low 5 bits
- **Backward branches** — negative B-type offsets, verified with a 3-iteration loop
- **`JALR` clears bit 0** of its computed target — verified by landing on an address that would be odd if the mask were missing

---

## Running it

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) and Python 3.

**Full verification:**
```sh
cd test && sh run.sh
```

**Waveform demo** (30-instruction program, retires at 325 ns):
```sh
cd test
python gen_demo.py
iverilog -g2012 -o demo.vvp ROM_demo.sv tb_wave.sv \
    ../ALU.sv ../PC.sv ../control.sv ../cmp.sv \
    ../data_mem.sv ../decoder.sv ../registers.sv ../top.sv
vvp demo.vvp
gtkwave wave.vcd
```

Signals worth watching: `PC_loc`, `IR_loc`, `OpA_loc`, `OpB_loc`, `res_loc`, `cmp_loc`, `next_PC_loc`, `wd_loc`.

---

## Roadmap

- [x] Single-cycle RV32I core
- [x] Sub-word loads and stores with sign/zero extension
- [x] Self-checking test harness — 43/43
- [ ] 5-stage pipeline: forwarding, load-use interlock, branch flush
- [ ] `ECALL` / `EBREAK` + minimal CSRs
- [ ] `riscv-tests` — 40/40 `rv32ui`
- [ ] Differential co-simulation against Spike
- [ ] M extension (`MUL` / `DIV`)
- [ ] Memory map, framebuffer, timer, keyboard
- [ ] Run a game on it
- [ ] Run DOOM on it
