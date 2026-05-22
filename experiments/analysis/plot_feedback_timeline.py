#!/usr/bin/env python3
import argparse
import csv
import html
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="experiments/results/processed/feedback_timeline.csv")
    parser.add_argument("--output", default="experiments/results/figures/feedback_timeline.svg")
    return parser.parse_args()


def read_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty feedback input: {path}")
    return rows


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


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
    top = 60
    span = bottom - top
    max_delay = max(to_int(row["sched_queue_delay_us"]) for row in rows) or 1
    max_pages = max(to_int(row["pages_demoted_per_epoch"]) for row in rows) or 1
    slot = (width - 140) / len(rows)

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#fff"/>',
        text(28, 30, "Feedback timeline: queue delay, demotion, refault pressure", 16, "start"),
        f'<line x1="{left}" y1="{bottom}" x2="{width - 50}" y2="{bottom}" stroke="#222"/>',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{bottom}" stroke="#222"/>',
        text(28, top + 14, "queue delay", 11, "start"),
        text(width - 52, top + 14, "pages demoted", 11, "end"),
    ]

    points = []
    for idx, row in enumerate(rows):
        x = left + slot * idx + slot / 2
        delay = to_int(row["sched_queue_delay_us"])
        pages = to_int(row["pages_demoted_per_epoch"])
        y = bottom - (delay / max_delay) * span
        points.append(f"{x:.1f},{y:.1f}")
        bar_h = (pages / max_pages) * span
        parts.append(
            f'<rect x="{x - 16:.1f}" y="{bottom - bar_h:.1f}" width="32" height="{bar_h:.1f}" fill="#93c5fd"/>'
        )
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="5" fill="#b91c1c"/>')
        parts.append(text(x, bottom + 20, row["group"], 11))
        parts.append(text(x, y - 10, delay, 10))

    parts.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="#b91c1c" stroke-width="2"/>')
    parts.append(text(width - 54, height - 24, "red=line queue delay, blue bars=demoted pages", 11, "end"))
    parts.append("</svg>")
    Path(path).write_text("\n".join(parts) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    rows = read_rows(args.input)
    write_svg(rows, args.output)
    print(f"wrote feedback timeline figure: {args.output}")


if __name__ == "__main__":
    main()
