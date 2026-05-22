#!/usr/bin/env python3
"""Machine-readable P0-P8 acceptance audit for the mature-gate document."""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


COMPLETE = "complete"
PARTIAL = "partial"
INCOMPLETE = "incomplete"
BLOCKED = "blocked"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").replace("\x00", "")
    except OSError:
        return ""


def read_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(read_text(path))
    except (json.JSONDecodeError, OSError):
        return {}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def latest(root: Path, pattern: str) -> Optional[Path]:
    paths = sorted(root.glob(pattern))
    return paths[-1] if paths else None


def contains(path: Optional[Path], marker: str) -> bool:
    return bool(path and marker in read_text(path))


def latest_with_marker(root: Path, pattern: str, marker: str) -> Optional[Path]:
    matches = [path for path in root.glob(pattern) if marker in read_text(path)]
    return sorted(matches)[-1] if matches else None


def csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def as_int(value: object) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return 0


def gate(name: str, status: str, evidence: List[str], missing: List[str]) -> Dict[str, Any]:
    return {"gate": name, "status": status, "evidence": evidence, "missing": missing}


def marker_evidence(path: Optional[Path], marker: str) -> str:
    if path:
        return f"{path.relative_to(repo_root())}: {marker}"
    return marker


def no_forbidden_control_refs(root: Path) -> tuple[bool, List[str]]:
    forbidden = re.compile(
        r"cross_scenario|mm_simulate_bad_demote|sched_gate_enable|mm_gate_enable|sched_boost_budget"
    )
    hits: List[str] = []
    for base in [root / "qemu" / "rootfs", root / "experiments", root / "userspace"]:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if any(part in {"results", "__pycache__", "target"} for part in path.parts):
                continue
            if path.name == "acceptance_gate_audit.py":
                continue
            text = read_text(path)
            for lineno, line in enumerate(text.splitlines(), start=1):
                if forbidden.search(line):
                    hits.append(f"{path.relative_to(root)}:{lineno}:{line.strip()}")
    return (not hits, hits[:20])


def no_paper_placeholder_refs(root: Path) -> tuple[bool, List[str]]:
    forbidden = re.compile(
        r"placeholder|planned evaluation|Expected results|final submission must|placeholder results|paper has not been re-audited|not a completed artifact|paper-planning",
        re.IGNORECASE,
    )
    paths = [
        root / "README.md",
        root / "STATUS.md",
        root / "docs" / "audits" / "acceptance_audit.md",
        root / "paper" / "contractbpf_ledger_nsdi27.tex",
        root / "paper" / "nsdi27" / "contractbpf_ledger_nsdi27.tex",
    ]
    hits: List[str] = []
    for path in paths:
        for lineno, line in enumerate(read_text(path).splitlines(), start=1):
            if forbidden.search(line):
                hits.append(f"{path.relative_to(root)}:{lineno}:{line.strip()}")
    return (not hits, hits[:20])


def paper_intro_within_target(root: Path) -> tuple[bool, str]:
    paper = root / "paper" / "nsdi27" / "contractbpf_ledger_nsdi27.tex"
    text = read_text(paper)
    match = re.search(r"\\section\{Introduction\}(.*?)(?=\\section\{)", text, re.DOTALL)
    if not match:
        return False, "paper/nsdi27/contractbpf_ledger_nsdi27.tex introduction section missing"
    stripped = re.sub(r"\\[a-zA-Z]+\*?(?:\[[^\]]*\])?(?:\{[^}]*\})?", " ", match.group(1))
    words = re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]*", stripped)
    return len(words) <= 1800, f"introduction_words={len(words)} target<=1800"


