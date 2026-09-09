# Test Plan

What the suite checks, assertion by assertion, and what it deliberately does not.

---

## Running it

```sh
cd verif
sh run.sh                  # PAD=0 — the real test
PAD=1 sh run.sh            # tight spacing
PAD=2 sh run.sh
PAD=4 sh run.sh            # fully separated, hides every hazard
```

Each run archives its table to `results/pass_fail_pad<N>.txt`.

Current status: **46 of 46 assertions pass at every padding level.**

### Files (all in `verif/`)

| file | role |
|---|---|
| `asm.py` | RV32I assembler — encoders for all six instruction formats |
| `gen_test.py` | builds the program *and* the expected end state, together |
| `check.py` | diffs simulator output against expectations |
| `tb_check.sv` | runs to completion, dumps all 32 registers and 32 memory words |
| `tb_wave.sv` | same plus a VCD, for waveform viewing |
| `gen_demo.py` | short 30-instruction program, readable in a waveform |
| `run.sh` | generate → compile → run → compare |

Expected values are written next to each instruction as it is emitted, so the
program and its oracle cannot drift apart.

---

## The `PAD` knob

`PAD=N` inserts N `nop`s after every instruction. Branch and jump offsets scale
automatically via `slots(n)`.

With enough spacing nothing overlaps in the pipeline, so a correct pipeline
produces exactly the same results as a single-cycle core — which means the same
46 assertions apply at every level. That turns padding into a bisector:

| level | spacing | what it exercises |
|---|---|---|
| `PAD=4` | 5 instructions apart | pipeline registers only — no hazard logic needed |
| `PAD=2` | 3 apart | + write-first register file (RAW distance 3) |
| `PAD=1` | 2 apart | + branch flush, + MEM/WB→EX forwarding |
| `PAD=0` | back to back | + EX/MEM→EX forwarding, + load-use interlock |

If `PAD=4` fails, the plumbing is wrong. If `PAD=4` passes and `PAD=0` fails,
the plumbing is right and it is purely a hazard problem.

---

## Register assertions

| assertion | value | what it proves |
|---|---|---|
| `x0` | `00000000` | **`x0` is hardwired zero** — survives `addi x0, x0, 5` |
| `x1` | `00000005` | `ADDI` |
| `x2` | `00000003` | `ADDI` |
| `x3` | `00000008` | `ADD` |
| `x4` | `00000002` | `SUB` — and that `funct7[5]` selects it |
| `x5` | `00000154` | `AUIPC` captured its own PC |
| `x6` | `000001b4` | `AUIPC` captured its own PC |
| `x7` | `000001bc` | `JALR` link value (`PC+4`) |
| `x8` | `000001c0` | **even** — `JALR` cleared bit 0 of an odd target |
| `x9` | `00000003` | **backward branch** looped exactly 3 times |
| `x10` | `00000001` | `SLT` — `3 < 5` signed |
| `x11` | `ffffffff` | `ADDI` with a negative immediate |
| `x12` | `00000000` | `SLTU` — `0xFFFFFFFF < 5` unsigned is **false** |
| `x13` | `00000001` | `SLT` — `-1 < 5` signed is **true** |
| `x14` | `ffffffff` | `SRAI` — sign propagates, `-1 >>> 1` stays `-1` |
| `x15` | `0000000f` | `SRLI` — logical shift, zeros in |
| `x16` | `abcde000` | `LUI` — via `0 + imm` through `x0` |
| `x17` | `00001088` | `AUIPC` with a non-zero immediate |
| `x18` | `0000007f` | `ADDI` |
| `x19` | `0000007f` | `LW` reads back what `SW` wrote |
| `x20` | `00000000` | loop counter drained to zero |
| `x21` | `44332211` | four `SB`s at lanes 0–3, read back as one word |
| `x22` | `00000011` | `LB` from **lane 0** |
| `x23` | `00000044` | `LB` from **lane 3** |
| `x24` | `ffffffff` | `LB` **sign-extends** a `0xFF` byte |
| `x25` | `000000ff` | `LBU` **zero-extends** the same byte |
| `x26` | `ffffffff` | `LH` **sign-extends** a `0xFFFF` half |
| `x27` | `0000ffff` | `LHU` **zero-extends** the same half |
| `x28` | `00000000` | **no poison ever executed** — see below |
| `x29` | `00000150` | `JAL` link value |
| `x30` | `0000015c` | `JALR` link value |
| `x31` | `0000002a` | sentinel: execution reached the end |

### `x12` / `x13` and `x24` / `x25` are the sharp pairs

Same operands, different instruction, opposite answer. `SLT` vs `SLTU` on `-1`
and `5` is the classic signed/unsigned bug; `LB` vs `LBU` on the same byte is
the classic extension bug. Getting one right and the other wrong is impossible
to fake.

### `x28` is the aggregate control-flow check

Eight taken branches, one `JAL` and two `JALR`s each place a poison instruction
in the slot they are supposed to skip. Every poison does `addi x28, x28, 1`. If
**any** of those eleven redirects fails, `x28` is non-zero. One assertion covers
all of them, and it also catches a broken pipeline flush.

---

## Memory assertions

The first 31 registers already carried expectations, so the remaining checks
park their results in data memory.

