# Performance, Timing and Area Metrics

What this core achieves today, where its limits come from, and what has to change
for it to become a product.

Measured on 2026-09-10 against `rtl/` at commit `be98a94` (the 5-stage pipeline).

Every number below carries one of three labels:

| label | meaning |
|---|---|
| **MEASURED** | produced by a tool run on this RTL. Method in section 9. |
| **DERIVED** | arithmetic on measured numbers. The formula is shown. |
| **ESTIMATED** | a model or a published rule of thumb. The assumptions are stated. Treat these as ranges, not facts. |

---

## 1. Headline numbers

| metric | value | label |
|---|---|---|
| CPI, dependent ALU chain | **1.000** | MEASURED |
| CPI, loop kernels | **1.17 – 1.59** | MEASURED |
| CPI, call-heavy code | **2.18** | MEASURED |
| CPI, typical compiled code | ~1.3 – 1.5 | ESTIMATED |
| Fmax, Lattice ECP5-85F, speed grade 6 | **61.8 – 65.9 MHz**, median 64.6 | MEASURED, post-route, 4 seeds |
| Fmax, Lattice ECP5-85F, speed grade 8 | **85.6 – 89.3 MHz** | MEASURED, post-route, 2 seeds |
| Fmax, Lattice iCE40-HX8K | **46.7 MHz** | MEASURED, post-route, 1 seed |
| Throughput, typical code, ECP5-6 | ~43 – 50 MIPS | DERIVED: Fmax ÷ CPI |
| Critical path | **forwarding compare → forwarding mux → 32-bit compare/add → next-PC mux → PC** | MEASURED |
| Critical path composition, ECP5 | 32% logic, **68% routing** | MEASURED |
| Logic depth, technology-independent | **76 gate levels** | MEASURED |
| Area, ECP5 | 3,931 LUT4 + 1,549 FF (4% / 1% of an 85F) | MEASURED |
| Area, iCE40 | 4,359 logic cells (56% of an HX8K) | MEASURED |
| Register file's share of LUTs | **75%** | MEASURED |
| Best measured variant: no reset + narrow flush | **2,233 LUT4 + 525 FF at 65.0 MHz** | MEASURED (5.3) |

If you remember only three things:

1. **The pipeline is unbalanced.** EX is about 3× deeper than any other stage, so
   the clock is set entirely by the branch-resolution loop in EX.
2. **The register file's reset loop costs three quarters of the core's LUTs.**
   Removing it halves the design but costs 12% Fmax by moving the critical path onto
   the flush fanout. Narrowing the flush as well wins all of it back: **43% fewer
   LUTs and 66% fewer flip-flops at the same clock speed** (section 5).
3. **Taken branches are the dominant CPI cost**, at 25–35% of all cycles in
   ordinary loops. Load-use stalls are small by comparison and a compiler removes
   most of them.

---

## 2. CPI — cycles per instruction

### 2.1 Results — MEASURED

Eight microbenchmarks, each built to isolate one pipeline behaviour, plus the
directed verification program from `verif/`.

| workload | what it isolates | instr | cycles | **CPI** | IPC | stall cycles | flush cycles |
|---|---|---|---|---|---|---|---|
| `alu_chain` | back-to-back dependent ALU ops | 121 | 121 | **1.000** | 1.000 | 0.0% | 0.0% |
| `sum_unroll4` | array sum, unrolled ×4, scheduled | 179 | 209 | **1.168** | 0.856 | 0.0% | 14.4% |
| `directed_test` | the `verif/` suite program | 108 | 135 | **1.250** | 0.800 | 0.7% | 19.3% |
| `memcpy_sched` | word copy, load and store separated | 387 | 513 | **1.326** | 0.754 | 0.0% | 24.6% |
| `sum_sched` | array sum, load hoisted from its use | 323 | 449 | **1.390** | 0.719 | 0.0% | 28.1% |
| `memcpy_naive` | word copy, store uses the load at once | 387 | 577 | **1.491** | 0.671 | 11.1% | 21.8% |
| `branchy` | data-dependent branch, ~50% taken | 356 | 546 | **1.534** | 0.652 | 0.0% | 34.8% |
| `sum_naive` | array sum, add uses the load at once | 323 | 513 | **1.588** | 0.630 | 12.5% | 24.6% |
| `call_ret` | `jal` + `jalr` every iteration | 163 | 355 | **2.178** | 0.459 | 0.0% | 54.1% |

