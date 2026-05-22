#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$ROOT/artifacts/logs"
TRACE_DIR="$ROOT/artifacts/traces"
RAW_DIR="$ROOT/experiments/results/raw"
PROCESSED_DIR="$ROOT/experiments/results/processed"
FIG_DIR="$ROOT/experiments/results/figures"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/${STAMP}-qemu-recovery.log"
CSV="$TRACE_DIR/${STAMP}-recovery.csv"
LATEST_RAW="$RAW_DIR/recovery_latest.csv"
PROCESSED="$PROCESSED_DIR/recovery_table.csv"
FIGURE="$FIG_DIR/recovery.svg"

mkdir -p "$LOG_DIR" "$TRACE_DIR" "$RAW_DIR" "$PROCESSED_DIR" "$FIG_DIR"

{
    printf 'Command: %q\n' "$ROOT/qemu/run/run-conflict.sh"
    printf 'Started: %s\n' "$STAMP"
} > "$LOG"

"$ROOT/qemu/run/run-conflict.sh" | tee -a "$LOG"

CONFLICT_LOG="$(ls -1t "$LOG_DIR"/*-qemu-conflict.log | head -n 1)"
printf 'Conflict log: %s\n' "$CONFLICT_LOG" | tee -a "$LOG"

python3 - "$CONFLICT_LOG" "$CSV" <<'PY'
import csv
import re
import sys

log_path, csv_path = sys.argv[1], sys.argv[2]

snapshots = {}
current = None

with open(log_path, encoding="utf-8", errors="replace") as f:
    for raw in f:
        line = raw.strip()
        if line == "CONTRACTBPF_UNGUARDED_SNAPSHOT_BEGIN":
            current = "unguarded"
            snapshots[current] = {}
            continue
        if line == "CONTRACTBPF_GUARDED_SNAPSHOT_BEGIN":
            current = "guarded"
            snapshots[current] = {}
            continue
        if line.endswith("_SNAPSHOT_END"):
            current = None
            continue
        if current and "=" in line:
            key, value = line.split("=", 1)
            snapshots[current][key] = value

required = ["unguarded", "guarded"]
for mode in required:
    if mode not in snapshots:
        raise SystemExit(f"missing {mode} snapshot in {log_path}")

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

numeric_fields = set(fields) - {"mode"}


def leading_int(value):
    match = re.match(r"\s*(-?\d+)", str(value))
    return match.group(1) if match else "0"

with open(csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    for epoch, mode in enumerate(required):
        snapshot = snapshots[mode]
        row = {
            "epoch": str(epoch),
            "mode": mode,
            "sched_queue_delay_us": snapshot.get("sched_queue_delay_us", "0"),
            "pages_demoted": snapshot.get("pages_demoted", "0"),
            "refault_events": snapshot.get("refault_events", "0"),
            "sched_degrade_state": snapshot.get("sched_degrade_state", "0"),
            "demote_degrade_state": snapshot.get("demote_degrade_state", "0"),
        }
        for field in numeric_fields:
            row[field] = leading_int(row.get(field, "0"))
        row["recovered"] = "1" if mode == "guarded" and int(row["demote_degrade_state"]) >= 2 else "0"
        writer.writerow(row)
PY

cp "$CSV" "$LATEST_RAW"
python3 "$ROOT/experiments/analysis/plot_recovery.py" \
    --input "$LATEST_RAW" \
    --processed "$PROCESSED" \
    --output "$FIGURE" | tee -a "$LOG"

python3 - "$CSV" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

if not any(
    row.get("mode") == "guarded"
    and int(row.get("demote_degrade_state", "0")) >= 2
    and row.get("recovered") == "1"
    for row in rows
):
    raise SystemExit("guarded recovery row missing")
PY

if [ ! -s "$FIGURE" ]; then
    echo "FAIL: recovery figure missing: $FIGURE" >&2
    exit 1
fi

printf 'Recovery CSV: %s\n' "$CSV" | tee -a "$LOG"
printf 'Recovery figure: %s\n' "$FIGURE" | tee -a "$LOG"
printf 'CONTRACTBPF_RECOVERY_CURVE_OK\n' | tee -a "$LOG"
