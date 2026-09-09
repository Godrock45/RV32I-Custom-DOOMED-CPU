#!/bin/sh
# Build and run the short waveform demo, producing wave.vcd.
# Usage:  cd verif && sh run_wave.sh
#
# Note: rtl/ROM.sv is deliberately excluded -- ROM_demo.sv provides its own
# ROME module holding the demo program, and two definitions would collide.
set -e

python gen_demo.py

rm -f demo.vvp
iverilog -g2012 -o demo.vvp \
    ROM_demo.sv tb_wave.sv \
    ../rtl/ALU.sv ../rtl/PC.sv ../rtl/control.sv ../rtl/cmp.sv \
    ../rtl/data_mem.sv ../rtl/decoder.sv ../rtl/registers.sv \
    ../rtl/load_extend.sv ../rtl/forward.sv ../rtl/hazard.sv ../rtl/top.sv \
    2>&1 | grep -v "sorry:" || true

test -f demo.vvp || { echo "COMPILE FAILED"; exit 1; }

vvp demo.vvp
echo
echo "wave.vcd written -- open it in GTKWave, Surfer or VaporView"
