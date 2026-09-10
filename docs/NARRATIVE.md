# The DOOMED CPU — A Design Narrative

This is the story of a 32-bit RISC-V processor built from scratch in SystemVerilog:
what it is, how it came to be shaped the way it is, what it measurably achieves, and
what still stands between it and a product. The companion documents hold the
reference detail — [`ARCHITECTURE.md`](ARCHITECTURE.md) for how the design works,
[`TESTPLAN.md`](TESTPLAN.md) for what the tests prove, [`METRICS.md`](METRICS.md) for
the measurements, and [`STATUS.md`](STATUS.md) for the roadmap. This document is the
connective tissue between them: the reasoning, in order, with the numbers attached.

---

## 1. The goal, and the shape of the project

The project has an unusually concrete ambition written into its name. The "DOOMED"
CPU is meant, eventually, to run DOOM. That goal is far rather than far-fetched —
people have run DOOM on homemade RISC-V soft cores, and the `doomgeneric` port exists
precisely so that a new platform only has to supply a framebuffer, a keyboard queue
and a millisecond timer. But almost everything DOOM needs is *not* the CPU: it needs
megabytes of memory, a memory-mapped display, input, a timer, the RISC-V M extension
for its fixed-point arithmetic, and enough throughput to be watchable. The processor
core is the part of that list that can be finished first, and the part everything
else depends on being correct.

So the project was ordered around a single principle: **prove each layer before
building on it.** First a single-cycle core that executes the base integer
instruction set. Then a test harness strong enough to be trusted. Then a pipeline,
brought up one hazard at a time. Then measurement — cycles per instruction, clock
frequency, critical path, area — so that decisions about what to improve next rest
on data rather than instinct. The toolchain, the official `riscv-tests` suite, a
memory map with peripherals, and a first game (Pac-Man, deliberately, before DOOM)
come after.

The instruction set is **RV32I**: the 32-bit base integer ISA. Its 37 computational
and control instructions are all implemented and verified. `FENCE` decodes as a
no-op, which is architecturally correct on a single-core, in-order machine with no
caches, since there is nothing to reorder. `ECALL` and `EBREAK` are not yet
implemented; they require control and status registers and trap handling, which
arrive with the toolchain work.

---

## 2. Reading the ISA before writing any RTL

The work began not with Verilog but with the specification. Every one of the 37
instructions was mapped against its encoding: where the opcode sits, which bits carry
`funct3` and `funct7`, and — the part that makes RISC-V decoding non-trivial — how the
immediate is scattered across the instruction word differently in each format.

RISC-V has six encoding formats, and the instruction set divides across them
unevenly: ten R-type register-register operations, fifteen I-type instructions
(immediate arithmetic, all five loads, and `JALR`), three S-type stores, six B-type
branches, two U-type instructions (`LUI` and `AUIPC`), and a single J-type jump,
`JAL`. The register fields and `funct3` sit in the same bit positions in every format
that has them, which is one of RISC-V's deliberate kindnesses to hardware designers.
The immediate is the opposite. A B-type branch splits its 13-bit offset across four
separate fields, with bit 0 implied to be zero and the sign bit at the top of the
word; a J-type jump scatters a 21-bit offset in a different pattern again. The
decoder's job is to reassemble each one.

Having that table on paper first meant that most of the datapath fell out of it. The
decoder became, quite literally, the table in RTL, and the rest of the design could be
reasoned about as "what does each instruction need computed, and where does the
result go."

---

## 3. The single-cycle core

### The datapath

The first core executes one instruction per clock cycle. A program counter addresses
an instruction ROM; the decoder splits the instruction into fields and reassembles the
immediate; a control unit turns the opcode into control signals; a 32-entry register
file supplies two operands; an ALU computes; a data memory is read or written; and a
writeback multiplexer chooses what returns to the register file. A separate comparator
evaluates branch conditions, and a next-PC multiplexer chooses where to fetch next.
The memories are **Harvard**: instruction and data memory are separate, which keeps
fetch and data access from ever contending.

Twelve modules make up the design as it stands today — the ALU, program counter,
instruction ROM, comparator, control unit, data memory, decoder, register file, and
the top level, joined later by a load-extension unit, a forwarding unit and a hazard
unit. The top level is deliberately kept to wiring, multiplexers and pipeline
registers; anything that makes a *decision* lives in its own module.

### Control as pure decode