def paper_claim_scope_ok(root: Path, native_complete: bool) -> tuple[bool, List[str]]:
    paper = root / "paper" / "nsdi27" / "contractbpf_ledger_nsdi27.tex"
    text = read_text(paper)
    missing: List[str] = []
    required_phrases = ["QEMU results are correctness and reproducibility evidence"]
    if native_complete:
        required_phrases.append("Native non-QEMU memcached conflict and recovery bars")
    else:
        required_phrases.extend(["not production performance claims", "must still extend this to non-QEMU"])
    for phrase in required_phrases:
        if phrase not in text:
            missing.append(f"missing claim-scope phrase: {phrase}")
    forbidden = re.compile(r"full PageFlex equivalence|PageFlex-equivalent|production performance results", re.IGNORECASE)
    for lineno, line in enumerate(text.splitlines(), start=1):
        if forbidden.search(line) and "not production performance results" not in line:
            missing.append(f"{paper.relative_to(root)}:{lineno}:{line.strip()}")
    if native_complete:
        stale_after_native = [
            "must still extend this to non-QEMU",
            "non-QEMU performance validation remains future work",
            "does not replace the required non-QEMU P5/P6 final evaluation",
            "not yet a non-QEMU performance study",
        ]
        for phrase in stale_after_native:
            if phrase in text:
                missing.append(f"native evidence present but paper still says: {phrase}")
    return not missing, missing


def generated_paper_tables_ok(root: Path, require_native: bool) -> tuple[bool, List[str], List[str]]:
    paper = root / "paper" / "nsdi27" / "contractbpf_ledger_nsdi27.tex"
    generated = root / "paper" / "nsdi27" / "generated"
    manifest_path = generated / "evidence_manifest.json"
    manifest = read_json(manifest_path)
    paper_text = read_text(paper)
    required = {
        "paper/nsdi27/generated/controlled_qemu_matrix_table.tex": "experiments/results/processed/matrix_summary.csv",
        "paper/nsdi27/generated/qemu_memcached_matrix_table.tex": "experiments/results/processed/memcached_matrix_summary.csv",
        "paper/nsdi27/generated/qemu_memcached_natural_bars_table.tex": "experiments/results/processed/memcached_natural_bars.csv",
        "paper/nsdi27/generated/qemu_no_violation_overhead_table.tex": "experiments/results/processed/no_violation_overhead.csv",
    }
    if require_native:
        required["paper/nsdi27/generated/native_memcached_bars_table.tex"] = (
            "experiments/results/processed/native_memcached_bars.csv"
        )
    evidence: List[str] = []
    missing: List[str] = []
    if not manifest_path.exists():
        missing.append(f"{manifest_path.relative_to(root)} is missing")
    manifest_tables = {
        str(row.get("table")): row for row in manifest.get("tables", []) if isinstance(row, dict)
    }
    for table_rel, source_rel in required.items():
        table_path = root / table_rel
        source_path = root / source_rel
        input_ref = table_rel.replace("paper/nsdi27/", "")
        plain_input = f"\\input{{{input_ref}}}"
        conditional_input = f"\\IfFileExists{{{input_ref}}}"
        if plain_input not in paper_text and conditional_input not in paper_text:
            missing.append(f"paper does not input {input_ref}")
        if not table_path.exists():
            missing.append(f"{table_rel} is missing")
            continue
        if not source_path.exists():
            missing.append(f"{source_rel} is missing")
            continue
        source_hash = file_sha256(source_path)
        table_text = read_text(table_path)
        if f"Source-SHA256: {source_hash}" not in table_text:
            missing.append(f"{table_rel} source hash does not match {source_rel}")
        manifest_row = manifest_tables.get(table_rel)
        if not manifest_row:
            missing.append(f"{manifest_path.relative_to(root)} missing {table_rel}")
        elif manifest_row.get("source") != source_rel or manifest_row.get("sha256") != source_hash:
            missing.append(f"{table_rel} manifest source/hash mismatch")
        evidence.append(f"{table_rel} <= {source_rel}")
    return not missing, evidence, missing


