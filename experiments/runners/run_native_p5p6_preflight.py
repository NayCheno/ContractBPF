#!/usr/bin/env python3
"""Check whether the current Docker container can run native P5/P6 evidence."""

from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def command_output(args: List[str]) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as err:
        return f"unavailable: {err}"


def check(name: str, required: bool, ok: bool, detail: str) -> Dict[str, Any]:
    return {"name": name, "required": required, "ok": ok, "detail": detail}


def check_contract_device() -> List[Dict[str, Any]]:
    device = Path(os.environ.get("CONTRACTBPF_DEVICE", "/dev/contractbpf"))
    rows: List[Dict[str, Any]] = []
    if not device.exists():
        return [
            check(
                "contractbpf_device_exists",
                True,
                False,
                f"{device} is missing; native final P5/P6 requires a host kernel with ContractBPF loaded",
            )
        ]
    mode = device.stat().st_mode
    rows.append(
        check(
            "contractbpf_device_is_char",
            True,
            stat.S_ISCHR(mode),
            f"{device} mode={oct(mode)}",
        )
    )
    rows.append(
        check(
            "contractbpf_device_read_write",
            True,
            os.access(device, os.R_OK | os.W_OK),
            f"{device} access rw={os.access(device, os.R_OK | os.W_OK)}",
        )
    )
    return rows


def check_cgroup() -> List[Dict[str, Any]]:
    root = Path(os.environ.get("CONTRACTBPF_CGROUP_ROOT", "/sys/fs/cgroup"))
    controllers_path = root / "cgroup.controllers"
    controllers = read_text(controllers_path).split()
    rows = [
        check(
            "cgroup_v2_mounted",
            True,
            controllers_path.exists(),
            f"{controllers_path}",
        ),
        check(
            "memory_controller_available",
            True,
            "memory" in controllers,
            f"controllers={' '.join(controllers) if controllers else 'unavailable'}",
        ),
    ]

    probe = root / f"contractbpf-preflight-{os.getpid()}"
    created = False
    try:
        probe.mkdir()
        created = True
    except OSError as err:
        rows.append(check("cgroup_root_writable", True, False, str(err)))
    else:
        rows.append(check("cgroup_root_writable", True, True, str(probe)))
        try:
            probe.rmdir()
        except OSError:
            pass
        created = False
    if created:
        try:
            probe.rmdir()
        except OSError:
            pass
    return rows


def check_sched_ext() -> List[Dict[str, Any]]:
    state_path = Path("/sys/kernel/sched_ext/state")
    state = read_text(state_path)
    return [
        check(
            "sched_ext_state_available",
            True,
            state_path.exists(),
            f"{state_path} value={state or 'unavailable'}",
        )
    ]


def check_memory_tiering() -> List[Dict[str, Any]]:
    tier_root = Path("/sys/devices/virtual/memory_tiering")
    tiers = sorted(tier_root.glob("memory_tier*/nodelist"))
    demotion_path = Path("/sys/kernel/mm/numa/demotion_enabled")
    demotion_enabled = read_text(demotion_path)
    tier_detail = ", ".join(f"{path.parent.name}:{read_text(path)}" for path in tiers) or "unavailable"
    return [
        check(
            "memory_tiering_has_multiple_tiers",
            True,
            len(tiers) >= 2,
            tier_detail,
        ),
        check(
            "numa_demotion_enabled",
            True,
            demotion_enabled == "true",
            f"{demotion_path} value={demotion_enabled or 'unavailable'}",
        ),
    ]


def check_executable(name: str, path: Path) -> Dict[str, Any]:
    return check(name, True, path.exists() and os.access(path, os.X_OK), str(path))


def check_file(name: str, path: Path) -> Dict[str, Any]:
    return check(name, True, path.is_file(), str(path))


def check_tools(root: Path) -> List[Dict[str, Any]]:
    contractctl = root / "userspace" / "contractctl" / "target" / "debug" / "contractctl"
    return [
        check_executable("contractctl_built", contractctl),
        check_executable(
            "scx_contract_boost_built",
            root / "build" / "scx" / "build" / "bin" / "scx_contract_boost",
        ),
        check_executable("contract_mm_loader_built", root / "build" / "bpf" / "contract_mm_loader"),
        check_file("bad_demote_bpf_object_built", root / "build" / "bpf" / "bad_demote.bpf.o"),
        check_executable(
            "memcached_ascii_load_built",
            root / "workloads" / "memcached" / "memcached_ascii_load",
        ),
        check_executable("memory_pressure_built", root / "workloads" / "memory_pressure" / "pressure"),
        check("memcached_binary_available", True, shutil.which("memcached") is not None, shutil.which("memcached") or "missing"),
    ]


def environment_metadata() -> Dict[str, str]:
    return {
        "uname": command_output(["uname", "-a"]),
        "kernel_release": command_output(["uname", "-r"]),
        "product_name": read_text(Path("/sys/class/dmi/id/product_name")) or "unavailable",
        "product_version": read_text(Path("/sys/class/dmi/id/product_version")) or "unavailable",
        "cmdline": read_text(Path("/proc/cmdline")) or "unavailable",
    }


def write_log(log_path: Path, payload: Dict[str, Any]) -> None:
    lines = [
        "CONTRACTBPF_NATIVE_P5P6_PREFLIGHT_BEGIN",
        json.dumps(payload, indent=2, sort_keys=True),
    ]
    for row in payload["checks"]:
        status = "OK" if row["ok"] else "FAIL"
        required = "required" if row["required"] else "optional"
        lines.append(f"check {status} {required} {row['name']} detail={row['detail']}")
    if payload["preflight_ok"]:
        lines.append("CONTRACTBPF_NATIVE_P5P6_PREFLIGHT_OK")
    else:
        lines.append("CONTRACTBPF_NATIVE_P5P6_PREFLIGHT_BLOCKED")
    log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    root = repo_root()
    timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    log_path = root / "artifacts" / "logs" / f"{timestamp}-native-p5p6-preflight.log"
    out_path = root / "experiments" / "results" / "processed" / "native_p5p6_preflight.json"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    checks: List[Dict[str, Any]] = []
    checks.extend(check_contract_device())
    checks.extend(check_cgroup())
    checks.extend(check_sched_ext())
    checks.extend(check_memory_tiering())
    checks.extend(check_tools(root))

    required_failures = [row for row in checks if row["required"] and not row["ok"]]
    payload: Dict[str, Any] = {
        "timestamp_utc": timestamp,
        "purpose": "native non-QEMU P5/P6 final-evidence preflight",
        "preflight_ok": not required_failures,
        "required_failures": required_failures,
        "environment": environment_metadata(),
        "checks": checks,
        "log": str(log_path),
    }
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_log(log_path, payload)

    print(f"native P5/P6 preflight log: {log_path}")
    print(f"native P5/P6 preflight json: {out_path}")
    if required_failures:
        for row in required_failures:
            print(f"FAIL {row['name']}: {row['detail']}")
        print("CONTRACTBPF_NATIVE_P5P6_PREFLIGHT_BLOCKED")
        return 1
    print("CONTRACTBPF_NATIVE_P5P6_PREFLIGHT_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
