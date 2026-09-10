#!/bin/sh
# CPI measurement -- docs/METRICS.md section 2.
#
# Runs every microbenchmark on the pipelined core in rtl/, and cross-checks each
# instruction count against the single-cycle core at tag v1.0-singlecycle
# (CPI = 1 there by construction, so its cycle count is an instruction count).
#
# Usage:  cd verif/metrics && sh run_cpi.sh        ->  results/cpi.txt
# Needs:  iverilog, python3, git
set -e
winpath() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }
HERE=$(winpath "$(dirname "$0")")
ROOT=$(winpath "$HERE/../..")
RTL="$ROOT/rtl"
B="$HERE/build/cpi"
rm -rf "$B"; mkdir -p "$B/sc"; cd "$B"

python "$HERE/bench.py" > /dev/null
for f in ALU.sv PC.sv control.sv cmp.sv data_mem.sv decoder.sv registers.sv top.sv; do
    git -C "$ROOT" show "v1.0-singlecycle:$f" > "sc/$f"
done

PIPE="$RTL/ALU.sv $RTL/PC.sv $RTL/control.sv $RTL/cmp.sv $RTL/data_mem.sv $RTL/decoder.sv \
      $RTL/registers.sv $RTL/load_extend.sv $RTL/forward.sv $RTL/hazard.sv $RTL/top.sv"
SC="sc/ALU.sv sc/PC.sv sc/control.sv sc/cmp.sv sc/data_mem.sv sc/decoder.sv sc/registers.sv sc/top.sv"

measure() {   # name rom start halt expected_s0 expected_dsum
    rm -f p.vvp s.vvp
    iverilog -g2012 -o p.vvp "$2" "$HERE/tb_perf.sv" $PIPE 2>&1 | grep -v "sorry:" || true
    iverilog -g2012 -o s.vvp "$2" "$HERE/tb_sc.sv"   $SC   2>&1 | grep -v "sorry:" || true
    P=$(vvp p.vvp +START=$3 +HALT=$4 | grep -E "^RESULT|TIMEOUT" || true)
    S=$(vvp s.vvp +START=$3 +HALT=$4 | grep -E "^SC|TIMEOUT" || true)
    echo "NAME=$1 ES0=$5 EDS=$6 | $P | $S" >> perf_results.txt
}

: > perf_results.txt
tr -d '\r' < manifest.txt | while read name start halt es0 eds; do
    measure "$name" "ROM_$name.sv" "$start" "$halt" "$es0" "$eds"
done

# the directed verification program from verif/, whole program as the window
H=$(PYTHONPATH="$ROOT/verif" PAD=0 python "$ROOT/verif/gen_test.py" | sed -n 's/.*(pc=0x\([0-9A-Fa-f]*\)).*/\1/p')
measure directed_test ROM_test.sv 0 $((0x$H)) -1 -1

mkdir -p "$ROOT/results"
python "$HERE/cpi_table.py" perf_results.txt | tee "$ROOT/results/cpi.txt"
