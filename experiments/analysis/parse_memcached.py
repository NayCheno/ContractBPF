#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path


def latest_log():
    logs = sorted(Path("artifacts/logs").glob("*-qemu-memcached.log"))
    if not logs:
        raise SystemExit("no qemu memcached log found")
    return logs[-1]


def percentile(samples, pct):
    if not samples:
        return 0
    values = sorted(samples)
    index = max(0, math.ceil((pct / 100.0) * len(values)) - 1)
    return values[min(index, len(values) - 1)]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="qemu memcached serial log")
    parser.add_argument("--output", default="experiments/results/processed/memcached_smoke.csv")
    return parser.parse_args()


def main():
    args = parse_args()
    log = Path(args.input) if args.input else latest_log()
    samples = []
    markers = set()

    for raw in log.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("LATENCY_SAMPLE_US="):
            try:
                samples.append(int(line.split("=", 1)[1]))
            except ValueError:
                pass
        if line in {"CONTRACTBPF_BOOT_OK", "MEMCACHED_LOAD_OK", "CONTRACTBPF_MEMCACHED_OK"}:
            markers.add(line)

    required = {"CONTRACTBPF_BOOT_OK", "MEMCACHED_LOAD_OK", "CONTRACTBPF_MEMCACHED_OK"}
    missing = sorted(required - markers)
    if missing:
        raise SystemExit(f"missing markers in {log}: {', '.join(missing)}")
    if not samples:
        raise SystemExit(f"no memcached latency samples in {log}")

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "workload",
                "samples",
                "p50_latency_us",
                "p99_latency_us",
                "max_latency_us",
                "raw_log",
            ],
        )
        writer.writeheader()
        writer.writerow(
            {
                "workload": "memcached",
                "samples": len(samples),
                "p50_latency_us": percentile(samples, 50),
                "p99_latency_us": percentile(samples, 99),
                "max_latency_us": max(samples),
                "raw_log": str(log),
            }
        )
    print(f"wrote memcached smoke metrics: {args.output}")


if __name__ == "__main__":
    main()
