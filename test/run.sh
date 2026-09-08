#!/bin/sh
# Build the directed test, run it, compare registers against expectations.
# Usage:  cd test && sh run.sh          (PAD=4 sh run.sh for nop-padded)
set -e

python gen_test.py

rm -f check.vvp                      # never silently run a stale binary
iverilog -g2012 -o check.vvp \
    ROM_test.sv tb_check.sv \
    ../ALU.sv ../PC.sv ../control.sv ../cmp.sv \
    ../data_mem.sv ../decoder.sv ../registers.sv \
    ../load_extend.sv ../top.sv \
    2>&1 | grep -v "sorry:" || true

test -f check.vvp || { echo "COMPILE FAILED"; exit 1; }

vvp check.vvp > result.txt
python check.py