**Correctness of the measurement itself:**

- Every run satisfies `cycles = instructions + stall_cycles + 2 × flushes` exactly.
  Each hazard event is accounted for, with nothing unexplained.
- Every instruction count matches the **single-cycle core** (`v1.0-singlecycle`) running
  the same program. That core has CPI = 1 by construction, so its cycle count is an
  independent instruction count.
- Every workload's result was checked (the array sums equal 2080, the copied block
  sums to 2080, the call and branch counters equal 32).

### 2.2 The penalty model — MEASURED costs

Per-event costs, read directly off the accounting identity:

| event | cost | why |
|---|---|---|
| dependent ALU op at distance 1 or 2 | **0 cycles** | EX/MEM→EX and MEM/WB→EX forwarding |
| dependent op at distance 3 | **0 cycles** | write-first register file |
| load immediately consumed | **+1 cycle** | load data exists only after MEM |
| taken branch | **+2 cycles** | resolved in EX, flushing IF and ID |
| `jal` / `jalr` | **+2 cycles** | same redirect path as a taken branch |
| not-taken branch | 0 cycles | fetch was already sequential |

So:

```
CPI = 1 + f_loaduse × 1 + f_taken_branch × 2 + f_jump × 2
```

where each `f` is a fraction of all instructions. `sum_naive` predicts
`(5 + 1 + 2) / 5 = 1.600` per iteration, and measures 1.588 once loop setup and the
final not-taken exit are included.

### 2.3 What the numbers say

**Forwarding is complete.** `alu_chain` makes every instruction consume its
predecessor's result and runs at exactly 1.000. No data hazard on an ALU result ever
costs a cycle.

**Taken branches are the dominant cost.** They consume 25–35% of all cycles in
ordinary loops and 54% in call-heavy code. This is the biggest CPI lever available:
a branch predictor would recover most of it (section 6, lever 5).

**Load-use is small, and the compiler controls it.** The same algorithm moves from
1.588 to 1.390 just by hoisting the load one instruction earlier. Unrolling gets it
to 1.168. **The identical source can land anywhere from 1.17 to 1.59 on this
pipeline, depending on the compiler.** Any CPI quoted without naming the compiler and
flags is not a meaningful number.

**Load → store-data stalls where it doesn't need to.** In `memcpy_naive` the store's
data register is the just-loaded value, and the hazard unit stalls because it
compares against `rs2`. But a store needs its data in **MEM**, not EX, and by then
the load has finished. Forwarding load data directly into the store-data path in MEM
would remove this stall with no loss of correctness. Current cost: 11% of cycles on
a naive copy loop.

### 2.4 Typical compiled code — ESTIMATED

Real programs sit between the microbenchmarks. Plugging an instruction mix into the
measured penalty model:

| profile | loads (immediately used) | branches (taken) | jumps | **CPI** |
|---|---|---|---|---|
| favourable | 20% (30%) | 15% (55%) | 3% | 1.29 |
| middle | 22% (40%) | 17% (62%) | 4% | 1.38 |
| unfavourable | 25% (50%) | 20% (70%) | 5% | 1.51 |

The mix fractions are **assumptions**, typical of compiled integer code on a
load-store ISA. They are not measured here, and the real figure needs the toolchain
plus a benchmark such as CoreMark (section 8). The penalties they multiply are
measured.

---

## 3. Timing

### 3.1 Maximum clock frequency — MEASURED

Post-route timing from nextpnr on the synthesised core (method in 9.2):

| device | speed grade | seeds | Fmax (MHz) | median |
|---|---|---|---|---|
| Lattice ECP5 LFE5U-85F | 6 (slowest) | 4 | 61.80, 63.87, 65.30, 65.92 | **64.6** |
| Lattice ECP5 LFE5U-85F | 8 (fastest) | 2 | 85.62, 89.30 | **~87** |
| Lattice iCE40 HX8K (CT256) | — | 1 | 46.71 | **46.7** |