The control unit takes exactly three inputs — `opcode`, `funct3` and `funct7` — and
produces nine outputs: `RegWrite`, `AluSrc` (operand B: immediate or register),
`AluSrcA` (operand A: PC or register), a four-bit `AluCtrl`, `MemRead`, `MemWrite`,
`MemToReg`, `Branch` and `Jump`. It never sees a datapath value. That constraint was
kept on purpose, and it paid off twice: it forced the branch comparator into its own
module (a comparison needs register values, which control must not see), and later it
meant the control unit needed **no changes at all** when the core was pipelined.

The ALU operation is encoded as `{funct7[5], funct3}` — four bits built directly from
the instruction, with no lookup table. For register-register operations, `funct7[5]`
is exactly the bit that distinguishes `SUB` from `ADD` and `SRA` from `SRL`, so the
encoding falls out uniformly. Every other instruction class forces `ADD`, because loads,
stores, branches, jumps, `LUI` and `AUIPC` all need an addition and nothing else.

### The decisions that made the design smaller

The most instructive thing about the single-cycle design is that it got *smaller* as
it was understood better. Several pieces of hardware were added and then removed once
their information turned out to exist already.

**The branch-target adder came in and went out.** Branches, `JAL` and `AUIPC` all need
`PC + immediate`. The obvious design gives that sum its own adder. But the ALU is idle
during a branch — the comparison is done by the separate comparator — so a single
select bit, `AluSrcA`, can steer the PC onto the ALU's first operand instead. The
dedicated adder was written, and then deleted. Only `PC + 4` keeps its own
incrementer, because `JAL` and `JALR` need the jump target *and* the return address in
the same cycle, and one adder cannot produce both. A careful enumeration afterwards
confirmed the decision holds across the whole ISA: no RV32I instruction ever needs two
ALU results at once, because RISC-V is a load-store architecture, branch comparison is
not an ALU operation here, and link addresses come from the incrementer. The shared
ALU costs nothing in correctness. What it does cost is an *option*: resolving branches
one stage earlier, in decode, would need an adder available in that stage. That is a
performance tradeoff for later, not a bug.

**`LUI` and `AUIPC` differ by exactly one bit.** `LUI` loads an immediate into the
upper bits of a register; `AUIPC` adds that immediate to the PC. Every control signal
is identical between them except `AluSrcA`. `AUIPC` puts the PC on the ALU's first
input; `LUI` puts register `rs1` there — and the decoder guarantees that `rs1` is
register zero for U-type instructions. Since `x0` is hardwired to zero, the ALU
computes `0 + immediate`, and `LUI` costs no dedicated hardware at all.

**The writeback selector dissolved into an existing signal.** Writeback needs to
choose between the ALU result, loaded data, and `PC + 4` for jump-and-link
instructions. The design went through a two-bit select, then a one-bit select, before
the observation that `Jump` is high for exactly `JAL` and `JALR` — precisely the two
instructions whose destination register receives `PC + 4`. So writeback became
"`MemToReg` selects load data, else `Jump` selects `PC + 4`, else the ALU result," with
no dedicated selector. The same `Jump` signal does double duty in the next-PC logic.

**Next-PC selection is a two-bit field.** `{Branch, Jump}` encodes four cases: `00`
for sequential fetch, `01` for `JAL` (jump to the ALU result, `PC + imm`), `10` for a
conditional branch (the ALU result if the comparator agrees, otherwise `PC + 4`), and
`11` for `JALR` (the ALU result, `rs1 + imm`, with bit 0 cleared). That last detail —
the `& ~1` — exists because I-type immediates, unlike B-type and J-type ones, do not
force the target's low bit to zero, and the specification requires it cleared. The
field must be decoded as a unit, never as two independent signals: an early comment in
the control unit records the trap of writing `taken = Branch & comparison`, which
would let the comparator fire on `JALR`.

### The decoder, and a debate worth having

The decoder does more than split fields. Where a format lacks a field, the decoder
deliberately leaves it at zero: `rs1` for U-type and J-type, `rd` for stores and
branches, and — crucially — `funct7` for every I-type instruction that is not a shift.

That last one is load-bearing. An `addi` with a negative immediate, such as
`addi x1, x0, -1`, has the immediate `0xFFF`, which sets instruction bit 30 — the bit
that `funct7[5]` reads. Without the zeroing, that `addi` would produce an `AluCtrl`
selecting subtraction, and compute `0 − (−1) = 1` instead of `0xFFFFFFFF`. The test
suite checks exactly this case. The zeroed `rs1` is equally load-bearing: it is what
makes `LUI` work through `x0`. And once the design was pipelined, zeroed register
fields gained a third purpose — the forwarding and hazard units compare register
indices, and a phantom index built from immediate bits could otherwise trigger a
forward or a stall for a register the instruction never referenced.

