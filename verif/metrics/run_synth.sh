#!/bin/sh
# Synthesis and place-and-route -- docs/METRICS.md sections 3, 4 and 5.
#
# Usage:  cd verif/metrics && sh run_synth.sh [variant ...]    ->  results/synth.txt
#   variants:  baseline (default)  narrow_flush  noreset  combo
#   env:       SEEDS="1 2 3"  SPEED=6  YOSYS=...  NEXTPNR_ECP5=...  NEXTPNR_ICE40=...
#
# Every variant gets ECP5-85F place-and-route over SEEDS. The baseline also gets
# iCE40-HX8K place-and-route and a technology-independent logic-depth run.
#
# Needs Yosys and nextpnr. If they are not installed, this works anywhere Python does:
#   pip install yowasp-yosys yowasp-nextpnr-ecp5 yowasp-nextpnr-ice40
set -e
winpath() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }
HERE=$(winpath "$(dirname "$0")")
ROOT=$(winpath "$HERE/../..")
pick() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return; }; done; }
YOSYS=${YOSYS:-$(pick yosys yowasp-yosys)}
PNR5=${NEXTPNR_ECP5:-$(pick nextpnr-ecp5 yowasp-nextpnr-ecp5)}
PNR40=${NEXTPNR_ICE40:-$(pick nextpnr-ice40 yowasp-nextpnr-ice40)}
if [ -z "$YOSYS" ] || [ -z "$PNR5" ]; then
    echo "need yosys and nextpnr-ecp5 -- e.g.  pip install yowasp-yosys yowasp-nextpnr-ecp5 yowasp-nextpnr-ice40"
    exit 1
fi
SEEDS=${SEEDS:-"1 2 3"}
SPEED=${SPEED:-6}
[ $# -eq 0 ] && set -- baseline

OUT="$ROOT/results/synth.txt"
mkdir -p "$ROOT/results"
echo "# run_synth.sh  $(date '+%Y-%m-%d %H:%M')  ECP5 speed $SPEED, seeds: $SEEDS" >> "$OUT"
report() { echo "$1"; echo "$1" >> "$OUT"; }
fmax() { grep 'Max frequency' "$1" | tail -1 | sed -E 's/.*: ([0-9.]+) MHz.*/\1/'; }
count() { awk -v k="$2" '$2 == k { print $1; f = 1; exit } END { if (!f) print 0 }' "$1"; }

for v in "$@"; do
    D="$HERE/build/synth/$v"
    rm -rf "$D"
    python "$HERE/make_core.py" "$v" "$D" > /dev/null
    cd "$D"

    "$YOSYS" -q -l ecp5_yosys.log ecp5.ys
    F=""
    for s in $SEEDS; do
        "$PNR5" --85k --speed "$SPEED" --seed "$s" --out-of-context --json core_ecp5.json \
                --freq 100 --timing-allow-fail > "pnr_ecp5_seed$s.log" 2>&1
        F="$F $(fmax "pnr_ecp5_seed$s.log")"
    done
    report "$(printf '%-13s ECP5-85F-%s  LUT4=%-5s FF=%-5s LUTRAM=%-3s Fmax MHz:%s' \
        "$v" "$SPEED" "$(count stat_ecp5.txt LUT4)" "$(count stat_ecp5.txt TRELLIS_FF)" \
        "$(count stat_ecp5.txt TRELLIS_DPR16X4)" "$F")"

    if [ "$v" = baseline ]; then
        if [ -n "$PNR40" ]; then
            "$YOSYS" -q -l ice40_yosys.log ice40.ys
            "$PNR40" --hx8k --package ct256 --json core_ice40.json --freq 50 \
                     --timing-allow-fail > pnr_ice40.log 2>&1
            report "$(printf '%-13s iCE40-HX8K   LUT4=%-5s Fmax MHz: %s' \
                "$v" "$(count stat_ice40.txt SB_LUT4)" "$(fmax pnr_ice40.log)")"
        fi
        "$YOSYS" -q -l generic_yosys.log generic.ys
        report "$(printf '%-13s generic      logic depth: %s levels' \
            "$v" "$(grep -oE 'length=[0-9]+' ltp.txt | head -1 | cut -d= -f2)")"
    fi
    cd "$HERE"
done
echo "logs and netlists: $HERE/build/synth/<variant>/"