The seed-to-seed spread on ECP5-6 is about 6%, which is the placement noise floor.
Differences smaller than that between two builds are not meaningful.

### 3.2 Throughput — DERIVED

`MIPS = Fmax ÷ CPI`. Millions of instructions retired per second — **not** DMIPS,
which needs Dhrystone and a compiler.

| workload | CPI | ECP5-6 (64.6 MHz) | ECP5-8 (85.6 MHz) | iCE40 (46.7 MHz) |
|---|---|---|---|---|
| `alu_chain` | 1.000 | 64.6 | 85.6 | 46.7 |
| `sum_unroll4` | 1.168 | 55.3 | 73.3 | 40.0 |
| `sum_sched` | 1.390 | 46.5 | 61.6 | 33.6 |
| `sum_naive` | 1.588 | 40.7 | 53.9 | 29.4 |
| `call_ret` | 2.178 | 29.7 | 39.3 | 21.4 |
| typical, middle estimate | 1.38 | ~47 | ~62 | ~34 |

### 3.3 The critical path — MEASURED

**ECP5-85F, speed grade 6, seed 1 — 15.17 ns (65.9 MHz).** Reconstructed from the
nextpnr timing report:

| # | segment | cumulative (ns) |
|---|---|---|
| 1 | clock-to-Q of **`wb_rd`** (the MEM/WB destination register field) | 0.52 |
| 2 | **forwarding unit**: compare `wb_rd == ex_rs2`, gated by `RegWrite` | 3.66 |
| 3 | **forwarding mux** → `fwd_rd2` | 5.65 |
| 4 | **32-bit branch comparator** — hardened carry chain | 11.65 |
| 5 | branch-taken decision → next-PC select logic | 13.35 |
| 6 | **next-PC mux** → `next_pc[0]` → **PC register** | 15.17 |

Total: 4.90 ns logic, **10.27 ns routing**.

This is the **EX-stage branch-resolution loop**, the textbook limiter of a classic
5-stage pipeline. The branch decision depends on forwarded operands, and it has to
reach the PC within the same cycle.

**iCE40-HX8K — 21.41 ns (46.7 MHz).** The same family of path:
`ex_rs1` (ID/EX) → forwarding compare → forwarding mux → ALU adder carry chain →
EX/MEM `alu_res`. 5.74 ns logic, **15.67 ns routing**.

**The forwarding comparison is the head of every critical path found** — from
`wb_rd` on ECP5, from `ex_rs1` on iCE40, from `mem_rd` in the what-if builds.
Section 6 describes how to take it out of the loop.

### 3.4 Logic depth, technology-independent — MEASURED

Yosys generic synthesis mapped to 2-input gates and multiplexers, then the longest
flop-to-flop topological path:

**76 levels:** `ex_rs1` → forwarding compare → forwarding mux → operand mux → ALU →
`ex_alu_res[31]` → `next_pc[31]` → PC.

Each module on its own:

| module | combinational depth | generic cells |
|---|---|---|
| `ALU` | **65** | 1,238 |
| `comparator` | 17 | 177 |
| `decoder` | 12 | 131 |
| `registers` (read path, incl. write-first bypass) | 10 | 4,713 |
| `control` | 7 | 39 |
| `hazard` | 7 | 33 |
| `load_extend` | 7 | 129 |
| `forward` | 6 | 52 |