A reviewer suggested the opposite structure: a decoder that only splits fields, with
all opcode-dependent logic in the control unit. That is a legitimate and widely taught
design, and the suggestion was right that field *extraction* needs no knowledge of the
opcode. But the immediate cannot be format-blind, so the format decode has to live
somewhere, and moving it into control would have required a wider operand multiplexer
for `LUI`, a full ALU decoder, and — the decisive point — would have fused datapath
values into the control unit, breaking the property that let it pipeline unchanged.
The honest cost of the current structure is that the opcode is decoded twice, once in
each unit. That is a small, synthesis-shared duplication, and it was accepted.

### Memory: bytes, lanes and signs

RISC-V addresses memory in bytes, but the data memory stores 32-bit words. Everything
about sub-word access follows from that mismatch. A load reads a whole word and must
select the addressed byte or halfword and extend it — with its sign bit for `LB` and
`LH`, with zeros for `LBU` and `LHU`. A store must change only the addressed lane and
leave the other three bytes of the word intact, or it silently corrupts neighbouring
data.

The implementation uses SystemVerilog's indexed part-select, `vector[base +: width]`,
which selects a fixed-width slice starting at a runtime-computed bit position.
`mem_dat[8*addr[1:0] +: 8]` picks a byte; `mem_dat[16*addr[1] +: 16]` picks a
halfword. The same form, on the left-hand side of an assignment inside the memory,
writes only the addressed lane. It is worth knowing that a variable index is never
free in hardware: whether it is written as a shift, a part-select or a `case`
statement, it synthesises to the same multiplexer tree.

Misaligned halfword and word stores are guarded to do nothing rather than write the
wrong lanes. That is a placeholder: the specification calls for a misaligned-access
exception, which needs the trap machinery that does not exist yet.

The load-extension logic sits on the CPU side of the memory rather than inside it, and
was later split into its own module. Sign versus zero extension is a property of the
*instruction*, not of the storage; if it lived inside the memory, every future
peripheral on a memory map — framebuffer, timer, serial port — would have to
reimplement it identically.

### Bugs that taught something

Several bugs from this phase are worth recording because each generalises.

The first comparator had its signedness inverted. SystemVerilog's `logic` vectors are
unsigned by default, so a bare `<` is an unsigned comparison: the design had signed
casts on the unsigned branches and none on the signed ones, and `BGEU` used `>` where
it needed `>=`. A bug like this is invisible on non-negative data and only surfaces when
something compares against a negative number — which is why the test suite later
checks `−1 < 5` in both interpretations.

Several `always_comb` blocks were initially missing a default, which infers a latch:
combinational logic that must "hold" a value on some path has nowhere to hold it
except storage the tool invents. The control unit avoids this by assigning every
output a default before its `case` statement. The contrast with `always_ff` is useful
to remember: an incomplete `if` there is not a bug at all, but a clock enable.

And one bug was caught by the tests rather than by reading. An edit meant to enlarge
the data memory changed the *index expression* instead of the *array size*, producing
`memistan[addr[16383:2]]` — a bit-select far beyond a 32-bit address. The read index
became undefined, every load returned X, and stores continued to work perfectly
because they used a different index. The test suite flagged every load destination at
once, which pointed straight at the read path.

---

## 4. Verification: building the thing that proves it works

The first program the core ever ran was eight hand-assembled instructions: two
immediates, an add, a store, a load, a branch and a self-loop. It passed on the first
simulation. That was encouraging, and also nearly meaningless — a test that exercises
eight instructions says nothing about the other twenty-nine, and it could not even
distinguish a taken branch from a fall-through, because the skipped slot held a
`nop` that would have been silent either way.

What replaced it was a small verification system built from scratch in Python. An
**assembler**, `asm.py`, provides an encoder for each of the six instruction formats —
the mirror image of the decoder, which makes writing it an independent check on the
decode logic. A **generator**, `gen_test.py`, emits a test program *and* the expected
final state of the machine together: every instruction is written alongside the value
it should leave behind, so the program and its oracle cannot drift apart. A
**testbench** runs the program to completion and dumps every register and data-memory
word, and a **checker** compares the dump against the expectations and reports each
assertion as pass or fail.

