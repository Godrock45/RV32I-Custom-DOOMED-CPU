#!/bin/sh
# Build the directed test, run it, compare registers against expectations.
# Usage:  cd verif && sh run.sh         (PAD=4 sh run.sh for nop-padded)
set -e

python gen_test.py

rm -f check.vvp                      # never silently run a stale binary
iverilog -g2012 -o check.vvp \
    ROM_test.sv tb_check.sv \
    ../rtl/ALU.sv ../rtl/PC.sv ../rtl/control.sv ../rtl/cmp.sv \
    ../rtl/data_mem.sv ../rtl/decoder.sv ../rtl/registers.sv \
    ../rtl/load_extend.sv ../rtl/forward.sv ../rtl/hazard.sv ../rtl/top.sv \
    2>&1 | grep -v "sorry:" || true

test -f check.vvp || { echo "COMPILE FAILED"; exit 1; }

vvp check.vvp > result.txt

mkdir -p ../results
python check.py | tee "../results/pass_fail_pad${PAD:-0}.txt"
