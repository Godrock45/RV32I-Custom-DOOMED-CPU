#!/usr/bin/env python3
"""Tabulate run_cpi.sh output and check every measurement is internally consistent.

Three checks per workload -- any failure makes the exit code non-zero:
  1. cycles == instructions + stall_cycles + 2 * flushes   (every bubble accounted for)
  2. instructions == the single-cycle core's count         (independent counter)
  3. the program computed the right answer                 (s0 / copied-block checksum)
"""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "perf_results.txt"
txt = open(path, newline="").read().replace("\r", "")
bad = []
rows = []
for line in txt.splitlines():
    m = re.match(r"NAME=(\S+) ES0=(\S+) EDS=(\S+) \| RESULT (.*?) \| SC (.*)$", line)
    if not m:
        bad.append(f"unparsed line: {line[:80]}"); continue
    name, es0, eds = m.group(1), int(m.group(2)), int(m.group(3))
    r = dict(x.split("=") for x in m.group(4).split())
    s = dict(x.split("=") for x in m.group(5).split())
    n, c, st, fl = int(r["n"]), int(r["cyc"]), int(r["stalls"]), int(r["flushes"])
    if c != n + st + 2 * fl:           bad.append(f"{name}: cycles {c} != {n} + {st} + 2*{fl}")
    if int(s["n"]) != n:               bad.append(f"{name}: pipelined n={n}, single-cycle n={s['n']}")
    if es0 != -1 and int(r["s0"]) != es0:   bad.append(f"{name}: s0={r['s0']}, expected {es0}")
    if eds != -1 and int(r["dsum"]) != eds: bad.append(f"{name}: dsum={r['dsum']}, expected {eds}")
    rows.append((name, n, c, st, fl))

print(f"{'workload':14s} {'instr':>5s} {'cycles':>6s} {'CPI':>6s} {'IPC':>5s} {'stall cyc':>9s} {'flush cyc':>9s}")
for name, n, c, st, fl in rows:
    print(f"{name:14s} {n:5d} {c:6d} {c/n:6.3f} {n/c:5.3f} {100*st/c:8.1f}% {100*2*fl/c:8.1f}%")
print()
if bad:
    print("CHECKS FAILED:"); [print("  " + b) for b in bad]; sys.exit(1)
print(f"{len(rows)} workloads: accounting identity, single-cycle cross-check and results all pass")