Branches needed a specific trick to be testable. A branch that must be taken jumps
over a "poison" instruction that increments register `x28`; a branch that must *not*
be taken falls into a counter that increments `x9`. At the end, `x28` must be zero —
no poison ever executed — and `x9` must equal the number of not-taken tests. Both
directions of every branch type become observable, where the original hand test could
see neither.

The suite grew in layers. The first version checked 31 registers across 72
instructions. Seven instructions that had no register left to hold their result were
then routed through data memory, reaching 40 checks. Then came the edge cases that
quietly break homemade cores: `x0` must stay zero when written; shift amounts of 32 or
more must use only the low five bits; backward branches — negative B-type offsets, on
which every loop depends — must work; and `JALR` must clear bit 0 of its computed
target. That last one needed ingenuity, since a misaligned PC still fetches the same
word: the test lands the jump on an `AUIPC` instruction, which captures the actual PC
into a register, so a missing mask shows up as an odd value. The suite stood at 43
assertions for the single-cycle core, all passing, and that state was tagged
`v1.0-singlecycle`.

Two lessons from this phase shaped everything after it. The first was about the
harness itself: a build script piped the compiler through `grep` and then `|| true`,
so when a new source file was missing from its list, the compile failed silently and
the simulator ran a *stale binary* from an earlier build. For a while, every result
being read was fiction. The script now deletes the old binary before compiling and
refuses to continue if none is produced. The second lesson came during the pipeline
work, and it is the one worth carrying: **a test that has never failed has not been
shown to work.** Section 5 describes the false green that taught it.

---

## 5. From one cycle to five

### Why a pipeline, and why not multicycle

A single-cycle core's clock period must fit the slowest instruction end to end —
fetch, decode, register read, ALU, memory, writeback — in one cycle. A pipeline splits
that path into stages, so each instruction still takes five cycles from fetch to
retirement, but a new instruction starts every cycle. Latency is unchanged; throughput
approaches one instruction per cycle at a much shorter clock period.

The classic intermediate step, the *multicycle* design, was skipped deliberately. A
multicycle core keeps one instruction in the machine at a time and sequences it through
states with a finite-state machine; it saves hardware by reusing units across cycles,
but its performance is no better than single-cycle. It is a teaching step, not a
destination, and nothing ships it.

A pipeline, notably, has **no control FSM at all.** Every stage does the same thing
every cycle; there is no machine-wide "current state" to name, because at any instant
five different instructions occupy five different stages. Control becomes
*distributed*: the control unit decodes once, in the decode stage, and each
instruction's control signals then ride the pipeline registers alongside its data. The
bundle shrinks as it travels — the execute stage consumes the ALU controls, the memory
stage consumes the memory controls, and only the writeback controls reach the end.
Even the pipeline's stall and flush logic is combinational: a condition re-evaluated
every cycle, with no counter and no state.

### Structure

The five stages are instruction fetch, decode, execute, memory access and writeback,
separated by four pipeline registers. Every signal carries a stage prefix — `if_`,
`id_`, `ex_`, `mem_`, `wb_` — so that a signal used in the wrong stage is visible by
eye. That matters because the most dangerous class of pipeline bug is a control signal
taken from a different stage than the data it governs: a memory write enable taken from
decode while the address comes from the memory stage would write memory on behalf of an
instruction three stages away.

Before writing any pipeline RTL, the contents of each boundary were specified: which
data, which register indices and which control signals cross each one. Register
indices were carried from the start even though nothing consumed them yet, because the
forwarding unit would need them and retrofitting them would mean touching every
register again.

The register file is the one module that lives in two stages. It is read in decode and
written in writeback, four cycles later, by a different instruction. And that creates
the first hazard.

### The write-first register file

An instruction in decode reads the register file during the same cycle that an
instruction in writeback writes it — but the write lands at the clock edge that *ends*
the cycle, while the read is combinational *during* it. Without intervention, the
reader sees the old value. The fix is a bypass on the read ports: if the register being
read is the one being written this cycle, return the write data directly rather than the
array's contents. A guard excludes `x0`, because a write to `x0` is discarded and must
never be forwarded onto a read of it. This single mechanism resolves every read-after-
write dependency at a distance of three instructions, with no forwarding hardware at all.

### Forwarding

Dependencies at distances one and two need forwarding. At distance one, when a
consuming instruction reaches execute, its producer has only just moved to the memory
stage; the result exists, but only in the EX/MEM pipeline register. At distance two, the
producer is in writeback, and the result sits in MEM/WB. The forwarding unit compares
the source registers of the instruction in execute against the destinations held in
those two registers and steers the right value into the ALU.

