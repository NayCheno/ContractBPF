# Experiments

Experiment runners start from controlled QEMU validation and must never
fabricate results.

Raw logs, processed tables, and figures belong under `experiments/results/`, with large outputs ignored by git.

Current controlled evidence:

- `make qemu-conflict` records the synthetic scheduler+paging feedback scenario
  and guarded recovery markers in `artifacts/logs/`.
- `make qemu-recovery` parses the latest controlled QEMU conflict run into a
  recovery CSV and SVG figure under ignored result directories.
- `make experiments` builds the controlled synthetic workload, runs the G1-G9
  QEMU experiment matrix, copies the raw serial log into
  `experiments/results/raw/`, writes processed CSV tables, and generates the
  feedback, tail-latency, recovery, ablation, and overhead SVG figures.
- `make qemu-memcached` runs a real memcached service smoke test in QEMU.
  `experiments/analysis/parse_memcached.py` turns its serial log into
  `experiments/results/processed/memcached_smoke.csv`.

These are prototype correctness/reproducibility artifacts. They are not
production performance results. The memcached smoke test proves a real-service
path exists, but it is not yet integrated into the full G1-G9 matrix.
