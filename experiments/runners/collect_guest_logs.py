#!/usr/bin/env python3
import argparse
import pathlib
import shutil


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pattern", default="*-qemu-*.log")
    parser.add_argument("--logs", default="artifacts/logs")
    parser.add_argument("--output", default="experiments/results/raw")
    return parser.parse_args()


def main():
    args = parse_args()
    logs = pathlib.Path(args.logs)
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    copied = 0
    for path in sorted(logs.glob(args.pattern)):
        dst = output / path.name
        shutil.copy2(path, dst)
        copied += 1

    if copied == 0:
        raise SystemExit(f"no logs matched {logs / args.pattern}")
    print(f"copied {copied} guest log(s) to {output}")


if __name__ == "__main__":
    main()
