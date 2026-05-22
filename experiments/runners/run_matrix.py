#!/usr/bin/env python3
import argparse
import pathlib

from matrixlib import (
    RAW_FIELDS,
    SUMMARY_FIELDS,
    copy_raw_log,
    load_configs,
    parse_matrix_log,
    repo_root,
    run_plot_scripts,
    run_qemu_matrix,
    summarize_groups,
    write_csv,
    write_derived_tables,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="experiments/configs")
    parser.add_argument("--log", help="Reuse an existing qemu experiment matrix log")
    parser.add_argument("--no-plots", action="store_true", help="Only write raw and processed CSVs")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()
    config_dir = pathlib.Path(args.config)
    if not config_dir.is_absolute():
        config_dir = root / config_dir

    configs = load_configs(config_dir)
    log_path = pathlib.Path(args.log) if args.log else run_qemu_matrix(root)
    if not log_path.is_absolute():
        log_path = root / log_path

    raw_dir = root / "experiments/results/raw"
    processed_dir = root / "experiments/results/processed"
    raw_log = copy_raw_log(log_path, raw_dir)

    parsed = parse_matrix_log(log_path)
    rows = summarize_groups(parsed, configs)

    raw_csv = raw_dir / "matrix_latest.csv"
    processed_csv = processed_dir / "matrix_summary.csv"
    write_csv(raw_csv, rows, RAW_FIELDS)
    write_csv(processed_csv, rows, SUMMARY_FIELDS)
    write_derived_tables(root, rows)

    if not args.no_plots:
        run_plot_scripts(root)

    print(f"raw log: {raw_log}")
    print(f"raw matrix: {raw_csv}")
    print(f"processed summary: {processed_csv}")
    print("CONTRACTBPF_EXPERIMENTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