Three conditions gate every forward: the producing instruction must actually write a
register, its destination must not be `x0`, and the indices must match. When both
stages match, the memory stage wins, because it holds the more recent write. That
priority is easy to invert and the inversion is silent in most programs, so the test
suite includes a case — two back-to-back writes to the same register followed by a
read — that detects it.

Two details were easy to get wrong. The value forwarded from writeback must be the
writeback multiplexer's output rather than the raw ALU result — otherwise a load would
forward its *address* and a jump-and-link its *target*. And the forwarded values must
feed not only the ALU but the branch comparator and the store-data path, because
`add x1, …` followed by `sw x1, 0(x4)` needs its store data forwarded just as an ALU
operand does.

### The load-use interlock

One dependency cannot be solved by forwarding. A load's data does not exist until the
memory stage completes, so an instruction that consumes a loaded value immediately
needs it before it exists anywhere in the machine. The hazard unit detects this — a load
in execute whose destination matches a source of the instruction in decode — and inserts
a single-cycle stall.

A stall is three coordinated actions: freeze the program counter, hold the IF/ID
register so the waiting instruction stays in decode, and inject a bubble into ID/EX so
nothing executes twice. Omitting any one produces a distinct and confusing failure: an
instruction that is fetched and discarded, one that is overwritten and never executes,
or one that executes twice. During the stall the pipeline effectively splits in half —
fetch and decode freeze while execute, memory and writeback keep draining, with the
bubble as the seam. One cycle is exactly enough: it turns the distance-one dependency
into a distance-two one, which forwarding already handles. The hazard unit compares one
stage earlier than the forwarding unit for a simple reason: forwarding can intervene
while an instruction is in execute, but a stall must catch it *before* it gets there.

### Branch flush

Branches resolve in execute. By then two more instructions have already been fetched
behind the branch. On a taken branch or any jump, those two are on the wrong path and
must be discarded: IF/ID and ID/EX are cleared, and the program counter is redirected.
The flush condition is written as a `case` over the same `{Branch, Jump}` field as the
next-PC multiplexer, so the two cannot drift apart. Only those two registers are
flushed; the instructions in the memory and writeback stages are older than the branch
and must complete.

### Bringing it up one hazard at a time

The pipeline was brought up with a single knob, `PAD`, which inserts that many `nop`
instructions after every real instruction in the test program, with every branch and
jump offset rescaled to match. A correct pipeline produces the same results at any
padding, so the same assertions apply throughout — and padding becomes a bisector. At
`PAD=4`, nothing overlaps and no hazard logic is needed at all, so a failure there
means the plumbing is wrong. At `PAD=2`, the write-first register file is exercised. At
`PAD=1`, branch flush and distance-two forwarding become necessary. At `PAD=0`,
everything is. The harness was checked at every padding level against the single-cycle
core first, so that a broken branch offset could never masquerade as a pipeline bug.

The bring-up followed the staircase exactly. Pipeline registers alone passed `PAD=4` and
`PAD=2`. `PAD=1` failed until flush was added — at which point the poison counter
proved taken branches correct while data-dependency checks still failed — and passed
once forwarding followed.

Then `PAD=0` passed, and it should not have, because the load-use interlock had not yet
been written. The test had no load immediately followed by a use of its result, so the
one hazard forwarding cannot solve was simply never exercised. A load-use case was added
and failed as expected; the interlock made it pass. A forwarding-priority case was added
too, and was verified by deliberately inverting the priority and watching it fail. Both
new tests were thereby shown to have teeth. The suite now stands at **46 assertions,
passing at every padding level**, and the pipelined core is tagged `v2.0-pipelined`.

