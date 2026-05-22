#!/usr/bin/env python3
import argparse
import pathlib
import sys

from matrixlib import SUMMARY_FIELDS, load_configs, parse_matrix_log, repo_root, run_qemu_matrix, summarize_groups, write_csv


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("--log", help="Reuse an existing qemu experiment matrix log")
    parser.add_argument("--config-dir", default="experiments/configs")
    parser.add_argument("--output", help="Write the selected group summary CSV")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()
    config_path = pathlib.Path(args.config)
    if not config_path.is_absolute():
        config_path = root / config_path

    config_dir = pathlib.Path(args.config_dir)
    if not config_dir.is_absolute():
        config_dir = root / config_dir

    configs = load_configs(config_dir)
    requested = None
    for group, data in configs.items():
        if config_path.resolve() == (config_dir / f"{group.lower()}_{data.get('control_mode', '')}.yaml").resolve():
            requested = group
            break
    if requested is None:
        stem = config_path.stem
        requested = stem.split("_", 1)[0].upper()
    if requested not in configs:
        raise SystemExit(f"unknown experiment group for config: {config_path}")

    log_path = pathlib.Path(args.log) if args.log else run_qemu_matrix(root)
    if not log_path.is_absolute():
        log_path = root / log_path

    rows = summarize_groups(parse_matrix_log(log_path), configs)
    selected = [row for row in rows if row["group"] == requested]
    if not selected:
        raise SystemExit(f"group {requested} not found in {log_path}")

    if args.output:
        output = pathlib.Path(args.output)
        if not output.is_absolute():
            output = root / output
        write_csv(output, selected, SUMMARY_FIELDS)
    else:
        writer = sys.stdout
        writer.write(",".join(SUMMARY_FIELDS) + "\n")
        writer.write(",".join(selected[0].get(field, "") for field in SUMMARY_FIELDS) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
