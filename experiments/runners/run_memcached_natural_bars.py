#!/usr/bin/env python3
import csv
import math
import pathlib
import shutil
import subprocess
from typing import Dict, List, Optional


GROUPS = ["G1", "G2", "G4", "G9"]


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[2]


def percentile(samples: List[int], pct: float) -> int:
    if not samples:
        return 0
    values = sorted(samples)
    index = max(0, math.ceil((pct / 100.0) * len(values)) - 1)
    return values[min(index, len(values) - 1)]


def to_int(value: object, default: int = 0) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return default


def parse_log(path: pathlib.Path) -> List[Dict[str, object]]:
    groups: List[Dict[str, object]] = []
    current: Optional[Dict[str, object]] = None
    service: Optional[str] = None
    section: Optional[str] = None

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line == "CONTRACTBPF_GROUP_BEGIN":
            current = {
                "service_a_samples": [],
                "service_b_samples": [],
                "raw_log": str(path),
            }
            service = None
            section = None
            continue
        if line == "CONTRACTBPF_GROUP_END":
            if current:
                groups.append(current)
            current = None
            service = None
            section = None
            continue
        if current is None:
            continue
        if line == "SERVICE_A_BEGIN":
            service = "a"
            continue
        if line == "SERVICE_A_END":
            service = None
            continue
        if line == "SERVICE_B_BEGIN":
            service = "b"
            continue
        if line == "SERVICE_B_END":
            service = None
            continue
        if line in {"SCHED_SNAPSHOT_BEGIN", "MM_SNAPSHOT_BEGIN"}:
            section = line.split("_", 1)[0].lower()
            continue
        if line in {"SCHED_SNAPSHOT_END", "MM_SNAPSHOT_END"}:
            section = None
            continue
        if line.startswith("LATENCY_SAMPLE_US="):
            try:
                sample = int(line.split("=", 1)[1])
            except ValueError:
                continue
            if service == "a":
                current["service_a_samples"].append(sample)  # type: ignore[index,union-attr]
            elif service == "b":
                current["service_b_samples"].append(sample)  # type: ignore[index,union-attr]
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        current[key] = value
        if section:
            current[f"{section}_{key}"] = value

    found = {str(group.get("group")) for group in groups}
    missing = [group for group in GROUPS if group not in found]
    if missing:
        raise SystemExit(f"natural memcached log missing groups: {', '.join(missing)}")
    return groups


def summarize(groups: List[Dict[str, object]]) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    by_group = {str(group.get("group")): group for group in groups}

    for group_id in GROUPS:
        group = by_group[group_id]
        samples_a = [int(v) for v in group.get("service_a_samples", [])]  # type: ignore[arg-type]
        samples_b = [int(v) for v in group.get("service_b_samples", [])]  # type: ignore[arg-type]
        pages = to_int(group.get("pages_demoted", group.get("mm_pages_demoted")))
        refaults = to_int(group.get("refault_events", group.get("mm_refault_events")))
        major_faults = to_int(group.get("major_fault_events", group.get("mm_major_fault_events")))
        queue = to_int(group.get("sched_queue_delay_us", group.get("sched_sched_queue_delay_us")))
        sched_degrade = to_int(group.get("sched_degrade_state", group.get("sched_boost_degrade_state")))
        demote_degrade = to_int(group.get("demote_degrade_state", group.get("mm_demote_degrade_state")))
        p99 = percentile(samples_a, 99)
        row = {
            "group": group_id,
            "description": str(group.get("description", "")),
            "control_mode": str(group.get("control_mode", "")),
            "workload": str(group.get("workload", "memcached")),
            "evidence_scope": str(group.get("evidence_scope", "qemu_memcached_natural")),
            "p50_latency_us": str(percentile(samples_a, 50)),
            "p99_latency_us": str(p99),
            "p999_latency_us": str(percentile(samples_a, 99.9)),
            "unaffected_tenant_p99_us": str(percentile(samples_b, 99)),
            "throughput_ops_per_s": f"{(len(samples_a) / (sum(samples_a) / 1_000_000.0)):.2f}" if samples_a and sum(samples_a) else "0.00",
            "sched_queue_delay_us": str(queue),
            "pages_demoted_per_epoch": str(pages),
            "refault_events": str(refaults),
            "major_fault_events": str(major_faults),
            "sched_degrade_state": str(sched_degrade),
            "demote_degrade_state": str(demote_degrade),
            "violations": str(to_int(group.get("violations", group.get("mm_violations")))),
            "service_a_samples_us": ";".join(str(v) for v in samples_a),
            "service_b_samples_us": ";".join(str(v) for v in samples_b),
            "raw_log": str(group.get("raw_log", "")),
        }
        rows.append(row)
    return rows


