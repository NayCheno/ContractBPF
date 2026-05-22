#!/usr/bin/env python3
"""Fixture tests for acceptance-gate native evidence provenance checks."""

from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments" / "runners"))
sys.path.insert(0, str(ROOT / "experiments" / "analysis"))

import acceptance_gate_audit as audit  # noqa: E402
import generate_paper_tables as paper_tables  # noqa: E402


FIELDS = [
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


def row(group: str, p99: int, refaults: int, queue: int, demote: int, raw_log: str) -> dict[str, str]:
    return {
        "group": group,
        "description": group,
        "control_mode": group,
        "workload": "memcached",
        "evidence_scope": "native_memcached",
        "p50_latency_us": "500",
        "p99_latency_us": str(p99),
        "p999_latency_us": str(p99),
        "unaffected_tenant_p99_us": "1000",
        "throughput_ops_per_s": "1000.00",
        "sched_queue_delay_us": str(queue),
        "pages_demoted_per_epoch": "8",
        "refault_events": str(refaults),
        "major_fault_events": "1",
        "sched_degrade_state": "0",
        "demote_degrade_state": str(demote),
        "violations": "1" if group in {"G4", "G9"} else "0",
        "service_a_samples_us": "1;2;3",
        "service_b_samples_us": "1;2;3",
        "raw_log": raw_log,
    }


class AcceptanceGateNativeEvidenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "experiments" / "results" / "processed").mkdir(parents=True)
        (self.root / "artifacts" / "logs").mkdir(parents=True)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_preflight(self, *, ok: bool = True, uname: str = "Linux nativehost 6.12.30-contractbpf") -> None:
        payload = {
            "preflight_ok": ok,
            "environment": {
                "uname": uname,
                "kernel_release": "6.12.30-contractbpf",
                "cmdline": "BOOT_IMAGE=/vmlinuz root=/dev/sda1",
            },
        }
        path = self.root / "experiments" / "results" / "processed" / "native_p5p6_preflight.json"
        path.write_text(json.dumps(payload) + "\n", encoding="utf-8")

    def write_raw_log(self, extra: str = "") -> str:
        path = self.root / "artifacts" / "logs" / "native-ok.log"
        path.write_text(
            "\n".join(
                [
                    "CONTRACTBPF_NATIVE_MEMCACHED_BARS_BEGIN",
                    "evidence_scope=native_memcached",
                    "CONTRACTBPF_NATIVE_MEMCACHED_BARS_OK",
                    extra,
                    "",
                ]
            ),
            encoding="utf-8",
        )
        return "artifacts/logs/native-ok.log"

    def write_native_csv(self, raw_log: str) -> Path:
        path = self.root / "experiments" / "results" / "processed" / "native_memcached_bars.csv"
        rows = [
            row("G1", 1000, 0, 0, 0, raw_log),
            row("G2", 1000, 0, 10000, 0, raw_log),
            row("G4", 2000, 10, 30000, 0, raw_log),
            row("G9", 1000, 10, 5000, 2, raw_log),
        ]
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
        return path

    def test_accepts_native_bars_with_preflight_and_native_raw_log(self) -> None:
        self.write_preflight()
        csv_path = self.write_native_csv(self.write_raw_log())
        ok, failures = audit.native_bars_ok(self.root, csv_path)
        self.assertTrue(ok, failures)

    def test_rejects_qemu_markers_in_native_raw_log(self) -> None:
        self.write_preflight()
        csv_path = self.write_native_csv(self.write_raw_log("QEMU exit status: 0"))
        ok, failures = audit.native_bars_ok(self.root, csv_path)
        self.assertFalse(ok)
        self.assertTrue(any("QEMU marker" in failure for failure in failures), failures)

    def test_rejects_wsl_preflight_environment(self) -> None:
        self.write_preflight(uname="Linux host 6.6.87.2-microsoft-standard-WSL2")
        csv_path = self.write_native_csv(self.write_raw_log())
        ok, failures = audit.native_bars_ok(self.root, csv_path)
        self.assertFalse(ok)
        self.assertTrue(any("non-QEMU/non-WSL" in failure for failure in failures), failures)

    def test_generates_native_table_when_native_csv_exists(self) -> None:
        raw_log = self.write_raw_log()
        csv_path = self.write_native_csv(raw_log)
        out_dir = self.root / "paper" / "nsdi27" / "generated"
        entry = paper_tables.write_native_bars(self.root, out_dir)
        self.assertIsNotNone(entry)
        assert entry is not None
        table = self.root / entry["table"]
        self.assertTrue(table.exists())
        self.assertEqual(entry["source"], str(csv_path.relative_to(self.root)))
        self.assertIn("Source-SHA256", table.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