def paper_figures_have_inputs(root: Path) -> tuple[bool, List[str], List[str]]:
    required = {
        "feedback_timeline.svg": ("plot_feedback_timeline.py", "feedback_timeline.csv"),
        "tail_latency.svg": ("plot_tail_latency.py", "tail_latency_table.csv"),
        "recovery.svg": ("plot_recovery.py", "recovery_table.csv"),
        "ablation.svg": ("plot_ablation.py", "ablation_table.csv"),
        "overhead.svg": ("plot_overhead.py", "overhead_table.csv"),
    }
    evidence: List[str] = []
    missing: List[str] = []
    for figure, (script, csv_name) in required.items():
        figure_path = root / "experiments" / "results" / "figures" / figure
        script_path = root / "experiments" / "analysis" / script
        csv_path = root / "experiments" / "results" / "processed" / csv_name
        if not figure_path.exists():
            missing.append(f"{figure_path.relative_to(root)} is missing")
        if not script_path.exists():
            missing.append(f"{script_path.relative_to(root)} is missing")
        if not csv_path.exists():
            missing.append(f"{csv_path.relative_to(root)} is missing")
        evidence.append(f"{figure} <= {script} + {csv_name}")
    return not missing, evidence, missing


def qemu_memcached_bars_ok(path: Path) -> tuple[bool, List[str]]:
    rows = {row.get("group", ""): row for row in csv_rows(path)}
    missing = [group for group in ["G1", "G2", "G4", "G9"] if group not in rows]
    if missing:
        return False, [f"missing groups: {', '.join(missing)}"]
    g1, g2, g4, g9 = rows["G1"], rows["G2"], rows["G4"], rows["G9"]
    failures: List[str] = []
    g4_p99 = as_int(g4["p99_latency_us"])
    g1_p99 = as_int(g1["p99_latency_us"])
    g2_p99 = as_int(g2["p99_latency_us"])
    if g4_p99 * 100 < max(g1_p99, g2_p99) * 150:
        failures.append("G4 P99 does not clear 1.5x G1/G2")
    if as_int(g4["refault_events"]) <= 0:
        failures.append("G4 refault evidence is zero")
    if as_int(g4["sched_queue_delay_us"]) < max(20_000, 2 * as_int(g2["sched_queue_delay_us"])):
        failures.append("G4 queue delay does not clear threshold")
    if as_int(g9["demote_degrade_state"]) < 2:
        failures.append("G9 did not revoke demote")
    if as_int(g9["sched_degrade_state"]) != 0:
        failures.append("G9 scheduler dispatch did not remain active")
    if as_int(g9["p99_latency_us"]) * 100 > g4_p99 * 70:
        failures.append("G9 P99 does not improve by >=30% over G4")
    if as_int(g4["unaffected_tenant_p99_us"]) > 0 and as_int(g9["unaffected_tenant_p99_us"]) * 100 > as_int(g4["unaffected_tenant_p99_us"]) * 110:
        failures.append("G9 unaffected tenant P99 is worse by >10%")
    return not failures, failures


def native_log_path(root: Path, value: str) -> Path:
    if value.startswith("/workspace/"):
        return root / value.removeprefix("/workspace/")
    path = Path(value)
    return path if path.is_absolute() else root / path


def native_environment_ok(root: Path) -> tuple[bool, List[str]]:
    preflight = read_json(root / "experiments" / "results" / "processed" / "native_p5p6_preflight.json")
    failures: List[str] = []
    if not preflight:
        return False, ["native_p5p6_preflight.json is missing or invalid"]
    if not preflight.get("preflight_ok"):
        failures.append("native preflight did not pass")
    env = preflight.get("environment", {})
    env_text = json.dumps(env, sort_keys=True).lower()
    forbidden = ["qemu", "microsoft-standard-wsl", "wsl2", "tcg"]
    hits = [term for term in forbidden if term in env_text]
    if hits:
        failures.append(f"native preflight environment is not non-QEMU/non-WSL: {', '.join(hits)}")
    return not failures, failures


