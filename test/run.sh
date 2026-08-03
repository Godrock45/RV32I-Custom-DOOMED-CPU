#!/bin/sh
# Build the directed test, run it, compare registers against expectations.
# Usage:  cd test && sh run.sh
set -e

python gen_test.py

iverilog -g2012 -o check.vvp \
    ROM_test.sv tb_check.sv \
    ../ALU.sv ../PC.sv ../control.sv ../cmp.sv \
    ../data_mem.sv ../decoder.sv ../registers.sv ../top.sv \
    2>&1 | grep -v "sorry:" || true

vvp check.vvp > result.txt
python check.py
