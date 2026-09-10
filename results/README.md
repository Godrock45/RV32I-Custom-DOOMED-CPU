# Test Results

Archived output from `verif/run.sh`, one file per padding level.

Regenerate with:

```sh
cd verif
for p in 0 1 2 4; do PAD=$p sh run.sh; done
```

Each run writes `results/pass_fail_pad<N>.txt`.

---

## Current status

| file | padding | result |
|---|---|---|
| `pass_fail_pad0.txt` | none — instructions back to back | **46 / 46** |
| `pass_fail_pad1.txt` | 1 nop between | **46 / 46** |
| `pass_fail_pad2.txt` | 2 nops between | **46 / 46** |
| `pass_fail_pad4.txt` | 4 nops — nothing overlaps | **46 / 46** |

---

## Why four levels

`PAD=N` inserts N `nop`s after every instruction, with branch and jump offsets
scaled to match. A correct pipeline produces identical results at every level,
so the same 46 assertions apply throughout — which turns padding into a
bisector for pipeline bugs.

| level | passing requires |
|---|---|
| `PAD=4` | pipeline registers only. No forwarding, flush or stall needed — nothing overlaps. |
| `PAD=2` | + write-first register file (RAW at distance 3) |
| `PAD=1` | + branch flush, + MEM/WB→EX forwarding |
| `PAD=0` | + EX/MEM→EX forwarding, + load-use interlock |

Reading a failure:

- `PAD=4` fails → the pipeline **plumbing** is wrong
- `PAD=4` passes, `PAD=0` fails → plumbing is fine, it is a **hazard** problem
- `PAD=2` passes, `PAD=1` fails → distance-2 forwarding or the second flush slot

This is how the pipeline was brought up: `PAD=4` first with no hazard logic at
all, then flush, then forwarding, then the interlock, each step validated by the
next level down.

---

## What the assertions mean

See [`../docs/TESTPLAN.md`](../docs/TESTPLAN.md) for the row-by-row mapping —
which register or memory word proves which piece of functionality, and what is
deliberately not covered.

---

## Metrics

| file | produced by | contents |
|---|---|---|
| `cpi.txt` | `verif/metrics/run_cpi.sh` | CPI, IPC and hazard breakdown for nine workloads, plus the three consistency checks |
| `synth.txt` | `verif/metrics/run_synth.sh` | ECP5 and iCE40 Fmax and area per build. One line per run, under a dated header. |

What these numbers mean, and how they were measured:
[`../docs/METRICS.md`](../docs/METRICS.md).
