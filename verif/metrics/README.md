# metrics — the scripts behind `docs/METRICS.md`

Every number in [`docs/METRICS.md`](../../docs/METRICS.md) comes from here.
Nothing in `rtl/` is ever modified: variants are generated as copies.

```sh
cd verif/metrics
sh run_cpi.sh                                  # CPI            -> results/cpi.txt
sh run_synth.sh                                # Fmax and area  -> results/synth.txt
sh run_synth.sh narrow_flush noreset combo     # the what-if builds (METRICS.md §5)
```

`run_cpi.sh` takes seconds. `run_synth.sh` takes several minutes per variant, since
each one is placed and routed once per seed.

## Requirements

| for | needs |
|---|---|
| `run_cpi.sh` | `iverilog`, `python3`, `git` (it reads the `v1.0-singlecycle` tag) |
| `run_synth.sh` | Yosys and nextpnr. If not installed: `pip install yowasp-yosys yowasp-nextpnr-ecp5 yowasp-nextpnr-ice40` |

`run_synth.sh` finds `yosys`/`nextpnr-*` on `PATH`, falling back to the `yowasp-*`
wrappers. Override with `YOSYS=...`, `NEXTPNR_ECP5=...`, `NEXTPNR_ICE40=...`. Tune with
`SEEDS="1 2 3 4"` and `SPEED=8`.

## Files

| file | role |
|---|---|
| `bench.py` | the eight CPI microbenchmarks. Writes ROM images plus a manifest of measurement windows and expected results. |
| `tb_perf.sv` | read-only probe for the pipelined core: counts retired instructions, cycles, stalls, flushes, and instruction classes |
| `tb_sc.sv` | the same window on the single-cycle core, as an independent instruction count |
| `cpi_table.py` | tabulates results. Fails unless every run passes all three checks: the accounting identity, the single-cycle cross-check, and a correct computed result. |
| `run_cpi.sh` | the CPI flow |
| `make_core.py` | stages one variant: `baseline`, `narrow_flush`, `noreset`, `combo` |
| `ecp5.ys`, `ice40.ys`, `generic.ys` | Yosys scripts, run inside a staged directory |
| `run_synth.sh` | the synthesis and place-and-route flow |

Everything generated lands in `build/`, which is gitignored.

## Checking a variant still works

`make_core.py` also writes `top_sim.sv`, the full core for that variant, so it can go
straight through the directed suite:

```sh
python make_core.py narrow_flush build/nf
cd build/nf
PYTHONPATH=../../.. PAD=0 python ../../../gen_test.py
iverilog -g2012 -o t.vvp ROM_test.sv ../../../tb_check.sv top_sim.sv \
    ../../../../rtl/ALU.sv ../../../../rtl/PC.sv ../../../../rtl/control.sv \
    ../../../../rtl/cmp.sv ../../../../rtl/data_mem.sv ../../../../rtl/decoder.sv \
    ../../../../rtl/registers.sv ../../../../rtl/load_extend.sv \
    ../../../../rtl/forward.sv ../../../../rtl/hazard.sv
vvp t.vvp > result.txt && python ../../../check.py
```

The `noreset` and `combo` variants will fail that check, and that's expected: the
directed test never initialises `x28`, so it relies on the register file resetting
to zero. See METRICS.md §4.3.

## Caveats carried into the numbers

- Memories are hoisted to ports, so memory access time is not in any path.
- ECP5 is placed out-of-context: no I/O buffers and no global clock network.
- Fmax varies about 6% between seeds. Compare medians, not single runs.
- LUT counts vary by a few hundred between builds from mapping alone (METRICS.md §5.3).
