#!/usr/bin/env python3
"""Run native non-QEMU memcached P5/P6 bars when the host is capable."""

from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, TextIO

from run_memcached_natural_bars import parse_log, summarize, validate, write_csv


GROUPS = ["G1", "G2", "G4", "G9"]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-preflight", action="store_true")
    parser.add_argument("--ops-a", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_OPS_A", "4000")))
    parser.add_argument("--ops-b", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_OPS_B", "2000")))
    parser.add_argument("--value-a", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_VALUE_A", "16384")))
    parser.add_argument("--value-b", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_VALUE_B", "1024")))
    parser.add_argument("--file-mb", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_FILE_MB", "256")))
    parser.add_argument("--pressure-mb", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_PRESSURE_MB", "3072")))
    parser.add_argument("--iterations", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_ITERATIONS", "2")))
    parser.add_argument("--memory-high", type=int, default=int(os.environ.get("CONTRACTBPF_NATIVE_MEMORY_HIGH", str(512 * 1024 * 1024))))
    parser.add_argument(
        "--recovery-sleep-s",
        type=float,
        default=float(os.environ.get("CONTRACTBPF_NATIVE_RECOVERY_SLEEP_S", "2.0")),
    )
    parser.add_argument(
        "--conflict-warmup-s",
        type=float,
        default=float(os.environ.get("CONTRACTBPF_NATIVE_CONFLICT_WARMUP_S", "2.0")),
    )
    return parser.parse_args()


class NativeRunner:
    def __init__(self, root: Path, args: argparse.Namespace, log: TextIO):
        self.root = root
        self.args = args
        self.log = log
        self.state_dir = Path(os.environ.get("CONTRACTBPF_STATE_DIR", "/run/contractbpf-native-p5p6"))
        self.cgroup_root = Path(os.environ.get("CONTRACTBPF_CGROUP_ROOT", "/sys/fs/cgroup"))
        self.contractctl = root / "userspace" / "contractctl" / "target" / "debug" / "contractctl"
        self.scx = root / "build" / "scx" / "build" / "bin" / "scx_contract_boost"
        self.mm_loader = root / "build" / "bpf" / "contract_mm_loader"
        self.bad_demote = root / "build" / "bpf" / "bad_demote.bpf.o"
        self.memcached = Path(shutil.which("memcached") or "/usr/bin/memcached")
        self.memload = root / "workloads" / "memcached" / "memcached_ascii_load"
        self.pressure = root / "workloads" / "memory_pressure" / "pressure"
        self.sched_manifest = root / "bpf" / "contracts" / "service_a_sched_natural.yaml"
        self.paging_manifest = root / "bpf" / "contracts" / "service_a_paging.yaml"
        self.paging_norevoke_manifest = root / "bpf" / "contracts" / "service_a_paging_norevoke.yaml"
        self.pressure_file = Path(os.environ.get("CONTRACTBPF_NATIVE_PRESSURE_FILE", "/tmp/contractbpf-native-pressure.bin"))
        self.pressure_mempolicy = os.environ.get("CONTRACTBPF_PRESSURE_MEMPOLICY", "bind")
        self.processes: List[subprocess.Popen[str]] = []
        self.scx_proc: Optional[subprocess.Popen[str]] = None
        self.memcached_a: Optional[subprocess.Popen[str]] = None
        self.memcached_b: Optional[subprocess.Popen[str]] = None

    def emit(self, line: str = "") -> None:
        print(line, file=self.log, flush=True)

    def run(self, argv: List[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
        self.emit("COMMAND " + " ".join(argv))
        proc = subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        if proc.stdout:
            self.log.write(proc.stdout)
            if not proc.stdout.endswith("\n"):
                self.log.write("\n")
            self.log.flush()
        if check and proc.returncode != 0:
            raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(argv)}")
        return proc

    def contractctl_cmd(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return self.run([str(self.contractctl), "--state-dir", str(self.state_dir), *args], check=check)

    def cgroup(self, name: str) -> Path:
        return self.cgroup_root / name

    def put_pid_in_cgroup(self, name: str, pid: int) -> None:
        try:
            (self.cgroup(name) / "cgroup.procs").write_text(f"{pid}\n", encoding="utf-8")
        except OSError as err:
            raise RuntimeError(f"failed to move pid {pid} into cgroup {name}: {err}") from err

    def setup_cgroups(self) -> None:
        for name in ("service-A", "service-B"):
            self.cgroup(name).mkdir(exist_ok=True)
        subtree = self.cgroup_root / "cgroup.subtree_control"
        if subtree.exists():
            try:
                subtree.write_text("+memory\n", encoding="utf-8")
            except OSError as err:
                self.emit(f"cgroup_subtree_control_warning={err}")
        high = self.cgroup("service-A") / "memory.high"
        if high.exists():
            high.write_text(f"{self.args.memory_high}\n", encoding="utf-8")
            self.emit(f"service_a_memory_high={high.read_text(encoding='utf-8').strip()}")

    def reset_contract(self) -> None:
        shutil.rmtree(self.state_dir, ignore_errors=True)
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.setup_cgroups()
        self.contractctl_cmd("reset", "--test-only", check=False)

    def load_contracts(self, paging_manifest: Path) -> None:
        self.reset_contract()
        self.run([str(self.mm_loader), str(self.bad_demote)])
        self.contractctl_cmd("reset", "--test-only", check=False)
        self.contractctl_cmd("load", str(self.sched_manifest))
        self.contractctl_cmd("load", str(paging_manifest))
        self.contractctl_cmd("gate", str(self.sched_manifest), "--enable", "1")
        self.contractctl_cmd("gate", str(paging_manifest), "--enable", "1")

    def start_scx(self) -> None:
        self.scx_proc = subprocess.Popen(
            [str(self.scx)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        self.processes.append(self.scx_proc)
        state_path = Path("/sys/kernel/sched_ext/state")
        for _ in range(20):
            state = state_path.read_text(encoding="utf-8", errors="replace").strip()
            self.emit(f"SCHED_EXT_STATE_POLL={state}")
            if state == "enabled":
                self.emit("CONTRACTBPF_SCHED_EXT_OK")
                return
            time.sleep(0.5)
        raise RuntimeError("sched_ext did not become enabled")

    def stop_scx(self) -> None:
        if not self.scx_proc:
            return
        self.scx_proc.terminate()
        try:
            output, _ = self.scx_proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(self.scx_proc.pid, signal.SIGKILL)
            output, _ = self.scx_proc.communicate(timeout=5)
        if output:
            self.log.write(output)
            if not output.endswith("\n"):
                self.log.write("\n")
            self.log.flush()
        self.scx_proc = None
        state_path = Path("/sys/kernel/sched_ext/state")
        if state_path.exists():
            state = state_path.read_text(encoding="utf-8", errors="replace").strip()
            self.emit(f"SCHED_EXT_STATE_AFTER_STOP={state}")
        self.emit("CONTRACTBPF_SCHED_EXT_UNLOAD_OK")

    def start_memcached(self) -> None:
        self.memcached_a = subprocess.Popen(
            [str(self.memcached), "-u", "root", "-l", "127.0.0.1", "-p", "11211", "-m", "512"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.memcached_b = subprocess.Popen(
            [str(self.memcached), "-u", "root", "-l", "127.0.0.1", "-p", "11212", "-m", "256"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.processes.extend([self.memcached_a, self.memcached_b])
        self.put_pid_in_cgroup("service-A", self.memcached_a.pid)
        self.put_pid_in_cgroup("service-B", self.memcached_b.pid)
        time.sleep(1)
        if self.memcached_a.poll() is not None or self.memcached_b.poll() is not None:
            raise RuntimeError("memcached failed to start")

    def popen_in_cgroup(
        self,
        service: str,
        argv: List[str],
        *,
        env: Optional[Dict[str, str]] = None,
    ) -> subprocess.Popen[str]:
        proc = subprocess.Popen(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        self.processes.append(proc)
        self.put_pid_in_cgroup(service, proc.pid)
        return proc

    def run_load_pair(self, label: str) -> None:
        a = self.popen_in_cgroup(
            "service-A",
            [str(self.memload), "11211", str(self.args.ops_a), str(self.args.value_a)],
        )
        b = self.popen_in_cgroup(
            "service-B",
            [str(self.memload), "11212", str(self.args.ops_b), str(self.args.value_b)],
        )
        out_a, _ = a.communicate()
        out_b, _ = b.communicate()
        self.emit("SERVICE_A_BEGIN")
        self.log.write(out_a or "")
        if out_a and not out_a.endswith("\n"):
            self.log.write("\n")
        self.emit("SERVICE_A_END")
        self.emit("SERVICE_B_BEGIN")
        self.log.write(out_b or "")
        if out_b and not out_b.endswith("\n"):
            self.log.write("\n")
        self.emit("SERVICE_B_END")
        self.emit(f"native_load_pair_done={label}")

    def start_pressure(self, label: str) -> subprocess.Popen[str]:
        path = Path(f"{self.pressure_file}.{label}")
        env = os.environ.copy()
        env["CONTRACTBPF_PRESSURE_MEMPOLICY"] = self.pressure_mempolicy
        return self.popen_in_cgroup(
            "service-A",
            [
                str(self.pressure),
                str(path),
                str(self.args.file_mb),
                str(self.args.pressure_mb),
                str(self.args.iterations),
            ],
            env=env,
        )

    def begin_group(self, group: str, description: str) -> None:
        self.emit("CONTRACTBPF_GROUP_BEGIN")
        self.emit(f"group={group}")
        self.emit(f"description={description}")
        self.emit("workload=memcached")
        self.emit("evidence_scope=native_memcached")

    def emit_metrics(self, label: str) -> None:
        self.emit("SNAPSHOT_BEGIN")
        self.emit("DEVICE_LEDGER_BEGIN")
        proc = self.contractctl_cmd("ledger", "--scope", "service-A", "--format", "lines", check=False)
        if proc.returncode != 0:
            self.emit(f"ledger_read_error={proc.returncode}")
        self.emit("DEVICE_LEDGER_END")
        debugfs = Path("/sys/kernel/debug/contractbpf")
        for section, filename in (("SCHED", "sched_snapshot"), ("MM", "mm_snapshot")):
            path = debugfs / filename
            if path.exists():
                self.emit(f"{section}_SNAPSHOT_BEGIN")
                self.emit(path.read_text(encoding="utf-8", errors="replace").strip())
                self.emit(f"{section}_SNAPSHOT_END")
        self.emit("SNAPSHOT_END")
        self.emit(f"native_metrics_done={label}")

    def end_group(self, label: str) -> None:
        self.emit_metrics(label)
        self.emit("CONTRACTBPF_GROUP_END")

    def run_baseline_group(self, group: str, description: str, sched_only: bool) -> None:
        self.begin_group(group, description)
        self.reset_contract()
        self.emit(f"control_mode={'sched_only' if sched_only else 'default'}")
        if sched_only:
            self.start_scx()
        self.run_load_pair(group)
        if sched_only:
            self.stop_scx()
        self.end_group(group)

    def run_conflict_group(self, group: str, description: str, manifest: Path) -> None:
        self.begin_group(group, description)
        self.load_contracts(manifest)
        self.emit(f"control_mode={group}")
        self.start_scx()
        if group == "G9":
            pressure = self.start_pressure(f"{group}-prerecovery")
            pressure_out, _ = pressure.communicate()
            self.log.write(pressure_out or "")
            if self.args.recovery_sleep_s > 0:
                self.emit(f"recovery_sleep_s={self.args.recovery_sleep_s}")
                time.sleep(self.args.recovery_sleep_s)
            self.run_load_pair(group)
        else:
            pressure = self.start_pressure(group)
            if self.args.conflict_warmup_s > 0:
                self.emit(f"conflict_warmup_s={self.args.conflict_warmup_s}")
                time.sleep(self.args.conflict_warmup_s)
            self.run_load_pair(group)
            pressure_out, _ = pressure.communicate()
            self.log.write(pressure_out or "")
        self.end_group(group)
        self.stop_scx()

    def cleanup(self) -> None:
        for proc in reversed(self.processes):
            if proc.poll() is None:
                proc.terminate()
        for proc in reversed(self.processes):
            if proc.poll() is None:
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()

    def run_all(self) -> None:
        self.emit("CONTRACTBPF_NATIVE_MEMCACHED_BARS_BEGIN")
        self.emit(
            "native_memcached_config "
            f"ops_a={self.args.ops_a} ops_b={self.args.ops_b} "
            f"value_a={self.args.value_a} value_b={self.args.value_b} "
            f"file_mb={self.args.file_mb} pressure_mb={self.args.pressure_mb} "
            f"iterations={self.args.iterations} memory_high={self.args.memory_high} "
            f"pressure_mempolicy={self.pressure_mempolicy} "
            f"recovery_sleep_s={self.args.recovery_sleep_s} "
            f"conflict_warmup_s={self.args.conflict_warmup_s}"
        )
        self.setup_cgroups()
        self.start_memcached()
        self.run_baseline_group("G1", "Linux default scheduler plus default paging", False)
        self.run_baseline_group("G2", "sched_ext policy only", True)
        self.run_conflict_group("G4", "sched_ext plus bad paging natural conflict window", self.paging_norevoke_manifest)
        self.run_conflict_group("G9", "full ContractBPF-Ledger bounded degradation", self.paging_manifest)
        self.emit("CONTRACTBPF_NATIVE_MEMCACHED_BARS_OK")


def run_preflight(root: Path) -> int:
    proc = subprocess.run(
        [sys.executable, str(root / "experiments" / "runners" / "run_native_p5p6_preflight.py")],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    print(proc.stdout, end="")
    return proc.returncode


def blocked_artifact(root: Path, reason: str) -> Path:
    timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    log_path = root / "artifacts" / "logs" / f"{timestamp}-native-memcached-bars.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        "\n".join(
            [
                "CONTRACTBPF_NATIVE_MEMCACHED_BARS_BEGIN",
                f"blocked_reason={reason}",
                "CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED",
                "",
            ]
        ),
        encoding="utf-8",
    )
    return log_path


def main() -> int:
    args = parse_args()
    root = repo_root()
    if not args.skip_preflight:
        preflight = run_preflight(root)
        if preflight != 0:
            log_path = blocked_artifact(root, f"native preflight failed with exit {preflight}")
            print(f"native memcached bars log: {log_path}")
            print("CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED")
            return 2

    timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    log_path = root / "artifacts" / "logs" / f"{timestamp}-native-memcached-bars.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    runner: Optional[NativeRunner] = None
    try:
        with log_path.open("w", encoding="utf-8") as log:
            runner = NativeRunner(root, args, log)
            runner.run_all()
    finally:
        if runner:
            runner.cleanup()

    rows = summarize(parse_log(log_path))
    raw_dir = root / "experiments" / "results" / "raw"
    processed_dir = root / "experiments" / "results" / "processed"
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_copy = raw_dir / log_path.name
    shutil.copy2(log_path, raw_copy)
    for row in rows:
        row["raw_log"] = str(raw_copy)
        row["evidence_scope"] = "native_memcached"
    processed_csv = processed_dir / "native_memcached_bars.csv"
    write_csv(processed_csv, rows)
    validate(rows)
    print(f"raw log: {raw_copy}")
    print(f"processed native memcached bars: {processed_csv}")
    print("CONTRACTBPF_NATIVE_MEMCACHED_BARS_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
