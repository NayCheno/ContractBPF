#!/usr/bin/env python3
"""Run native mature-gate evidence on a ContractBPF-capable SSH host."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, List, Optional, TextIO


SYNC_EXCLUDES = [
    ".git/",
    ".cache/",
    ".pytest_cache/",
    ".mypy_cache/",
    ".ruff_cache/",
    ".venv/",
    "venv/",
    "env/",
    "build/",
    "out/",
    "linux/",
    "linux-*/",
    "linux-*.tar.*",
    "**/target/",
    "artifacts/repro/",
    "experiments/artifact_bundles/",
    "*.aux",
    "*.bbl",
    "*.bcf",
    "*.blg",
    "*.fdb_latexmk",
    "*.fls",
    "*.out",
    "*.run.xml",
    "*.synctex.gz",
    "*.toc",
    "*.tmp",
    "*.temp",
]

FETCH_DIRS = [
    "artifacts/logs",
    "experiments/results/raw",
    "experiments/results/processed",
    "experiments/results/figures",
    "docs/audits",
    "artifacts/repro",
    "experiments/artifact_bundles",
]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def env_flag(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def env_value(name: str, default: str) -> str:
    return os.environ.get(name) or default


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sync the current repo/evidence to an SSH host, run the privileged "
            "native Docker mature-gate flow there, and fetch native evidence back."
        )
    )
    parser.add_argument("--host", default=os.environ.get("CONTRACTBPF_REMOTE", ""))
    parser.add_argument("--remote-dir", default=env_value("CONTRACTBPF_REMOTE_DIR", "~/ContractBPF-native"))
    parser.add_argument("--ssh", default=env_value("CONTRACTBPF_SSH", "ssh"))
    parser.add_argument("--rsync", default=env_value("CONTRACTBPF_RSYNC", "rsync"))
    parser.add_argument(
        "--ssh-option",
        action="append",
        default=[],
        help="Extra option passed to ssh; may be repeated.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        default=env_flag("CONTRACTBPF_REMOTE_SKIP_BUILD"),
        help="Skip 'docker compose build contractbpf' on the remote host.",
    )
    return parser.parse_args()


def timestamp() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")


def command_text(argv: List[str]) -> str:
    return " ".join(shlex.quote(part) for part in argv)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def emit(log: TextIO, line: str = "") -> None:
    print(line, file=log, flush=True)
    print(line, flush=True)


def split_env_options() -> List[str]:
    value = os.environ.get("CONTRACTBPF_SSH_OPTIONS", "").strip()
    if not value:
        return []
    return shlex.split(value)


def ssh_options(args: argparse.Namespace) -> List[str]:
    return [*split_env_options(), *args.ssh_option]


def remote_dir_is_safe(remote_dir: str) -> bool:
    stripped = remote_dir.strip()
    return stripped not in {"", "/", "~", "~/", ".", ".."}


def quote_remote_path(path: str) -> str:
    if path == "~":
        return "~"
    if path.startswith("~/"):
        rest = path[2:]
        if not rest:
            return "~/"
        return "~/" + "/".join(shlex.quote(part) for part in rest.split("/"))
    return shlex.quote(path)


def remote_child(remote_dir: str, child: str) -> str:
    return remote_dir.rstrip("/") + "/" + child.strip("/")


def remote_spec(host: str, remote_dir: str, child: str = "") -> str:
    path = remote_dir.rstrip("/")
    if child:
        path = remote_child(path, child)
    return f"{host}:{path.rstrip('/')}/"


def run(argv: List[str], cwd: Path, log: TextIO) -> subprocess.CompletedProcess[str]:
    emit(log, "$ " + command_text(argv))
    proc = subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.stdout:
        log.write(proc.stdout)
        if not proc.stdout.endswith("\n"):
            log.write("\n")
        log.flush()
        print(proc.stdout, end="" if proc.stdout.endswith("\n") else "\n")
    emit(log, f"exit_code={proc.returncode}")
    return proc


def ssh_argv(args: argparse.Namespace, remote_command: str) -> List[str]:
    return [args.ssh, *ssh_options(args), args.host, remote_command]


def rsync_transport(args: argparse.Namespace) -> str:
    return command_text([args.ssh, *ssh_options(args)])


def rsync_push(args: argparse.Namespace, root: Path, log: TextIO) -> subprocess.CompletedProcess[str]:
    argv = [
        args.rsync,
        "-az",
        "--delete",
        "--protect-args",
        "-e",
        rsync_transport(args),
    ]
    for pattern in SYNC_EXCLUDES:
        argv.extend(["--exclude", pattern])
    argv.extend([str(root) + "/", remote_spec(args.host, args.remote_dir)])
    return run(argv, root, log)


def rsync_fetch(args: argparse.Namespace, root: Path, rel: str, log: TextIO) -> bool:
    target = root / rel
    target.mkdir(parents=True, exist_ok=True)
    probe = run(ssh_argv(args, f"test -d {quote_remote_path(remote_child(args.remote_dir, rel))}"), root, log)
    if probe.returncode != 0:
        emit(log, f"fetch_skip={rel}")
        return False
    argv = [
        args.rsync,
        "-az",
        "--protect-args",
        "-e",
        rsync_transport(args),
        remote_spec(args.host, args.remote_dir, rel),
        str(target) + "/",
    ]
    return run(argv, root, log).returncode == 0


def remote_script(args: argparse.Namespace) -> str:
    remote_dir = quote_remote_path(args.remote_dir)
    inner = (
        "make native-p5p6-bars && "
        "make paper-tables && "
        "python3 experiments/runners/archive_repro.py --command "
        + shlex.quote("remote native P5/P6 bars pre-audit archive")
        + " && "
        "make acceptance-audit && "
        "python3 experiments/runners/archive_repro.py --command "
        + shlex.quote("remote native mature gates and acceptance audit")
    )
    steps = ["set -euo pipefail", f"cd {remote_dir}"]
    if not args.skip_build:
        steps.append("docker compose build contractbpf")
    steps.append(
        "docker compose -f docker-compose.yml -f docker-compose.native.yml "
        "run --rm contractbpf bash -lc "
        + shlex.quote(inner)
    )
    return " && ".join(steps)


def blocked_payload(ts: str, log_path: Path, missing: List[str], args: argparse.Namespace) -> dict[str, Any]:
    return {
        "timestamp_utc": ts,
        "purpose": "remote native non-QEMU mature-gate executor",
        "status": "blocked",
        "remote_configured": bool(args.host),
        "host": args.host,
        "remote_dir": args.remote_dir,
        "missing": missing,
        "log": str(log_path),
    }


def final_payload(
    ts: str,
    log_path: Path,
    args: argparse.Namespace,
    status: str,
    remote_exit_code: Optional[int],
    fetched: List[str],
    local_audit_exit_code: Optional[int],
    local_archive_exit_code: Optional[int],
) -> dict[str, Any]:
    return {
        "timestamp_utc": ts,
        "purpose": "remote native non-QEMU mature-gate executor",
        "status": status,
        "remote_configured": bool(args.host),
        "host": args.host,
        "remote_dir": args.remote_dir,
        "remote_exit_code": remote_exit_code,
        "fetched": fetched,
        "local_audit_exit_code": local_audit_exit_code,
        "local_archive_exit_code": local_archive_exit_code,
        "log": str(log_path),
    }


def main() -> int:
    args = parse_args()
    root = repo_root()
    ts = timestamp()
    log_path = root / "artifacts" / "logs" / f"{ts}-remote-native-mature-gates.log"
    out_path = root / "experiments" / "results" / "processed" / "remote_native_mature_gates.json"
    log_path.parent.mkdir(parents=True, exist_ok=True)

    with log_path.open("w", encoding="utf-8") as log:
        emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_BEGIN")
        missing: List[str] = []
        if not args.host:
            missing.append("CONTRACTBPF_REMOTE/--host not set")
        if not remote_dir_is_safe(args.remote_dir):
            missing.append(f"unsafe remote directory: {args.remote_dir!r}")
        if args.host:
            if shutil.which(args.ssh) is None:
                missing.append(f"ssh executable missing: {args.ssh}")
            if shutil.which(args.rsync) is None:
                missing.append(f"rsync executable missing: {args.rsync}")

        if missing:
            payload = blocked_payload(ts, log_path, missing, args)
            emit(log, json.dumps(payload, indent=2, sort_keys=True))
            emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_BLOCKED")
            write_json(out_path, payload)
            return 2

        mkdir = run(ssh_argv(args, f"mkdir -p {quote_remote_path(args.remote_dir)}"), root, log)
        if mkdir.returncode != 0:
            payload = final_payload(ts, log_path, args, "failed", mkdir.returncode, [], None, None)
            emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_REMOTE_PREP_FAILED")
            write_json(out_path, payload)
            return 1

        push = rsync_push(args, root, log)
        if push.returncode != 0:
            payload = final_payload(ts, log_path, args, "failed", push.returncode, [], None, None)
            emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_SYNC_FAILED")
            write_json(out_path, payload)
            return 1

        remote = run(ssh_argv(args, remote_script(args)), root, log)
        fetched: List[str] = []
        for rel in FETCH_DIRS:
            if rsync_fetch(args, root, rel, log):
                fetched.append(rel)

        if remote.returncode != 0:
            payload = final_payload(ts, log_path, args, "failed", remote.returncode, fetched, None, None)
            emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_REMOTE_COMMAND_FAILED")
            write_json(out_path, payload)
            return remote.returncode if remote.returncode < 125 else 1

        audit = run([sys.executable, str(root / "experiments" / "runners" / "acceptance_gate_audit.py")], root, log)
        archive: Optional[subprocess.CompletedProcess[str]] = None
        if audit.returncode == 0:
            archive = run(
                [
                    sys.executable,
                    str(root / "experiments" / "runners" / "archive_repro.py"),
                    "--command",
                    "make remote-native-mature-gates",
                ],
                root,
                log,
            )

        local_archive_exit = archive.returncode if archive is not None else None
        status = "complete" if audit.returncode == 0 and local_archive_exit == 0 else "incomplete"
        payload = final_payload(
            ts,
            log_path,
            args,
            status,
            remote.returncode,
            fetched,
            audit.returncode,
            local_archive_exit,
        )
        write_json(out_path, payload)
        if status == "complete":
            emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_OK")
            return 0
        emit(log, "CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_INCOMPLETE")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