The ALU is 85% of the longest path in generic gates, because Yosys maps the adder as
a ripple structure. **This is a generic-gate artefact:** FPGAs use hardened carry
chains (which is why the comparator's chain, not the adder, won on ECP5), and an ASIC
flow would use a parallel-prefix adder.

### 3.5 Stage balance — DERIVED from 3.4

| stage | deepest combinational content | approx. levels |
|---|---|---|
| IF | PC → +4 incrementer → next-PC default | small |
| ID | decoder (12) → register-file read (10) → ID/EX | ~22 |
| **EX** | forward (6) → muxes (~3) → ALU (65) / comparator (17) → next-PC (~2) | **~76** |
| MEM | EX/MEM → memory → `load_extend` (7) → MEM/WB | 7 + memory |
| WB | writeback mux → register-file write, write-first bypass | ~5 |

**EX is roughly 3× deeper than ID, and far deeper than everything else.** The other
four stages spend most of every cycle idle. Balancing the pipeline is where the next
large Fmax gain lives.

### 3.6 Routing dominates — MEASURED

68% of the ECP5 critical path and 73% of the iCE40 path is wire, not logic. The
design is **placement- and fanout-bound**, not logic-bound. Two structural causes:

- The **register file is 1,024 flip-flops plus two 32:1 read multiplexers**. That
  spreads the placement, lengthening every wire that crosses it.
- **`flush` and `stall` drive about 286 flip-flops** ([rtl/top.sv:80](../rtl/top.sv#L80),
  [rtl/top.sv:93](../rtl/top.sv#L93)), because they clear every bit of IF/ID and ID/EX —
  32-bit PCs, operands and immediates included. A bubble only needs its
  side-effecting control bits cleared.

### 3.7 ASIC — NOT MEASURED

No standard-cell library or PDK was available, so there is no ASIC Fmax, area or
power here. The technology-independent result carries over: the limiting loop is
forwarding → compare/add → next-PC, and the generic ripple adder (65 levels) would be
replaced by a parallel-prefix adder in any real ASIC flow, shortening it
substantially. Section 8 describes the flow that would produce real numbers.

---

## 4. Area

### 4.1 Utilisation — MEASURED

| resource | ECP5-85F | iCE40-HX8K |
|---|---|---|
| LUT4 | 3,931 | 2,972 |
| mux primitives | 1,124 PFUMX + 456 L6MUX21 | — |
| carry | 63 CCU2C | 123 SB_CARRY |
| flip-flops | 1,549 | 1,549 |
| block RAM | 0 of 208 | 0 of 32 |
| device use | 4% logic, 1% FF | **56%** logic cells, 80% I/O |

The iCE40 build places its memory buses on 166 pins. On a real board those buses
would connect to on-chip or external memory rather than pins.

### 4.2 Per-module — MEASURED (generic synthesis)

| module | generic cells | share | flip-flops |
|---|---|---|---|
| **`registers`** | **4,045** | **58%** | **992** |
| `ALU` | 1,246 | 18% | — |
| `top` glue: pipeline registers, forwarding muxes, next-PC | 1,045 | 15% | 494 |
| `comparator` | 180 | 3% | — |
| `decoder` | 131 | 2% | — |
| `load_extend` | 129 | 2% | — |
| `forward` | 52 | <1% | — |
| `control` | 39 | <1% | — |
| `hazard` | 33 | <1% | — |
| `PrgCo` | 32 | <1% | 32 |
| **total** | **6,932** | | **1,518** |

The 494 pipeline flip-flops match the boundary spec in
[`ARCHITECTURE.md`](ARCHITECTURE.md) almost exactly. `x0` is optimised away, which is
why the register file has 992 flops rather than 1,024.

### 4.3 The register file — MEASURED

[`rtl/registers.sv`](../rtl/registers.sv) resets all 32 registers to zero. A reset
prevents the synthesiser from mapping the register file onto distributed RAM, so it
becomes 1,024 flip-flops plus two full 32:1 read multiplexers.

Synthesised standalone on ECP5:

| variant | LUT4 | FF | LUTRAM (DPR16X4) | total cells |
|---|---|---|---|---|
| as written, with reset | **2,947** | **1,024** | 0 | 5,451 |
| reset loop removed | **182** | **0** | 32 | 252 |

**The reset costs about 2,765 LUT4s and every one of those 1,024 flip-flops — about
three quarters of the entire core.**

The RISC-V specification does not require general registers to reset; only `x0` is
defined. Many shipping cores leave them uninitialised. Note that the directed test
currently depends on the reset: its poison counter `x28` is never initialised
explicitly, so it would need an `addi x28, x0, 0` first.

### 4.4 Data memory — MEASURED

[`rtl/data_mem.sv`](../rtl/data_mem.sv) synthesised standalone on ECP5:

| resource | count |
|---|---|
| distributed RAM (DPR16X4) | **512** — 4× the 128 a 256 × 32 memory needs |
| LUT4 of read multiplexing | **1,036** |
| block RAM (DP16KD) | **0** |

The asynchronous read (`always_comb mem_dat = memistan[...]`) rules out block RAM,
because FPGA block RAMs and ASIC SRAM macros are **synchronous**: the address is
captured on a clock edge. So a 1 KB memory costs about a quarter of the core's LUT
count in multiplexers. At the capacity DOOM needs, measured in megabytes, this form
cannot be built at all. See section 6.

---

## 5. Measured what-ifs

Two alternative builds, synthesised and placed exactly like the baseline. Your RTL
was not modified: both are scratch copies.

### 5.1 Register file without reset

| | baseline | no reset | change |
|---|---|---|---|
| LUT4 | 3,931 | 1,805 | **−54%** |
| flip-flops | 1,549 | 525 | **−66%** |
| distributed RAM | 0 | 32 | |
| Fmax, ECP5-6 (3 seeds) | 64.6 median | 55.97, 57.00, 58.87 — **57.0** median | **−12%** |
| MIPS per 1k LUT at CPI 1.38 | 11.9 | **22.9** | **+92%** |

**Half the area, yet slower** — and outside the seed noise. The critical path moved.
It now runs `mem_rd` → forwarding compare → forwarding mux → carry chain → branch
decision → **`flush`** → the synchronous-reset (LSR) pin of the `id_instr`
flip-flops. That's 17.87 ns: 6.55 logic, 11.32 routing.

With the register file shrunk, the placer reorganised the design, and `flush`'s
fanout into IF/ID became the longest wire. **Area and timing optimisations do not
compose automatically.** Removing the reset is still the right product decision —
nearly double the performance per LUT — and 5.2 shows that pairing it with a
narrower flush wins the lost clock speed back.

### 5.2 Squash only the control bits on flush and stall

Today `flush` and `stall` clear every bit of IF/ID and ID/EX — about 286
flip-flops. The variant clears only what a bubble actually needs cleared:

- **IF/ID:** `id_instr` is squashed (an all-zero word decodes to all-zero control).
  `id_pc` and `id_pc_plus4` hold on stall and are never flushed.
- **ID/EX:** only the six side-effecting bits are squashed — `RegWrite`, `MemRead`,
  `MemWrite`, `MemToReg`, `Branch`, `Jump`. Operands, immediates, register indices
  and ALU selects pass through. With those six bits at zero the bubble cannot write a
  register, touch memory, redirect the PC, trigger forwarding (gated by `RegWrite`)
  or trigger the load-use interlock (gated by `MemRead`), so its data is dead.

That takes the flush/stall reset fanout from about 286 flip-flops to **38**.

**Correctness — MEASURED.** 46/46 assertions at padding levels 0, 1, 2 and 4, and
cycle counts **bit-identical** to the baseline on all eight CPI workloads. It is a
pure timing change.

**On the baseline, alone — MEASURED:**

| | baseline | control-only flush |
|---|---|---|
| LUT4 | 3,931 | 3,808 (−3%) |
| flip-flops | 1,549 | 1,549 |
| Fmax, ECP5-6 (3 seeds) | 64.6 median | 63.07, 65.21, 66.68 — **65.2** median |

**No measurable gain on its own.** The difference is inside the 6% seed-noise floor,
which is expected: the baseline's critical path ends at the PC register, not at the
flush fanout, so shortening the fanout does not touch the limiting path.

Its value appears where the fanout **is** the critical path — the no-reset build of
5.1.

### 5.3 Combined: no-reset register file + control-only flush — MEASURED

| | baseline | no reset (5.1) | **combined** |
|---|---|---|---|
| LUT4 | 3,931 | 1,805 | **2,233** (−43%) |
| flip-flops | 1,549 | 525 | **525** (−66%) |
| distributed RAM | 0 | 32 | 32 |
| Fmax, ECP5-6 | 64.6 median, 4 seeds | 57.0 median, 3 seeds | 66.59, 64.99, 64.55 — **65.0** median |
| critical-path endpoint | PC register | `id_instr` reset pin (flush) | PC register |
| MIPS per 1k LUT at CPI 1.38 | 11.9 | 22.9 | **21.1** |

**The narrower flush recovers everything the reset removal cost.** Fmax is back at
the baseline (the 0.4 MHz difference is noise). The critical path has moved off the
flush fanout and back onto the EX loop. And the core keeps 43% fewer LUTs and 66%
fewer flip-flops. That's **1.77× the baseline's performance per LUT at the same clock
speed** — the best build measured.

Its critical path is 15.02 ns (4.99 logic, 10.02 routing), from `wb_Jump` to the PC.
`wb_Jump` only drives the writeback mux, so the path must run writeback mux →
`wb_data` → forwarding mux → EX → next-PC → PC. **The writeback mux sits inside the
MEM/WB→EX forwarding path** — see lever 4.

**Why the combined build has more LUT4s than the no-reset build alone** (2,233 vs
1,805): it isn't the flush change. Technology-independent synthesis gives
*identical* cell counts with and without the narrower flush — 6,925 vs 6,925 on the
reset register file, 7,105 vs 7,105 on the no-reset one. So the change adds no logic.
The swings on ECP5 (−123 LUT4 on one register file, +428 on the other) are
LUT-mapping and packing variance in `synth_ecp5`, the area equivalent of Fmax
varying with the placement seed. Compare two builds to within a few hundred LUTs,
not exactly.

This build's register file is not reset, so its registers power up undefined, as
they do in many shipping cores. Its timing and area are measured. **Its functional
behaviour was not simulated**, because the directed test relies on the reset (4.3).
The control-only flush on its own *was* simulated and passes (5.2).

---

## 6. What limits this design, and the levers — ranked

| # | lever | effect | basis |
|---|---|---|---|
| 1 | **Synchronous memories** | Required, not optional. Without them the core cannot use block RAM or SRAM at any useful size. | MEASURED (4.4) |
| 2 | **Register file without reset** | Alone: −54% LUT, −66% FF, but −12% Fmax. With #3: **−43% LUT, −66% FF at unchanged Fmax.** | MEASURED (5.1, 5.3) |
| 3 | **Squash control bits only on flush/stall** | Reset fanout 286 → 38 flip-flops. Neutral alone; recovers the full 12% that #2 loses. | MEASURED (5.2, 5.3) |
| 4 | **Registered forwarding selects** | Takes the forwarding compare off the critical path. | ESTIMATED |
| 5 | **Branch prediction** | Attacks 25–35% of cycles in loops. | DERIVED (2.3) |
| 6 | **Load → store-data forwarding in MEM** | Removes the stall in `memcpy_naive`-style code. | MEASURED cost, 11% of cycles |

**Lever 1 — synchronous memories.** Block RAM and SRAM capture their address on a
clock edge and return data the next cycle. Keeping today's CPI means feeding
addresses one stage early:

- **IF:** address the instruction memory with `next_pc` rather than `if_pc`, so the
  instruction arrives exactly as IF/ID captures it. A stall must also hold the memory
  address.
- **MEM:** address data memory with `ex_alu_res` at the end of EX, so load data
  arrives during MEM. ECP5 block RAM provides byte-write enables in its 36-bit
  pseudo-dual-port mode (`PDPW16KD`), which map directly onto `SB`/`SH`.

Done naively — addressing with the MEM-stage register — every load gains a cycle and
the load-use penalty becomes 2.

**Lever 4 — registered forwarding selects.** Today `fwd_a`/`fwd_b` are computed in EX
by comparing `ex_rs1`/`ex_rs2` against `mem_rd`/`wb_rd`. All of those are known one
cycle earlier, so the comparison can move to ID and be registered into ID/EX. The EX
path then starts at a flip-flop driving the forwarding mux directly.

On the measured ECP5 path, segments 1–2 of section 3.3 (0.52 → 3.66 ns) account for
about 3.1 ns. Removing them bounds this path near 12 ns, roughly 83 MHz on speed
grade 6. **ESTIMATED:** the next-worst path is unknown until the change is built and
placed.

The combined build of 5.3 shows the companion problem. Its path starts at
`wb_Jump`, passing through the **writeback mux** before the forwarding mux. Choosing
the final writeback value at the end of MEM and registering it into MEM/WB takes
that mux out of the loop as well. Both changes are needed to shorten EX, since each
covers a path the other leaves in place.

**Lever 5 — branch prediction.** Resolving in EX makes every taken branch cost two
cycles. A small branch target buffer with 2-bit counters fetches the predicted target
in IF, so correct predictions cost nothing. With taken branches at 25–35% of loop
cycles, this is the largest CPI lever available. The resolution stage still sets the
mispredict penalty.

---

## 7. From core to product — gap analysis

What stands between this core and one you could ship, grouped by kind.

### Implementation

| gap | why it matters |
|---|---|
| Asynchronous memories | cannot map to block RAM or SRAM (4.4, lever 1) |
| Register file reset | 75% of LUTs (4.3) |
| No timing constraints | a product ships with an SDC/LPF clock constraint and closes timing against it, rather than reporting a failing Fmax |
| No bus interface | real memory has wait states. The core needs a ready/valid interface such as AXI4-Lite or Wishbone, and must stall on it. Today any wait state would add straight to CPI with no way to express it. |

### Architecture

| gap | why it matters |
|---|---|
| No Zicsr, no machine mode | no traps, interrupts, `mtvec`/`mepc`/`mcause`, or `mtime` — required to run most real firmware |
| No interrupts | a CLINT-style timer and software interrupt at minimum |
| No M extension | multiply and divide become software routines |
| No misalignment exceptions | misaligned stores are silently dropped rather than trapping |
| No debug | the RISC-V Debug Specification's JTAG debug module is what lets anyone else bring up software on it |

### Verification

| gap | why it matters |
|---|---|
| `riscv-tests` not run | the standard first bar for any RV32I claim |
| `riscv-arch-test` not run | the architectural compliance suite |
| No formal verification | RVFI + riscv-formal checks each instruction's semantics exhaustively. It finds the corner cases directed tests do not. |
| No coverage measurement | today's 46 assertions are directed; nobody has measured what they miss |

### Performance

| gap | why it matters |
|---|---|
| No branch prediction | largest CPI lever (lever 5) |
| No caches | irrelevant with zero-latency memory, essential once memory is external |

---

## 8. Scorecard

Current value against a product target, and how to measure the ones not yet
measured. Targets are grounded in measurements from this document where possible;
where they aren't, it says so.

| metric | now | product target | how to get there or measure it |
|---|---|---|---|
| CPI, typical code | ~1.38 (estimated) | ≤ 1.2 | branch prediction (lever 5). Measure with CoreMark once the toolchain exists. |
| Fmax, ECP5-6 | 64.6 MHz | ≥ 85 MHz | the speed-8 part already reaches ~87. On -6 it needs levers 3 and 4. |
| LUT4, ECP5 | 3,931 | ≤ ~2,250 at unchanged Fmax | the combined build reaches 2,233 at 65.0 MHz (5.3) |
| Flip-flops | 1,549 | ≤ ~550 | the combined build reaches 525 (5.3) |
| MIPS per 1k LUT | 11.9 | ≥ 20 | the combined build reaches 21.1 at full clock speed (5.3) |
| DMIPS/MHz | not measured | measure | Dhrystone 2.1, compiled with GCC; report the flags alongside the number |
| CoreMark/MHz | not measured | measure | CoreMark, same caveat |
| `riscv-tests` `rv32ui` | not run | 40 / 40 | see [`STATUS.md`](STATUS.md) step 3 |
| `riscv-arch-test` | not run | pass | after Zicsr |
| Formal (riscv-formal) | not run | pass | add an RVFI trace port |
| Interrupt latency | no interrupts | specified, bounded | after Zicsr + CLINT |
| Power | not measured | measure | vendor power estimator on a routed design, or OpenROAD for an ASIC |
| ASIC Fmax / area | not measured | measure | OpenLane on sky130 or gf180 |

---

## 9. Method and reproduction

Nothing in `rtl/` was modified. All instrumentation and variant builds were scratch
copies.

### 9.1 CPI

**Workloads** were generated by a Python script using `verif/asm.py`, with label
resolution for branch offsets. Each program fills any input data first, *outside* the
measurement window, then runs the kernel and ends in a `beq x0, x0, 0` self-loop.

**Pipelined probe.** A read-only testbench observes the core through hierarchy:

- A shadow valid bit mirrors ID/EX: `valid ← !stall && !flush && id_instr != 0`. An
  all-zero `id_instr` is a flushed bubble.
- EX never stalls, so every valid instruction occupies EX for exactly one cycle, and
  counting valid EX cycles counts retired instructions.
- The window runs from the kernel's first instruction reaching EX until the halt loop
  reaches EX. With no hazards, cycles equal instructions exactly, with no fill
  correction.
- It also counts `stall` cycles, `flush` events, and classifies each instruction as
  load, store, branch (taken or not), `jal`, `jalr`, or other.

**Cross-check.** The same programs run on `v1.0-singlecycle`, where CPI = 1, with the
same window. Instruction counts agreed in all nine cases.

### 9.2 Timing and area

**Synthesis copy.** The real `top_wire` has no functional outputs — its debug ports
are tied to zero — so a synthesiser would delete the entire core as unobservable. A
script copied `rtl/top.sv` to `core_synth`, replacing the `ROME` and `memory`
instances with ports: an instruction bus and a data bus. That is also how the core
would ship as IP, with memories as separate macros. `load_extend` stays inside the
core.

What that means for the numbers:

- **Memory access time is excluded.** The paths `imem_addr → imem_rdata` and
  `dmem_addr → dmem_rdata` are external. In a product they would be SRAM macro
  timing.
- **ECP5 was placed out-of-context** (`--out-of-context`): no I/O buffers and no
  global clock network. Timing is slightly pessimistic compared with a board build.
- **iCE40 was placed with its buses on pins**, and the clock promoted to a global
  buffer.

**Flows:**

```sh
# ECP5
yosys -p "read_verilog -sv <rtl files> core_synth.sv; synth_ecp5 -top core_synth -json core.json"
nextpnr-ecp5 --85k --speed 6 --seed N --out-of-context --json core.json \
             --freq 100 --timing-allow-fail

# iCE40
yosys -p "read_verilog -sv <rtl files> core_synth.sv; synth_ice40 -top core_synth -json core.json"
nextpnr-ice40 --hx8k --package ct256 --json core.json --freq 50 --timing-allow-fail

# technology-independent depth and area
yosys -p "read_verilog -sv <rtl files> core_synth.sv; synth -top core_synth; stat; \
          flatten; abc -g AND,NAND,OR,NOR,XOR,XNOR,ANDNOT,ORNOT,MUX; ltp -noff"
```

**Tool versions:**

| tool | version |
|---|---|
| Yosys | 0.69 (git sha1 9f75ca1f9), via `yowasp-yosys` 0.69.0.0.post1233 |
| nextpnr-ecp5 / nextpnr-ice40 | via `yowasp-nextpnr-*` 0.11.1.0.post826 |
| Icarus Verilog | 12.0 (devel) (s20150603-1539-g2693dd32b) |

YoWASP packages Yosys and nextpnr as WebAssembly, installable with `pip`. It was
installed into an isolated virtual environment for this analysis.

### 9.3 Not measured, and why

| item | reason |
|---|---|
| ASIC timing, area, power | no PDK or standard-cell library available |
| Power on FPGA | nextpnr does not estimate power |
| Dhrystone / CoreMark | needs the RISC-V GCC toolchain (not yet set up) |
| Timing with memories in the path | memories were hoisted to ports, since they would be SRAM macros in a product |
| iCE40 seed spread | single seed only |
| Functional simulation of the no-reset builds (5.1, 5.3) | the directed test relies on the register-file reset (4.3); their timing and area are measured |

### 9.4 Reproducing

The scripts behind every number here live in
[`verif/metrics/`](../verif/metrics/README.md):

```sh
cd verif/metrics
sh run_cpi.sh                                  # section 2        -> results/cpi.txt
sh run_synth.sh                                # sections 3 and 4 -> results/synth.txt
sh run_synth.sh narrow_flush noreset combo     # section 5 what-ifs
```

Synthesis needs Yosys and nextpnr. `pip install yowasp-yosys yowasp-nextpnr-ecp5
yowasp-nextpnr-ice40` works anywhere Python does.
