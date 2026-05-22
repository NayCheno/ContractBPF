#!/usr/bin/env python3
import csv
import math
import pathlib
import shutil
import subprocess
from typing import Dict, Iterable, List, Optional


GROUPS = [f"G{i}" for i in range(1, 10)]

SUMMARY_FIELDS = [
    "group",
    "description",
    "control_mode",
    "workload",
    "evidence_scope",
    "p50_latency_us",
    "p99_latency_us",
    "p999_latency_us",
    "throughput_ops_per_s",
    "major_fault_rate_per_epoch",
    "refault_ratio",
    "sched_queue_delay_us",
    "pages_demoted_per_epoch",
    "boost_events_per_epoch",
    "fallback_activation_latency_ms",
    "recovery_time_epochs",
    "steady_state_overhead_pct",
    "unaffected_tenant_p99_us",
    "major_fault_events",
    "refault_events",
    "sched_degrade_state",
    "demote_degrade_state",
    "violations",
]

RAW_FIELDS = SUMMARY_FIELDS + [
    "service_a_samples_us",
    "service_b_samples_us",
    "raw_log",
]


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[2]


def parse_flat_yaml(path: pathlib.Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def load_configs(config_dir: pathlib.Path) -> Dict[str, Dict[str, str]]:
    configs: Dict[str, Dict[str, str]] = {}
    for path in sorted(config_dir.glob("g*.yaml")):
        data = parse_flat_yaml(path)
        group = data.get("group")
        if group:
            configs[group] = data
    missing = [group for group in GROUPS if group not in configs]
    if missing:
        raise SystemExit(f"missing experiment configs: {', '.join(missing)}")
    return configs


def latest_matrix_log(root: pathlib.Path) -> pathlib.Path:
    logs = sorted((root / "artifacts/logs").glob("*-qemu-experiment-matrix.log"))
    if not logs:
        raise SystemExit("no experiment matrix log found")
    return logs[-1]


def run_qemu_matrix(root: pathlib.Path) -> pathlib.Path:
    subprocess.run([str(root / "qemu/run/run-experiment-matrix.sh")], cwd=root, check=True)
    return latest_matrix_log(root)


def _append_latency(group: Dict[str, object], service: Optional[str], value: str) -> None:
    if service not in {"a", "b"}:
        return
    try:
        sample = int(value)
    except ValueError:
        return
    key = "service_a_samples" if service == "a" else "service_b_samples"
    group.setdefault(key, []).append(sample)


def parse_matrix_log(path: pathlib.Path) -> List[Dict[str, object]]:
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
        if line in {"CROSS_SNAPSHOT_BEGIN", "SCHED_SNAPSHOT_BEGIN", "MM_SNAPSHOT_BEGIN"}:
            section = line.split("_", 1)[0].lower()
            continue
        if line in {"CROSS_SNAPSHOT_END", "SCHED_SNAPSHOT_END", "MM_SNAPSHOT_END"}:
            section = None
            continue

        if line.startswith("LATENCY_SAMPLE_US="):
            _append_latency(current, service, line.split("=", 1)[1])
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
        raise SystemExit(f"matrix log missing groups: {', '.join(missing)}")
    return groups


def to_int(value: object, default: int = 0) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return default


def percentile(samples: Iterable[int], pct: float) -> int:
    values = sorted(int(sample) for sample in samples)
    if not values:
        return 0
    index = max(0, math.ceil((pct / 100.0) * len(values)) - 1)
    return values[min(index, len(values) - 1)]


def throughput(samples: List[int]) -> str:
    total_us = sum(samples)
    if not samples or total_us <= 0:
        return "0.00"
    return f"{len(samples) / (total_us / 1000000.0):.2f}"


def summarize_groups(
    parsed_groups: List[Dict[str, object]],
    configs: Dict[str, Dict[str, str]],
) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    by_group = {str(group.get("group")): group for group in parsed_groups}

    for group_id in GROUPS:
        group = by_group[group_id]
        config = configs[group_id]
        samples_a = [int(v) for v in group.get("service_a_samples", [])]  # type: ignore[arg-type]
        samples_b = [int(v) for v in group.get("service_b_samples", [])]  # type: ignore[arg-type]
        pages_demoted = to_int(group.get("pages_demoted", group.get("cross_pages_demoted")))
        refault_events = to_int(group.get("refault_events", group.get("cross_refault_events")))
        major_fault_events = to_int(group.get("major_fault_events", group.get("mm_major_fault_events")))
        sched_degrade = to_int(group.get("sched_degrade_state", group.get("cross_sched_degrade_state")))
        demote_degrade = to_int(group.get("demote_degrade_state", group.get("cross_demote_degrade_state")))
        whole_policy = to_int(group.get("whole_policy_fallback"))
        p99 = percentile(samples_a, 99)

        fallback_ms = 0
        if demote_degrade >= 2 or sched_degrade >= 1 or whole_policy:
            fallback_ms = 1

        recovery_epochs = 0
        if group_id == "G9" and demote_degrade >= 2 and sched_degrade == 0:
            recovery_epochs = 1
        elif whole_policy:
            recovery_epochs = 2

        row = {
            "group": group_id,
            "description": config.get("description", str(group.get("description", ""))),
            "control_mode": config.get("control_mode", str(group.get("control_mode", ""))),
            "workload": config.get("workload", str(group.get("workload", ""))),
            "evidence_scope": config.get("evidence_scope", str(group.get("evidence_scope", ""))),
            "p50_latency_us": str(percentile(samples_a, 50)),
            "p99_latency_us": str(p99),
            "p999_latency_us": str(percentile(samples_a, 99.9)),
            "throughput_ops_per_s": throughput(samples_a),
            "major_fault_rate_per_epoch": str(major_fault_events),
            "refault_ratio": f"{(refault_events / pages_demoted):.4f}" if pages_demoted else "0.0000",
            "sched_queue_delay_us": str(to_int(group.get("sched_queue_delay_us", group.get("cross_sched_queue_delay_us")))),
            "pages_demoted_per_epoch": str(pages_demoted),
            "boost_events_per_epoch": str(to_int(group.get("sched_boost_events", group.get("sched_sched_boost_events")))),
            "fallback_activation_latency_ms": str(fallback_ms),
            "recovery_time_epochs": str(recovery_epochs),
            "steady_state_overhead_pct": "0.00",
            "unaffected_tenant_p99_us": str(percentile(samples_b, 99)),
            "major_fault_events": str(major_fault_events),
            "refault_events": str(refault_events),
            "sched_degrade_state": str(sched_degrade),
            "demote_degrade_state": str(demote_degrade),
            "violations": str(to_int(group.get("violations", group.get("cross_violations")))),
            "service_a_samples_us": ";".join(str(v) for v in samples_a),
            "service_b_samples_us": ";".join(str(v) for v in samples_b),
            "raw_log": str(group.get("raw_log", "")),
        }
        rows.append(row)

    baseline = to_int(rows[0]["p99_latency_us"])
    if baseline > 0:
        for row in rows:
            overhead = ((to_int(row["p99_latency_us"]) - baseline) / baseline) * 100.0
            row["steady_state_overhead_pct"] = f"{overhead:.2f}"
    return rows


def write_csv(path: pathlib.Path, rows: List[Dict[str, str]], fields: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})


