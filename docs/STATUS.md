# Status and Roadmap

What is built, what is next, and why the order is what it is.

---

## Where the project stands

**A 5-stage pipelined RV32I core, verified against 46 self-checking assertions
at every padding level.**

| milestone | tag | state |
|---|---|---|
| Single-cycle RV32I, all 37 base integer instructions | `v1.0-singlecycle` | done, 43/43 |
| 5-stage pipeline with forwarding and hazard detection | `v2.0-pipelined` | done, 46/46 |
| `riscv-tests` (`rv32ui`) | — | not started |
| Memory map, framebuffer, timer | — | not started |
| Run a game | — | not started |

---

## Done

**Instruction set.** All 37 RV32I base integer instructions across all six
encoding formats. `FENCE` decodes as a no-op, which is spec-correct on a
single-core in-order machine with no caches.

**Pipeline.** Five stages, four pipeline registers, and every hazard class
handled:

- branch and jump **flush** — clears IF/ID and ID/EX on any PC redirect
- **forwarding** — EX/MEM→EX and MEM/WB→EX, with EX/MEM taking priority
- **write-first register file** — covers RAW at distance 3 without a bypass path
- **load-use interlock** — freeze PC and IF/ID, bubble ID/EX, one cycle

**Verification.** A Python RV32I assembler and a self-checking test generator
that emits the program and its expected end state together. 46 assertions
covering every instruction, both branch polarities across all six comparisons,
byte placement at all four lane offsets, and the edge cases that quietly break
cores.

---

## Not implemented

| gap | needed for |
|---|---|
| `ECALL` / `EBREAK` | clean simulation halt; syscalls later |
| CSRs (Zicsr) | traps, interrupts, `rdcycle` |
| Misalignment traps | `data_mem` silently drops misaligned halfword and word stores rather than raising an exception |
| M extension (`MUL`, `DIV`) | DOOM's fixed-point math |
| Memory map / peripherals | anything with a display |

---

## Next, in order

### 1. Toolchain

`riscv-none-elf-gcc` (xPack prebuilt — no WSL needed), a linker script placing
`.text` at 0, and a short `bin2hex.py` to feed `$readmemh`. This is the tedious
block, and everything after it gets easier because there is a compiler.

### 2. `EBREAK` as a halt

Five lines, no CSRs. `control` raises a `System` signal on opcode `1110011` with
`funct3 = 000`; it rides the pipeline to WB and drives `halt`; the testbench
calls `$finish`. Asserting in WB rather than EX means everything older has
already retired.

Worth doing while already in the toolchain weeds — 40 back-to-back test runs
need a clean termination.

### 3. `riscv-tests` — 40/40 `rv32ui`

Clone the suite for its **test sources**, not its build system. The stock
`rv32ui-p-*` environment assumes machine-mode traps and CSRs; replace
`riscv_test.h` with about 20 lines that redefine `RVTEST_PASS`/`RVTEST_FAIL` to
store a result to a magic address and spin. The testbench watches that address.

Also needed: grow ROM and data memory past their current sizes.

### 4. Memory map, framebuffer, timer

An address decoder routing to RAM, ROM, a framebuffer, keyboard input and a
millisecond counter. This is the step that turns a CPU core into an **SoC**.

A memory-mapped timer avoids needing `rdcycle`, and therefore CSRs.

### 5. Run a game

Pac-Man before DOOM. Same infrastructure — framebuffer, timer, input, memory map
— at kilobytes instead of megabytes, and it does not need the M extension
because GCC emits soft-multiply for `-march=rv32i`. If it runs, the remaining
gap to DOOM is memory capacity and speed, not architecture.

### 6. DOOM

Needs the M extension, several megabytes of RAM, and enough throughput to be
watchable. Verilator rather than Icarus by this point.

---

## Ordering rationale

**Verification before optimisation.** A hazard bug and an instruction-decode bug
look identical from the outside. Getting the ISA verified first means any
failure after a pipeline change is definitionally a hazard bug, which halves the
search space.

**`riscv-tests` before peripherals.** The directed suite in `verif/` only covers
cases somebody thought of. Roughly 40 externally written programs with far
broader operand coverage will find things it cannot. Better to discover those
before a framebuffer is in the picture.

**Pac-Man before DOOM.** Identical infrastructure, a fraction of the memory, and
it de-risks the whole peripheral stack. A DOOM failure on unproven hardware
gives you a black screen and no idea which layer broke.

---

## Deliberate non-goals

**No branch predictor yet.** Branches resolve in EX, so a taken branch costs two
flush slots. A predictor would reduce how often that is paid, but the penalty
size is set by the resolve stage. Worth measuring CPI before spending hardware
on it.

**No cache yet.** A cache hides memory latency, and both memories currently
answer in zero cycles. It becomes real when external SDRAM does.

**No multicycle variant.** It is a teaching step between single-cycle and
pipelined, not a destination. Nothing ships it.
