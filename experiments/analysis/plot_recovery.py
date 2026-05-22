#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        default="experiments/results/raw/recovery_latest.csv",
        help="Recovery CSV produced by qemu/run/run-recovery.sh",
    )
    parser.add_argument(
        "--processed",
        default="experiments/results/processed/recovery_table.csv",
        help="Processed table output path",
    )
    parser.add_argument(
        "--output",
        default="experiments/results/figures/recovery.svg",
        help="SVG figure output path",
    )
    return parser.parse_args()


def read_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"empty recovery input: {path}")
    return rows


def write_processed(rows, path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "epoch",
        "mode",
        "sched_queue_delay_us",
        "pages_demoted",
        "refault_events",
        "sched_degrade_state",
        "demote_degrade_state",
        "recovered",
    ]
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})


def bar(x, y, width, height, fill):
    return f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{fill}"/>'


def text(x, y, value, size=12, anchor="middle"):
    return (
        f'<text x="{x}" y="{y}" font-family="monospace" font-size="{size}" '
        f'text-anchor="{anchor}" fill="#111">{value}</text>'
    )


def write_svg(rows, path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)

    width = 720
    height = 320
    chart_bottom = 250
    max_delay = max(int(row["sched_queue_delay_us"]) for row in rows) or 1
    max_state = max(int(row["demote_degrade_state"]) for row in rows) or 1
    colors = {"unguarded": "#b91c1c", "guarded": "#047857"}

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#fff"/>',
        text(28, 28, "ContractBPF controlled recovery timeline", 16, "start"),
        '<line x1="60" y1="250" x2="660" y2="250" stroke="#222"/>',
        '<line x1="60" y1="70" x2="60" y2="250" stroke="#222"/>',
        text(60, 275, "epoch", 12, "middle"),
        text(28, 84, "queue delay", 11, "start"),
    ]

    slot = 240
    bar_width = 84
    for idx, row in enumerate(rows):
        mode = row["mode"]
        delay = int(row["sched_queue_delay_us"])
        degrade = int(row["demote_degrade_state"])
        x = 130 + idx * slot
        bar_height = int((delay / max_delay) * 150)
        parts.append(bar(x, chart_bottom - bar_height, bar_width, bar_height, colors.get(mode, "#334155")))
        parts.append(text(x + bar_width / 2, chart_bottom + 20, f'{row["epoch"]}:{mode}', 12))
        parts.append(text(x + bar_width / 2, chart_bottom - bar_height - 8, str(delay), 12))

        state_y = chart_bottom - int((degrade / max_state) * 150)
        parts.append(f'<circle cx="{x + 150}" cy="{state_y}" r="8" fill="#1d4ed8"/>')
        parts.append(text(x + 150, state_y - 14, f'demote state {degrade}', 11))

    parts.extend(
        [
            text(630, 84, "red=unguarded, green=guarded", 11, "end"),
            text(630, 104, "blue point=demote degrade state", 11, "end"),
            "</svg>",
        ]
    )

    Path(path).write_text("\n".join(parts) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    rows = read_rows(args.input)
    write_processed(rows, args.processed)
    write_svg(rows, args.output)
    print(f"wrote processed recovery table: {args.processed}")
    print(f"wrote recovery figure: {args.output}")


if __name__ == "__main__":
    main()
