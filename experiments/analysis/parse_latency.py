#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


FIELDS = [
    "group",
    "description",
    "p50_latency_us",
    "p99_latency_us",
    "p999_latency_us",
    "unaffected_tenant_p99_us",
    "throughput_ops_per_s",
]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="experiments/results/raw/matrix_latest.csv")
    parser.add_argument("--output", default="experiments/results/processed/latency_metrics.csv")
    return parser.parse_args()


def main():
    args = parse_args()
    with open(args.input, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty matrix input: {args.input}")

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in FIELDS})
    print(f"wrote latency metrics: {args.output}")


if __name__ == "__main__":
    main()
