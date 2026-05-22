#!/usr/bin/env python3
import argparse
import pathlib
import subprocess

from matrixlib import (
    RAW_FIELDS,
    SUMMARY_FIELDS,
    copy_raw_log,
    load_configs,
    parse_matrix_log,
    repo_root,
    summarize_groups,
    write_csv,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="experiments/configs")
    parser.add_argument("--log", help="Reuse an existing qemu memcached matrix log")
    return parser.parse_args()


def latest_log(root: pathlib.Path) -> pathlib.Path:
    logs = sorted((root / "artifacts/logs").glob("*-qemu-memcached-matrix.log"))
    if not logs:
        raise SystemExit("no memcached matrix log found")
    return logs[-1]


def run_qemu(root: pathlib.Path) -> pathlib.Path:
    subprocess.run([str(root / "qemu/run/run-memcached-matrix.sh")], cwd=root, check=True)
    return latest_log(root)


def main() -> int:
    args = parse_args()
    root = repo_root()
    config_dir = pathlib.Path(args.config)
    if not config_dir.is_absolute():
        config_dir = root / config_dir

    configs = load_configs(config_dir)
    for config in configs.values():
        config["workload"] = "memcached"
        config["evidence_scope"] = "qemu_memcached_ioctl_controlled"

    log_path = pathlib.Path(args.log) if args.log else run_qemu(root)
    if not log_path.is_absolute():
        log_path = root / log_path

    raw_dir = root / "experiments/results/raw"
    processed_dir = root / "experiments/results/processed"
    raw_log = copy_raw_log(log_path, raw_dir)
    rows = summarize_groups(parse_matrix_log(log_path), configs)

    raw_csv = raw_dir / "memcached_matrix_latest.csv"
    processed_csv = processed_dir / "memcached_matrix_summary.csv"
    write_csv(raw_csv, rows, RAW_FIELDS)
    write_csv(processed_csv, rows, SUMMARY_FIELDS)
    write_csv(processed_dir / "memcached_tail_latency_table.csv", rows, [
        "group",
        "description",
        "p50_latency_us",
        "p99_latency_us",
        "p999_latency_us",
        "unaffected_tenant_p99_us",
    ])
    write_csv(processed_dir / "memcached_feedback_table.csv", rows, [
        "group",
        "description",
        "sched_queue_delay_us",
        "pages_demoted_per_epoch",
        "refault_events",
        "demote_degrade_state",
    ])

    print(f"raw log: {raw_log}")
    print(f"raw memcached matrix: {raw_csv}")
    print(f"processed memcached summary: {processed_csv}")
    print("CONTRACTBPF_MEMCACHED_EXPERIMENTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