| assertion | value | what it proves |
|---|---|---|
| `mem[8]` | `00000001` | `SLTI` — `-1 < 0` signed |
| `mem[9]` | `00000000` | `SLTI` with a **negative immediate** — see below |
| `mem[10]` | `00000000` | `SLTIU` — unsigned compare |
| `mem[11]` | `fffffffa` | `XORI` with a **negative immediate** |
| `mem[12]` | `0000000d` | `ORI` |
| `mem[13]` | `000000f0` | `ANDI` |
| `mem[14]` | `00000050` | `SLLI` |
| `mem[15]` | `ffffffff` | `SRA` — arithmetic, sign fills |
| `mem[16]` | `1fffffff` | `SRL` — logical, zeros fill |
| `mem[17]` | `00000000` | reading `x0` after a write attempt still gives zero |
| `mem[18]` | `0000000a` | **shift amount ≥ 32** uses only `OpB[4:0]` — `5 << (33 & 31)` |
| `mem[19]` | `0000005a` | value staged for the load-use test |
| `mem[20]` | `0000005b` | **load-use interlock** — see below |
| `mem[21]` | `00000022` | **forwarding priority** — see below |

### `mem[9]` and `mem[11]` prove the decoder's `funct7` zeroing

Both use immediate `-1` = `0xFFF`, which puts a 1 in `instruction[30]` — the bit
that becomes `funct7[5]`. Without the decoder zeroing `funct7` for non-shift
I-type instructions, `SLTI` would decode as `AluCtrl=1010` and `XORI` as `1100`,
both of which fall through to the ALU default and return 0.

### `mem[15]` vs `mem[16]` prove the ALU encoding

Identical operands and shift amount. `SRA` gives `ffffffff`, `SRL` gives
`1fffffff`. The only difference between them is `funct7[5]`, so this confirms
`AluCtrl = {funct7[5], funct3}` reaches the right ALU arm.

### `mem[20]` — load-use interlock

```asm
sw   x20, 19*4(x0)      # store 0x5A
lw   x20, 19*4(x0)      # load it back
addi x20, x20, 1        # USE immediately -> forwarding cannot help
sw   x20, 20*4(x0)      # expect 0x5B
```

Forwarding cannot fix this: when the `addi` is in EX, the `lw` is in MEM and
`mem_alu_res` holds the **address**, not the data. Only a one-cycle stall works.
Remove `hazard.sv` and this assertion fails while everything else still passes.

### `mem[21]` — forwarding priority

```asm
addi x20, x0, 0x11
addi x20, x0, 0x22
addi x20, x20, 0        # must read 0x22, not 0x11
```

Both EX/MEM and MEM/WB match on `x20`. EX/MEM holds the newer value and must
win. Inverting the `if`/`else if` in `forward.sv` yields `0x11` here and passes
everything else — verified.

---

## Coverage summary

### Instructions — all 37 base integer, across all six formats

| format | instructions | covered by |
|---|---|---|
| **R** (10) | `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` | `x3 x4 x8 x10 x12 x7 x9`, `mem[15] mem[16]` |
| **I** (15) | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` + `LB LH LW LBU LHU` + `JALR` | `x1 x11 x14 x15`, `mem[8]`–`mem[14]`, `x19`–`x27`, `x7 x30` |
| **S** (3) | `SB SH SW` | `x21 x26 x19` |
| **B** (6) | `BEQ BNE BLT BGE BLTU BGEU` | `x28` (taken) and `x9` (not taken) |
| **U** (2) | `LUI AUIPC` | `x16 x17 x5 x6 x8` |
| **J** (1) | `JAL` | `x29`, `x28` |

Every branch comparison is tested in **both directions** — eight taken cases
including the `>=`-on-equal boundary for `BGE`/`BGEU`, and four not-taken cases.

### Datapath behaviour

- Byte placement and selection at **all four lane offsets**
- Sign versus zero extension for both byte and halfword
- Halfword access in the **high** lane (`addr[1] = 1`), not just lane 0
- Little-endian assembly — four `SB`s read back as a single word
- Signed versus unsigned comparison in both the ALU and the branch comparator

### Edge cases

- `x0` write protection, both the write and a subsequent read
- Shift amounts ≥ 32 masked to five bits
- **Backward branches** — negative B-type offsets, i.e. real loops
- **`JALR` bit-0 masking**, detected by an `AUIPC` at the landing site that
  would capture an odd PC if the mask were missing

### Pipeline behaviour

- Branch and jump **flush** — via `x28` across eleven redirects
- **Forwarding** at distance 1 and 2, including priority between them
- **Write-first register file** at distance 3 (implicit — `PAD=2` passing
  requires it)
- **Load-use interlock**
- Store data forwarding (`addi` immediately followed by `sb` of the same register)
- Comparator operating on forwarded values (the loop's `bne` reads a register
  written one instruction earlier)

---

## Not covered

| gap | why |
|---|---|
| `ECALL` / `EBREAK` | not implemented — need CSRs and trap handling |
| `FENCE` | decodes as a no-op, which is spec-correct on a single-core in-order machine with no caches |
| Misaligned access traps | `data_mem` guards silently drop misaligned halfword and word stores instead of raising an exception |
| CSRs (Zicsr) | not implemented |
| Instruction-memory edge behaviour | ROM is idealised: single-cycle, no wait states |
| Exhaustive operand coverage | this is a **directed** suite — one or two operand pairs per instruction, not a sweep |

That last row is the real limitation. Directed tests only cover cases someone
thought of. `riscv-tests` runs roughly 40 programs with far broader operand
coverage per instruction, which is why it is the next verification step.

---

## Method note

Two assertions here were added **after** the corresponding logic already
appeared to work, and both immediately exposed real gaps:

- `PAD=0` passed with **no load-use stall at all**, because no load in the suite
  was followed by a use. A false green on the one hazard forwarding cannot fix.
- Nothing tested forwarding priority until `mem[21]` was added.

Both new assertions were then confirmed to **fail** when the corresponding logic
is removed or inverted. A test that has never failed has not been shown to work.