def native_raw_logs_ok(root: Path, rows: List[Dict[str, str]]) -> tuple[bool, List[str]]:
    failures: List[str] = []
    seen: set[Path] = set()
    for row in rows:
        raw = row.get("raw_log", "")
        if not raw:
            failures.append(f"{row.get('group', '<unknown>')} raw_log is missing")
            continue
        path = native_log_path(root, raw)
        if path in seen:
            continue
        seen.add(path)
        text = read_text(path)
        if not text:
            failures.append(f"{path.relative_to(root) if path.is_relative_to(root) else path} is missing or empty")
            continue
        required_markers = [
            "CONTRACTBPF_NATIVE_MEMCACHED_BARS_BEGIN",
            "CONTRACTBPF_NATIVE_MEMCACHED_BARS_OK",
            "evidence_scope=native_memcached",
        ]
        for marker in required_markers:
            if marker not in text:
                failures.append(f"{path.relative_to(root)} missing {marker}")
        forbidden = ["qemu-system", "QEMU exit status", "DMI: QEMU", "qemu_memcached_natural"]
        for marker in forbidden:
            if marker in text:
                failures.append(f"{path.relative_to(root)} contains QEMU marker {marker!r}")
    return not failures, failures


def display_path(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def native_bars_ok(root: Path, path: Path) -> tuple[bool, List[str]]:
    if not path.exists():
        return False, [f"{display_path(root, path)} is missing"]
    ok, failures = qemu_memcached_bars_ok(path)
    rows = csv_rows(path)
    if rows and any(row.get("evidence_scope") != "native_memcached" for row in rows):
        failures.append("native bars CSV is not marked evidence_scope=native_memcached")
    env_ok, env_failures = native_environment_ok(root)
    raw_ok, raw_failures = native_raw_logs_ok(root, rows)
    failures.extend(env_failures)
    failures.extend(raw_failures)
    return ok and env_ok and raw_ok and not failures, failures


def audit(root: Path) -> Dict[str, Any]:
    logs = root / "artifacts" / "logs"
    processed = root / "experiments" / "results" / "processed"
    bundles = root / "experiments" / "artifact_bundles"

    qemu_wrapper = latest(logs, "*-qemu-mature-gates-wrapper.log")
    latest_bundle = latest(bundles, "*.tar.zst")
    p0_ok = bool(qemu_wrapper and latest_bundle and contains(qemu_wrapper, "CONTRACTBPF_MEMCACHED_NATURAL_BARS_GATE_OK"))

    p1_ok, p1_hits = no_forbidden_control_refs(root)
    p2_log = latest_with_marker(logs, "*-qemu-policy-identity.log", "CONTRACTBPF_P2_SOURCE_IDENTITY_OK")
    p3_log = latest_with_marker(logs, "*-qemu-natural-conflict.log", "CONTRACTBPF_SCOPE_RUNTIME_OK")
    p4_log = latest_with_marker(logs, "*-qemu-mm-bpf.log", "CONTRACTBPF_MM_BPF_POLICY_OK")
    natural_conflict_log = latest_with_marker(logs, "*-qemu-natural-conflict.log", "CONTRACTBPF_NATURAL_CONFLICT_5RUN_OK")
    natural_recovery_log = latest_with_marker(logs, "*-qemu-natural-conflict.log", "CONTRACTBPF_NATURAL_RECOVERY_OK")
    qemu_bars_csv = processed / "memcached_natural_bars.csv"
    qemu_bars_pass, qemu_bars_failures = qemu_memcached_bars_ok(qemu_bars_csv)
    native_bars_csv = processed / "native_memcached_bars.csv"
    native_pass, native_failures = native_bars_ok(root, native_bars_csv)
    native_ok_log = latest_with_marker(logs, "*-native-memcached-bars.log", "CONTRACTBPF_NATIVE_MEMCACHED_BARS_OK")
    native_blocked_log = latest_with_marker(logs, "*-native-memcached-bars.log", "CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED")
    preflight_json = processed / "native_p5p6_preflight.json"
    remote_json = processed / "remote_native_mature_gates.json"
    placeholder_ok, placeholder_hits = no_paper_placeholder_refs(root)
    table_ok, table_evidence, table_missing = generated_paper_tables_ok(root, native_pass)
    figure_ok, figure_evidence, figure_missing = paper_figures_have_inputs(root)
    claim_scope_ok, claim_scope_missing = paper_claim_scope_ok(root, native_pass)
    intro_ok, intro_detail = paper_intro_within_target(root)

    gates = [
        gate(
            "P0 reproduce current artifact",
            COMPLETE if p0_ok else INCOMPLETE,
            [
                marker_evidence(qemu_wrapper, "qemu-mature-gates wrapper"),
                f"{latest_bundle.relative_to(root)}" if latest_bundle else "no bundle",
            ],
            [] if p0_ok else ["passing qemu-mature-gates wrapper and bundle required"],
        ),
        gate(
            "P1 remove debugfs final control path",
            COMPLETE if p1_ok else INCOMPLETE,
            ["main experiment/control source scan has no forbidden debugfs control knobs"] if p1_ok else [],
            p1_hits,
        ),
        gate(
            "P2 real policy identity",
            COMPLETE if contains(p2_log, "CONTRACTBPF_P2_SOURCE_IDENTITY_OK") else INCOMPLETE,
            [marker_evidence(p2_log, "CONTRACTBPF_P2_SOURCE_IDENTITY_OK")],
            [] if contains(p2_log, "CONTRACTBPF_P2_SOURCE_IDENTITY_OK") else ["P2 marker missing"],
        ),
        gate(
            "P3 real scope mapping",
            COMPLETE if contains(p3_log, "CONTRACTBPF_SCOPE_RUNTIME_OK") else INCOMPLETE,
            [marker_evidence(p3_log, "CONTRACTBPF_SCOPE_RUNTIME_OK")],
            [] if contains(p3_log, "CONTRACTBPF_SCOPE_RUNTIME_OK") else ["P3 marker missing"],
        ),
        gate(
            "P4 real BPF paging path",
            COMPLETE if contains(p4_log, "CONTRACTBPF_MM_BPF_POLICY_OK") else INCOMPLETE,
            [marker_evidence(p4_log, "CONTRACTBPF_MM_BPF_POLICY_OK")],
            [] if contains(p4_log, "CONTRACTBPF_MM_BPF_POLICY_OK") else ["P4 marker missing"],
        ),
    ]

    p5_status = COMPLETE if native_pass else PARTIAL
    p6_status = COMPLETE if native_pass else PARTIAL
    native_bars_evidence = (
        [
            f"{native_bars_csv.relative_to(root)} native bars pass=True",
            marker_evidence(native_ok_log, "CONTRACTBPF_NATIVE_MEMCACHED_BARS_OK"),
        ]
        if native_pass
        else [marker_evidence(native_blocked_log, "CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED")]
    )
    remote_native_evidence = [f"{remote_json.relative_to(root)}"] if remote_json.exists() else []
    gates.append(
        gate(
            "P5 natural scheduler-paging conflict",
            p5_status,
            [
                marker_evidence(natural_conflict_log, "CONTRACTBPF_NATURAL_CONFLICT_5RUN_OK"),
                f"{qemu_bars_csv.relative_to(root)} QEMU bars pass={qemu_bars_pass}",
                *native_bars_evidence,
                *remote_native_evidence,
            ],
            [] if native_pass else ["native non-QEMU memcached bars missing or failed", *native_failures],
        )
    )
    gates.append(
        gate(
            "P6 bounded degradation recovery",
            p6_status,
            [
                marker_evidence(natural_recovery_log, "CONTRACTBPF_NATURAL_RECOVERY_OK"),
                f"{qemu_bars_csv.relative_to(root)} QEMU recovery bars pass={qemu_bars_pass}",
                *native_bars_evidence,
                *remote_native_evidence,
            ],
            [] if native_pass else ["native non-QEMU recovery bars missing or failed", *native_failures],
        )
    )

    overhead_csv = processed / "no_violation_overhead.csv"
    overhead_rows = csv_rows(overhead_csv)
    overhead_ok = bool(overhead_rows and overhead_rows[-1].get("pass") == "1")
    hotpath_log = latest(logs, "*-qemu-natural-conflict.log")
    ledger_ok = any("CONTRACTBPF_LEDGER_STRESS_GATE_OK" in read_text(path) for path in logs.glob("*-qemu-natural-conflict.log"))
    hotpath_ok = any("CONTRACTBPF_HOTPATH_GATE_OK" in read_text(path) for path in logs.glob("*-qemu-natural-conflict.log"))
    p7_ok = overhead_ok and ledger_ok and hotpath_ok
    gates.append(
        gate(
            "P7 overhead and scalability",
            COMPLETE if p7_ok else INCOMPLETE,
            [
                f"{overhead_csv.relative_to(root)} pass={overhead_ok}",
                "CONTRACTBPF_LEDGER_STRESS_GATE_OK" if ledger_ok else "ledger stress missing",
                "CONTRACTBPF_HOTPATH_GATE_OK" if hotpath_ok else "hotpath marker missing",
            ],
            [] if p7_ok else ["P7 overhead, hotpath, and ledger stress evidence all required"],
        )
    )

    p8_integrity_ok = placeholder_ok and table_ok and figure_ok and claim_scope_ok and intro_ok
    p8_ok = p8_integrity_ok and native_pass and bool(latest_bundle)
    p8_missing: List[str] = []
    if not native_pass:
        p8_missing.append("final paper audit requires native non-QEMU evidence")
    if not placeholder_ok:
        p8_missing.extend(placeholder_hits)
    if not table_ok:
        p8_missing.extend(table_missing)
    if not figure_ok:
        p8_missing.extend(figure_missing)
    if not claim_scope_ok:
        p8_missing.extend(claim_scope_missing)
    if not intro_ok:
        p8_missing.append(intro_detail)
    gates.append(
        gate(
            "P8 paper evidence integrity",
            COMPLETE if p8_ok else PARTIAL,
            [
                "paper placeholder scan passed" if placeholder_ok else "paper placeholder scan failed",
                "generated paper tables passed" if table_ok else "generated paper tables failed",
                *table_evidence,
                "figure script/input map passed" if figure_ok else "figure script/input map failed",
                *figure_evidence,
                "paper QEMU/non-QEMU claim scope passed" if claim_scope_ok else "paper QEMU/non-QEMU claim scope failed",
                intro_detail,
                f"latest bundle={latest_bundle.relative_to(root)}" if latest_bundle else "no bundle",
                f"native preflight report={preflight_json.relative_to(root)}" if preflight_json.exists() else "native preflight report missing",
                f"remote native report={remote_json.relative_to(root)}" if remote_json.exists() else "remote native report missing",
            ],
            [] if p8_ok else p8_missing,
        )
    )

    complete = all(row["status"] == COMPLETE for row in gates)
    return {
        "timestamp_utc": dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ"),
        "complete": complete,
        "summary": {
            "complete": sum(1 for row in gates if row["status"] == COMPLETE),
            "partial": sum(1 for row in gates if row["status"] == PARTIAL),
            "incomplete": sum(1 for row in gates if row["status"] == INCOMPLETE),
            "blocked": sum(1 for row in gates if row["status"] == BLOCKED),
        },
        "gates": gates,
        "qemu_bars_failures": qemu_bars_failures,
    }


def write_markdown(path: Path, payload: Dict[str, Any]) -> None:
    lines = [
        "# Acceptance Gate Audit",
        "",
        f"Timestamp UTC: {payload['timestamp_utc']}",
        f"Complete: {payload['complete']}",
        "",
        "| Gate | Status | Missing |",
        "|---|---|---|",
    ]
    for row in payload["gates"]:
        missing = "<br>".join(row["missing"]) if row["missing"] else ""
        lines.append(f"| {row['gate']} | {row['status']} | {missing} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    root = repo_root()
    payload = audit(root)
    out_dir = root / "experiments" / "results" / "processed"
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "acceptance_gate_audit.json"
    md_path = root / "docs" / "audits" / "acceptance_gate_audit_latest.md"
    md_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(md_path, payload)
    print(f"acceptance audit json: {json_path}")
    print(f"acceptance audit markdown: {md_path}")
    for row in payload["gates"]:
        print(f"{row['gate']}: {row['status']}")
    if payload["complete"]:
        print("CONTRACTBPF_ACCEPTANCE_AUDIT_OK")
        return 0
    print("CONTRACTBPF_ACCEPTANCE_AUDIT_INCOMPLETE")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
