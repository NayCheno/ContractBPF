#!/usr/bin/env python3
import argparse
import csv
import html
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="experiments/results/processed/ablation_table.csv")
    parser.add_argument("--output", default="experiments/results/figures/ablation.svg")
    return parser.parse_args()


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def read_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty ablation input: {path}")
    return rows


def text(x, y, value, size=12, anchor="middle"):
    return (
        f'<text x="{x}" y="{y}" font-family="monospace" font-size="{size}" '
        f'text-anchor="{anchor}" fill="#111">{html.escape(str(value))}</text>'
    )


def write_svg(rows, path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    width = 900
    height = 360
    left = 70
    bottom = 285
    max_latency = max(to_int(row["p99_latency_us"]) for row in rows) or 1
    max_recovery = max(to_int(row["recovery_time_epochs"]) for row in rows) or 1
    slot = (width - 140) / len(rows)

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#fff"/>',
        text(28, 30, "Ablation: latency and recovery effect by group", 16, "start"),
        f'<line x1="{left}" y1="{bottom}" x2="{width - 40}" y2="{bottom}" stroke="#222"/>',
        f'<line x1="{left}" y1="60" x2="{left}" y2="{bottom}" stroke="#222"/>',
        text(28, 74, "P99 us", 11, "start"),
    ]

    for idx, row in enumerate(rows):
        x = left + slot * idx + slot / 2
        latency = to_int(row["p99_latency_us"])
        recovery = to_int(row["recovery_time_epochs"])
        bar_h = latency / max_latency * 180
        radius = 5 + recovery / max_recovery * 9
        parts.append(
            f'<rect x="{x - 17:.1f}" y="{bottom - bar_h:.1f}" width="34" height="{bar_h:.1f}" fill="#7c3aed"/>'
        )
        parts.append(f'<circle cx="{x + 30:.1f}" cy="{bottom - bar_h:.1f}" r="{radius:.1f}" fill="#f59e0b"/>')
        parts.append(text(x, bottom + 20, row["group"], 11))
        parts.append(text(x, bottom - bar_h - 10, latency, 10))

    parts.append(text(width - 44, height - 24, "purple=P99 latency, orange=recovery epochs", 11, "end"))
    parts.append("</svg>")
    Path(path).write_text("\n".join(parts) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    rows = read_rows(args.input)
    write_svg(rows, args.output)
    print(f"wrote ablation figure: {args.output}")


if __name__ == "__main__":
    main()