def latest_log(root: pathlib.Path) -> pathlib.Path:
    logs = sorted((root / "artifacts/logs").glob("*-qemu-memcached-natural.log"))
    if not logs:
        raise SystemExit("no memcached natural log found")
    return logs[-1]


def write_csv(path: pathlib.Path, rows: List[Dict[str, str]]) -> None:
    fields = [
        "group",
        "description",
        "control_mode",
        "workload",
        "evidence_scope",
        "p50_latency_us",
        "p99_latency_us",
        "p999_latency_us",
        "unaffected_tenant_p99_us",
        "throughput_ops_per_s",
        "sched_queue_delay_us",
        "pages_demoted_per_epoch",
        "refault_events",
        "major_fault_events",
        "sched_degrade_state",
        "demote_degrade_state",
        "violations",
        "service_a_samples_us",
        "service_b_samples_us",
        "raw_log",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def validate(rows: List[Dict[str, str]]) -> None:
    by_group = {row["group"]: row for row in rows}
    g1 = by_group["G1"]
    g2 = by_group["G2"]
    g4 = by_group["G4"]
    g9 = by_group["G9"]

    g1_p99 = to_int(g1["p99_latency_us"])
    g2_p99 = to_int(g2["p99_latency_us"])
    g4_p99 = to_int(g4["p99_latency_us"])
    g9_p99 = to_int(g9["p99_latency_us"])
    g1_refault = to_int(g1["refault_events"])
    g4_refault = to_int(g4["refault_events"])
    g2_queue = to_int(g2["sched_queue_delay_us"])
    g4_queue = to_int(g4["sched_queue_delay_us"])
    g9_sched_degrade = to_int(g9["sched_degrade_state"])
    g9_demote_degrade = to_int(g9["demote_degrade_state"])
    g4_unaffected = to_int(g4["unaffected_tenant_p99_us"])
    g9_unaffected = to_int(g9["unaffected_tenant_p99_us"])

    failures = []
    if g4_p99 * 100 < max(g1_p99, g2_p99) * 150:
        failures.append(f"G4 p99 {g4_p99} is not >= 1.5x max(G1={g1_p99}, G2={g2_p99})")
    if g1_refault > 0:
        if g4_refault < 2 * g1_refault:
            failures.append(f"G4 refault {g4_refault} is not >= 2x G1 {g1_refault}")
    elif g4_refault <= 0:
        failures.append("G4 refault evidence is zero while G1 is zero")
    if g2_queue > 0:
        if g4_queue < 2 * g2_queue:
            failures.append(f"G4 queue delay {g4_queue} is not >= 2x G2 {g2_queue}")
    elif g4_queue < 20_000:
        failures.append(f"G4 queue delay {g4_queue} is below invariant threshold 20000")
    if g9_demote_degrade < 2:
        failures.append(f"G9 demote degrade state {g9_demote_degrade} is below revoke")
    if g9_sched_degrade != 0:
        failures.append(f"G9 scheduler degrade state {g9_sched_degrade} is not active")
    if g9_p99 * 100 > g4_p99 * 70:
        failures.append(f"G9 p99 {g9_p99} does not improve by >=30% over G4 {g4_p99}")
    if g4_unaffected > 0 and g9_unaffected * 100 > g4_unaffected * 110:
        failures.append(
            f"G9 unaffected p99 {g9_unaffected} is worse than G4 {g4_unaffected} by >10%"
        )

    if failures:
        raise SystemExit("CONTRACTBPF_MEMCACHED_NATURAL_BARS_GATE_FAIL\n" + "\n".join(failures))


def main() -> int:
    root = repo_root()
    subprocess.run([str(root / "qemu/run/run-memcached-natural-bars.sh")], cwd=root, check=True)
    log_path = latest_log(root)
    rows = summarize(parse_log(log_path))

    raw_dir = root / "experiments/results/raw"
    processed_dir = root / "experiments/results/processed"
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_copy = raw_dir / log_path.name
    shutil.copy2(log_path, raw_copy)
    for row in rows:
        row["raw_log"] = str(raw_copy)

    processed_csv = processed_dir / "memcached_natural_bars.csv"
    write_csv(processed_csv, rows)
    validate(rows)

    print(f"raw log: {raw_copy}")
    print(f"processed memcached natural bars: {processed_csv}")
    print("CONTRACTBPF_MEMCACHED_NATURAL_BARS_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
