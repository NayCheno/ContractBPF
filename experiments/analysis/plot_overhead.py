#!/usr/bin/env python3
import argparse
import csv
import html
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="experiments/results/processed/overhead_table.csv")
    parser.add_argument("--output", default="experiments/results/figures/overhead.svg")
    return parser.parse_args()


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def read_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty overhead input: {path}")
    return rows


def text(x, y, value, size=12, anchor="middle"):
    return (
        f'<text x="{x}" y="{y}" font-family="monospace" font-size="{size}" '
        f'text-anchor="{anchor}" fill="#111">{html.escape(str(value))}</text>'
    )


def write_svg(rows, path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    width = 900
    height = 340
    left = 70
    zero = 245
    max_abs = max(abs(to_float(row["steady_state_overhead_pct"])) for row in rows) or 1.0
    slot = (width - 140) / len(rows)

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#fff"/>',
        text(28, 30, "Steady-state overhead vs G1 baseline", 16, "start"),
        f'<line x1="{left}" y1="{zero}" x2="{width - 40}" y2="{zero}" stroke="#222"/>',
        f'<line x1="{left}" y1="60" x2="{left}" y2="285" stroke="#222"/>',
        text(28, 74, "overhead %", 11, "start"),
    ]

    for idx, row in enumerate(rows):
        x = left + slot * idx + slot / 2
        overhead = to_float(row["steady_state_overhead_pct"])
        bar_h = abs(overhead) / max_abs * 155
        y = zero - bar_h if overhead >= 0 else zero
        color = "#dc2626" if overhead >= 0 else "#059669"
        parts.append(
            f'<rect x="{x - 18:.1f}" y="{y:.1f}" width="36" height="{bar_h:.1f}" fill="{color}"/>'
        )
        parts.append(text(x, zero + 20, row["group"], 11))
        parts.append(text(x, y - 8 if overhead >= 0 else y + bar_h + 14, f"{overhead:.1f}", 10))

    parts.append(text(width - 44, height - 24, "red=slower than G1, green=faster than G1", 11, "end"))
    parts.append("</svg>")
    Path(path).write_text("\n".join(parts) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    rows = read_rows(args.input)
    write_svg(rows, args.output)
    print(f"wrote overhead figure: {args.output}")


if __name__ == "__main__":
    main()