Along the way the bring-up produced a catalogue of mistakes that are each typical of
first pipelines: the flush initially applied to all four pipeline registers (which would
delete older instructions, including a jump's own link write); the sequential next-PC
computed from the execute-stage PC instead of the fetch-stage PC (which would make the
program counter jump *backwards* on every cycle); blocking assignments inside
`always_ff` blocks (which collapse pipeline stages together); a pipeline register
written with `assign` instead of a clocked block (which is no register at all); and an
illegal literal, `32'b4`, where `32'd4` was meant. Every one was caught before it could
waste a debugging session, by reading the code against the boundary specification.

---

## 6. What the core achieves — measured

Once the pipeline passed, the next question was what it is actually worth: how many
cycles each instruction costs, how fast it can be clocked, what limits the clock, and
how much silicon it uses. Every number below was produced by a tool run against the
RTL, except where a number is explicitly called an estimate. The full method, and the
scripts that reproduce each figure, are in [`METRICS.md`](METRICS.md) and
`verif/metrics/`.

### Cycles per instruction

Eight microbenchmarks were written, each isolating one pipeline behaviour, and measured
alongside the directed test program. A read-only testbench probe counts retired
instructions, cycles, stalls and flushes inside a window that excludes setup code. The
measurements check themselves in three ways: every run satisfies
`cycles = instructions + stall_cycles + 2 × flushes` exactly; every instruction count
matches the single-cycle core running the same program, which by construction has a CPI
of exactly one; and every program's computed result is verified.

A chain of dependent ALU operations, each consuming its predecessor's result, runs at a
CPI of **1.000** — forwarding is complete, and no data hazard on an ALU result ever
costs a cycle. Loop kernels land between **1.17 and 1.59**. Call-heavy code, with a
jump and a return in every iteration, reaches **2.18**. The per-event costs are exact:
a load consumed immediately costs one cycle; a taken branch, a `JAL` or a `JALR` costs
two.

The measurements say two clear things. First, **taken branches dominate**, consuming 25
to 35 percent of all cycles in ordinary loops and more than half in call-heavy code;
that is the largest performance lever available, and a branch predictor is what would
pull it. Second, **the compiler matters as much as the hardware.** The same array-sum
algorithm runs at 1.588 written naively, 1.390 with its load hoisted one instruction
earlier, and 1.168 unrolled — so a CPI figure quoted without naming the compiler and its
flags is not a meaningful number. For typical compiled integer code, the measured
penalties combined with a plausible instruction mix suggest a CPI of roughly 1.3 to 1.5;
that range is an estimate until the toolchain exists to run a real benchmark.

The measurements also exposed one stall that need not exist. When a store's *data*
register is the value just loaded, the hazard unit stalls — but a store needs its data in
the memory stage, not in execute, by which point the load has finished. Forwarding load
data into the store-data path would remove a stall that costs 11 percent of cycles in a
naive copy loop.

### Clock frequency

To measure timing, the core was synthesised and placed and routed onto real FPGA
architectures using open-source tools. One preparation step was necessary and
instructive: the top level has no functional outputs — its debug ports are tied to zero
— so a synthesiser would correctly conclude that nothing in the design is observable and
delete all of it. The core was therefore synthesised with its two memories lifted out to
ports, which is also how a processor core ships as intellectual property, with memories
as separate macros.

On a Lattice ECP5-85F at its slowest speed grade, the core closes at **61.8 to 65.9 MHz**
across four placement seeds, a median of **64.6 MHz**. The fastest speed grade reaches
**85.6 to 89.3 MHz**. A small, low-cost Lattice iCE40-HX8K reaches **46.7 MHz**.
Combined with the measured CPI, typical code would retire roughly **43 to 50 million
instructions per second** on the slower ECP5.

### The critical path, and an unbalanced pipeline

The timing reports name the path that limits the clock, and it is the textbook limiter
of a classic five-stage pipeline. On the ECP5 it runs from a destination-register field
in the MEM/WB register, through the forwarding unit's comparison, through the
forwarding multiplexer, through the 32-bit branch comparator's carry chain, through the
branch decision and the next-PC multiplexer, into the program counter — 15.17
nanoseconds in total. It is the **branch-resolution loop in execute**: a branch decision
that depends on forwarded operands, and must reach the program counter within a single
cycle. The iCE40 is limited by the same family of path, ending instead in the ALU's
adder. In every critical path found, in every build, the head of the path is the
forwarding comparison.

Two further facts sharpen the picture. On both FPGAs, **68 to 73 percent of the critical
path is routing**, not logic: the design is bound by placement and fanout rather than by
the depth of its gates. And a technology-independent synthesis shows the longest path at
**76 gate levels**, with the execute stage about **three times deeper than decode** and
far deeper than every other stage. The pipeline is unbalanced: four stages spend most of
every cycle idle while execute sets the clock for all of them. Balancing it is where the
next substantial frequency gain lies.

### Area, and the register-file surprise

On the ECP5, the core uses **3,931 lookup tables and 1,549 flip-flops** — four and one
percent of the device. On the iCE40 it fills 56 percent of the logic. The breakdown by
module held the single largest surprise of the whole project: **the register file
accounts for 75 percent of the core's lookup tables.**

The cause is one loop. The register file resets all 32 registers to zero, and a reset
prevents the synthesiser from mapping the register file onto the FPGA's distributed RAM,
so it is built instead from 1,024 flip-flops and two full 32-to-1 read multiplexers.
Synthesised on its own, the register file costs 2,947 lookup tables with the reset and
182 without it. The RISC-V specification does not require general-purpose registers to
reset — only `x0` has a defined value — and many shipping cores leave them uninitialised.

The data memory revealed a related and more fundamental problem. Its read is
asynchronous: data appears combinationally as soon as the address changes. FPGA block
RAMs and ASIC SRAM macros are synchronous — they capture the address on a clock edge —
so an asynchronous memory cannot be built from them. A one-kilobyte data memory therefore
costs about a quarter of the core's lookup tables in multiplexers, and at the megabytes
DOOM requires, this form of memory could not be built at all. **Synchronous memories are
not an optimisation for this design; they are a prerequisite for any real one.**

### Three what-if builds: when area and timing disagree

The obvious response to the register-file finding is to remove the reset. That build was
synthesised and placed exactly like the baseline, and it halved the design: **54 percent
fewer lookup tables and 66 percent fewer flip-flops.** It was also, unexpectedly, **12
percent slower**, and consistently so across seeds, well outside the placement noise.
The critical path had moved. With the register file shrunk, the placer reorganised the
design, and the longest path now ended at the reset pins of the IF/ID register — driven
by the flush signal.

That pointed at a second issue. Flush and stall clear *every* bit of the IF/ID and ID/EX
registers: about 286 flip-flops, including 32-bit program counters, operands and
immediates. But a bubble only needs its side-effecting control bits cleared. With
register-write, memory-read, memory-write, branch and jump all zero, a bubble cannot
change architectural state, cannot trigger forwarding (gated by register-write), and
cannot trigger the load-use interlock (gated by memory-read) — so its data is dead. A
variant that clears only the instruction word and six control bits takes the fanout from
286 flip-flops to **38**. It passes all 46 assertions at every padding level with cycle
counts bit-identical to the baseline — a pure timing change. On the baseline alone it
made no measurable difference, which was expected: the baseline's critical path ends at
the program counter, not at the flush fanout.

The combination is where it mattered. The register file without reset, together with
the narrower flush, closes at a median of **65.0 MHz** — the baseline's speed — with
**43 percent fewer lookup tables and 66 percent fewer flip-flops**, delivering **1.77
times the baseline's performance per lookup table** at the same clock frequency. It is
the best build measured. The general lesson is that area and timing optimisations do not
compose automatically: an area improvement can move the critical path onto something
that was previously harmless, and the second change is needed to make the first one
pay.

---

## 7. Tradeoffs worth naming

Nearly every decision in the design traded one thing for another, and it is worth
stating each tradeoff plainly.

**A shared ALU against a dedicated branch adder.** Sharing saves hardware and costs no
correctness, but it ties branch-target computation to the execute stage, closing off
the option of resolving branches in decode — which would halve the taken-branch penalty
from two slots to one. That is a performance cost, deferred deliberately.

**Resolving branches in execute.** It is the simplest correct choice, and it makes
wrong-path stores structurally impossible — the wrong-path instructions are always in
fetch and decode, a full stage before any memory write. The price is a two-cycle penalty
on every taken branch, and a place on the critical path for the branch decision.

**Forwarding rather than stalling.** Forwarding keeps the CPI of dependent ALU code at
exactly one, but its comparison logic sits at the head of every critical path measured.
Registering the forwarding selects one cycle early — they depend only on values known in
decode — would take that comparison off the path. That is estimated, not yet measured,
at around three nanoseconds of the ECP5 path.

**A reset register file against area.** The reset makes simulation deterministic and the
directed test relies on it, but it costs three quarters of the core's logic. Removing it
is the right product decision, provided it is paired with the narrower flush and the test
initialises the registers it depends on.

**Flushing data against flushing control.** Clearing everything is the obvious bubble,
and it is correct. Clearing only side effects is equally correct, far cheaper in fanout,
and becomes important the moment the fanout is on the critical path.

**Asynchronous memories against a real product.** Combinational memories made the first
core simple — a load's data is available in the same cycle — but they cannot be built at
any useful size. Moving to synchronous memories without losing CPI means presenting
addresses one stage early: the fetch stage addresses instruction memory with the *next*
PC, and data memory is addressed with the execute stage's ALU result, so that data
arrives exactly when the memory stage needs it. Done naively, every load gains a cycle.

**Decoder zeroing against duplication.** Keeping format knowledge in the decoder makes
`LUI` free, prevents a negative immediate from selecting subtraction, and keeps phantom
indices out of the hazard logic; the price is decoding the opcode in two places.

---

## 8. What stands between this core and a product

The core is correct and measured, but it is not yet something that could ship. The gaps
fall into four groups.

**Implementation.** The memories must become synchronous. The register-file reset should
go, paired with the narrower flush. The design needs a real timing constraint to close
against, rather than a report of the frequency at which it fails. And it needs a memory
bus with a ready/valid handshake — AXI4-Lite or Wishbone — because real memory has wait
states, and today any wait state would add directly to CPI with no way for the pipeline to
express it.

**Architecture.** The core has no control and status registers and no machine mode, so it
cannot take a trap, service an interrupt, or keep time the way firmware expects. It needs
the M extension for multiplication and division, misaligned-access exceptions in place of
the silent no-op, and eventually a debug module following the RISC-V Debug Specification,
which is what lets anyone else bring software up on it.

**Verification.** Forty-six directed assertions are a strong start but only cover the
cases someone thought of. The official `riscv-tests` suite, the architectural compliance
suite, formal verification through an RVFI trace port and `riscv-formal`, and measured
coverage are each a step further, and each finds a class of bug the others miss.

**Performance.** A branch predictor addresses the largest measured cost. Caches become
essential the moment memory is external and slow; until then, with memories that answer
in zero cycles, a cache would only add logic to a path.

---

## 9. The road ahead

The immediate next step is the toolchain: a RISC-V GCC cross-compiler, a linker script
that places code at address zero, and a small converter from compiled binaries to the
memory image the simulation loads. Everything after it becomes easier, because there is
finally a compiler.

Alongside it comes `EBREAK` as a simulation halt. It is a small change with one subtlety
worth knowing in advance. `ECALL` and `EBREAK` share an opcode and a `funct3`, and differ
only in instruction bit 20 — which sits in the `rs2` field that the decoder zeroes for
I-type instructions, and which the control unit never sees. For a halt the distinction
does not matter; where it does, bit 0 of the reassembled immediate carries it. The halt
signal should ride the pipeline to writeback before stopping the machine, so that every
instruction older than the `EBREAK` has already retired — and a wrong-path `EBREAK` in the
shadow of a taken branch is then discarded by the flush for free.

Then the official `riscv-tests` suite, run against the pipeline with its pass and fail
macros redefined to store a result to an address the testbench watches, rather than
through the trap machinery the stock environment assumes. Then a memory map — RAM, ROM, a
framebuffer, keyboard input and a millisecond timer — which is the step that turns a CPU
core into a system-on-chip. Then Pac-Man: identical infrastructure to DOOM at a fraction
of the memory, and runnable without the M extension because the compiler emits software
multiplication for a plain RV32I target. If Pac-Man runs, the remaining distance to DOOM
is memory capacity and speed rather than architecture — the M extension, megabytes of
memory, and a faster simulator in Verilator.

---

## 10. Where everything lives

The repository is organised so that each question has one place to answer it. The
processor itself is the twelve modules in `rtl/`. The verification system — assembler,
test generator, checker, testbenches and run scripts — is in `verif/`, with the
measurement flows in `verif/metrics/`. Archived results, one pass/fail table per padding
level plus the CPI and synthesis results, are in `results/`. And the documentation, of
which this is one piece, is in `docs/`. The two tags mark the milestones: 
`v1.0-singlecycle` for the verified single-cycle core, and `v2.0-pipelined` for the
five-stage pipeline.

---

## Closing

The most useful thing this project demonstrates is not the instruction count. It is the
habit behind the design: asking, repeatedly, whether a piece of hardware is actually
needed — and deleting the adder, the selector and the signal whose information already
existed elsewhere; building the test before trusting the result, and then making each test
fail at least once to prove it can; and measuring before optimising, which is how the
register file turned out to be three quarters of the design, and how an obvious area fix
turned out to need a second change before it paid.

The core runs every instruction of the base integer set correctly, through a five-stage
pipeline that forwards, stalls and flushes as it should, at a measured 65 megahertz on a
mid-range FPGA. It is not yet a product, and it does not yet run DOOM. But every layer
that exists has been proven, and every number above can be regenerated from the
repository with a single command.
