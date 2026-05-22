#!/usr/bin/env python3
import argparse
import csv
import pathlib
import subprocess
from typing import Dict, List, Optional

from matrixlib import percentile, repo_root, throughput


FIELDS = [
    "phase",
    "description",
    "p99_latency_us",
    "throughput_ops_per_s",
    "cpu_busy_jiffies",
    "cpu_total_jiffies",
    "cpu_busy_pct",
    "p99_overhead_pct",
    "throughput_overhead_pct",
    "cpu_overhead_pct",
    "pass",
    "raw_log",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", help="Reuse an existing no-violation overhead log")
    parser.add_argument("--max-overhead-pct", type=float, default=5.0)
    return parser.parse_args()


def latest_log(root: pathlib.Path) -> pathlib.Path:
    logs = sorted((root / "artifacts/logs").glob("*-qemu-no-violation-overhead.log"))
    if not logs:
        raise SystemExit("no no-violation overhead log found")
    return logs[-1]


def run_qemu(root: pathlib.Path) -> pathlib.Path:
    subprocess.run(["bash", str(root / "qemu/run/run-no-violation-overhead.sh")], cwd=root, check=True)
    return latest_log(root)


def parse_log(path: pathlib.Path) -> Dict[str, Dict[str, object]]:
    phases: Dict[str, Dict[str, object]] = {}
    current: Optional[Dict[str, object]] = None
    service: Optional[str] = None

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line == "CONTRACTBPF_GROUP_BEGIN":
            current = {"service_a_samples": [], "raw_log": str(path)}
            service = None
            continue
        if line == "CONTRACTBPF_GROUP_END":
            if current and current.get("group"):
                phases[str(current["group"])] = current
            current = None
            service = None
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
        if line.startswith("LATENCY_SAMPLE_US=") and service == "a":
            try:
                current["service_a_samples"].append(int(line.split("=", 1)[1]))  # type: ignore[index,union-attr]
            except ValueError:
                pass
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            current[key] = value

    missing = [phase for phase in ("NV0", "NV1") if phase not in phases]
    if missing:
        raise SystemExit(f"missing no-violation phases: {', '.join(missing)}")
    return phases


def as_int(value: object) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return 0


def overhead_pct(baseline: float, candidate: float, lower_is_better: bool) -> float:
    if baseline <= 0:
        return 0.0
    if lower_is_better:
        return ((candidate - baseline) / baseline) * 100.0
    return ((baseline - candidate) / baseline) * 100.0


def busy_pct(busy: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return (float(busy) / float(total)) * 100.0


def build_rows(path: pathlib.Path, max_overhead: float) -> List[Dict[str, str]]:
    phases = parse_log(path)
    rows: List[Dict[str, str]] = []

    computed = {}
    for phase, group in phases.items():
        samples = [int(v) for v in group.get("service_a_samples", [])]  # type: ignore[arg-type]
        computed[phase] = {
            "description": str(group.get("description", "")),
            "p99": percentile(samples, 99),
            "throughput": float(throughput(samples)),
            "cpu_busy": as_int(group.get("cpu_busy_jiffies")),
            "cpu_total": as_int(group.get("cpu_total_jiffies")),
        }
        computed[phase]["cpu_busy_pct"] = busy_pct(
            int(computed[phase]["cpu_busy"]),
            int(computed[phase]["cpu_total"]),
        )

    base = computed["NV0"]
    cand = computed["NV1"]
    p99_overhead = overhead_pct(base["p99"], cand["p99"], lower_is_better=True)
    throughput_overhead = overhead_pct(base["throughput"], cand["throughput"], lower_is_better=False)
    cpu_overhead = overhead_pct(base["cpu_busy_pct"], cand["cpu_busy_pct"], lower_is_better=True)
    passed = (
        p99_overhead <= max_overhead
        and throughput_overhead <= max_overhead
        and cpu_overhead <= max_overhead
    )

    for phase in ("NV0", "NV1"):
        data = computed[phase]
        rows.append({
            "phase": phase,
            "description": str(data["description"]),
            "p99_latency_us": str(data["p99"]),
            "throughput_ops_per_s": f"{data['throughput']:.2f}",
            "cpu_busy_jiffies": str(data["cpu_busy"]),
            "cpu_total_jiffies": str(data["cpu_total"]),
            "cpu_busy_pct": f"{data['cpu_busy_pct']:.2f}",
            "p99_overhead_pct": "0.00" if phase == "NV0" else f"{p99_overhead:.2f}",
            "throughput_overhead_pct": "0.00" if phase == "NV0" else f"{throughput_overhead:.2f}",
            "cpu_overhead_pct": "0.00" if phase == "NV0" else f"{cpu_overhead:.2f}",
            "pass": "1" if phase == "NV1" and passed else ("baseline" if phase == "NV0" else "0"),
            "raw_log": str(path),
        })
    return rows


def write_csv(path: pathlib.Path, rows: List[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    args = parse_args()
    root = repo_root()
    log_path = pathlib.Path(args.log) if args.log else run_qemu(root)
    if not log_path.is_absolute():
        log_path = root / log_path

    rows = build_rows(log_path, args.max_overhead_pct)
    out = root / "experiments/results/processed/no_violation_overhead.csv"
    write_csv(out, rows)
    candidate = rows[1]

    print(f"raw log: {log_path}")
    print(f"processed no-violation overhead: {out}")
    print(f"p99_overhead_pct={candidate['p99_overhead_pct']}")
    print(f"throughput_overhead_pct={candidate['throughput_overhead_pct']}")
    print(f"cpu_overhead_pct={candidate['cpu_overhead_pct']}")
    if candidate["pass"] == "1":
        print("CONTRACTBPF_NO_VIOLATION_OVERHEAD_GATE_OK")
        return 0
    print("CONTRACTBPF_NO_VIOLATION_OVERHEAD_GATE_FAIL")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
