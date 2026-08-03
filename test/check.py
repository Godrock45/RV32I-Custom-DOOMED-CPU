#!/usr/bin/env python3
"""Compare the simulator's register/memory dump against expected.txt."""
import sys

exp = {}
for line in open("expected.txt"):
    kind, k, v = line.split()
    exp[(kind, int(k))] = int(v, 16)

got = {}
for line in open("result.txt"):
    p = line.split()
    if len(p) == 3 and p[0] in ("REG", "MEM"):
        try:                                  # x/z bits -> leave undefined
            got[(p[0], int(p[1]))] = int(p[2], 16)
        except ValueError:
            got[(p[0], int(p[1]))] = p[2]     # keep the raw 'xxxxxxff' for the report

bad = 0
for key in sorted(exp, key=lambda t: (t[0], t[1])):
    kind, k = key
    g = got.get(key)
    ok = (g == exp[key])
    if not ok:
        bad += 1
    label = ("x%d" % k) if kind == "REG" else ("mem[%d]" % k)
    if g is None:      shown = "MISSING"
    elif isinstance(g, str): shown = g
    else:              shown = "%08x" % g
    print("%s %-8s exp=%08x got=%s" %
          ("PASS" if ok else "FAIL", label, exp[key], shown))

print("\nchecked %d values, %d failures" % (len(exp), bad))
sys.exit(1 if bad else 0)
