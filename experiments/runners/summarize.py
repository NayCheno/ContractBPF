#!/usr/bin/env python3
import argparse
import csv


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="experiments/results/processed/matrix_summary.csv")
    return parser.parse_args()


def main():
    args = parse_args()
    with open(args.input, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty summary input: {args.input}")

    print("group,p99_latency_us,queue_delay_us,pages_demoted,demote_state,recovery_epochs")
    for row in rows:
        print(
            ",".join(
                [
                    row.get("group", ""),
                    row.get("p99_latency_us", ""),
                    row.get("sched_queue_delay_us", ""),
                    row.get("pages_demoted_per_epoch", ""),
                    row.get("demote_degrade_state", ""),
                    row.get("recovery_time_epochs", ""),
                ]
            )
        )


if __name__ == "__main__":
    main()