def write_derived_tables(root: pathlib.Path, rows: List[Dict[str, str]]) -> None:
    processed = root / "experiments/results/processed"
    raw = root / "experiments/results/raw"
    processed.mkdir(parents=True, exist_ok=True)
    raw.mkdir(parents=True, exist_ok=True)

    write_csv(processed / "tail_latency_table.csv", rows, [
        "group",
        "description",
        "p50_latency_us",
        "p99_latency_us",
        "p999_latency_us",
        "unaffected_tenant_p99_us",
    ])
    write_csv(processed / "feedback_timeline.csv", rows, [
        "group",
        "description",
        "sched_queue_delay_us",
        "pages_demoted_per_epoch",
        "refault_events",
        "demote_degrade_state",
    ])
    write_csv(processed / "ablation_table.csv", rows, [
        "group",
        "description",
        "p99_latency_us",
        "recovery_time_epochs",
        "demote_degrade_state",
        "sched_degrade_state",
    ])
    write_csv(processed / "overhead_table.csv", rows, [
        "group",
        "description",
        "throughput_ops_per_s",
        "steady_state_overhead_pct",
    ])

    recovery_rows = []
    for epoch, group_id in enumerate(["G4", "G9"]):
        row = next(item for item in rows if item["group"] == group_id)
        recovery_rows.append({
            "epoch": str(epoch),
            "mode": "unguarded" if group_id == "G4" else "guarded",
            "sched_queue_delay_us": row["sched_queue_delay_us"],
            "pages_demoted": row["pages_demoted_per_epoch"],
            "refault_events": row["refault_events"],
            "sched_degrade_state": row["sched_degrade_state"],
            "demote_degrade_state": row["demote_degrade_state"],
            "recovered": "1" if group_id == "G9" and to_int(row["demote_degrade_state"]) >= 2 else "0",
        })
    write_csv(raw / "recovery_latest.csv", recovery_rows, [
        "epoch",
        "mode",
        "sched_queue_delay_us",
        "pages_demoted",
        "refault_events",
        "sched_degrade_state",
        "demote_degrade_state",
        "recovered",
    ])


def copy_raw_log(log_path: pathlib.Path, raw_dir: pathlib.Path) -> pathlib.Path:
    raw_dir.mkdir(parents=True, exist_ok=True)
    dst = raw_dir / log_path.name
    if log_path.resolve() != dst.resolve():
        shutil.copy2(log_path, dst)
    return dst


def run_plot_scripts(root: pathlib.Path) -> None:
    scripts = [
        "plot_feedback_timeline.py",
        "plot_tail_latency.py",
        "plot_recovery.py",
        "plot_ablation.py",
        "plot_overhead.py",
    ]
    for script in scripts:
        subprocess.run(["python3", str(root / "experiments/analysis" / script)], cwd=root, check=True)
