#!/usr/bin/env python3
"""Archive ContractBPF repro logs and processed evidence into a tar.zst bundle."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def copy_tree(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    for path in src.rglob("*"):
        rel = path.relative_to(src)
        target = dst / rel
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif path.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_output(args: list[str], cwd: Path) -> str:
    try:
        return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as err:  # pragma: no cover - best-effort metadata.
        return f"unavailable: {err}"


def write_metadata(root: Path, out_dir: Path, command: str) -> None:
    patches = sorted((root / "kernel" / "patches").glob("*.patch"))
    with (out_dir / "metadata.txt").open("w", encoding="utf-8") as handle:
        handle.write(f"timestamp_utc={out_dir.name}\n")
        handle.write(f"command={command}\n")
        handle.write(f"git_head={command_output(['git', 'rev-parse', 'HEAD'], root)}\n")
        handle.write(f"git_status={command_output(['git', 'status', '--short'], root)}\n")
        handle.write(f"docker_image={os.environ.get('HOSTNAME', 'unknown')}\n")
        handle.write(f"kernel_source={os.environ.get('CONTRACTBPF_LINUX_DIR', str(root / 'build' / 'linux'))}\n")
        for patch in patches:
            handle.write(f"patch_sha256 {patch.name} {file_sha256(patch)}\n")

    transcript = out_dir / "command_transcript.txt"
    transcript.write_text(
        "\n".join(
            [
                command,
                "",
                "Individual command logs are stored under logs/ and raw/. This file records the",
                "prototype-gate command that produced the archived evidence bundle.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def make_tar(root: Path, out_dir: Path, bundle_dir: Path) -> Path:
    bundle_dir.mkdir(parents=True, exist_ok=True)
    tar_path = bundle_dir / f"{out_dir.name}.tar"
    zst_path = bundle_dir / f"{out_dir.name}.tar.zst"
    if tar_path.exists():
        tar_path.unlink()
    if zst_path.exists():
        zst_path.unlink()

    subprocess.check_call(["tar", "-cf", str(tar_path), "-C", str(out_dir.parent), out_dir.name], cwd=root)
    subprocess.check_call(["zstd", "-q", "-f", str(tar_path), "-o", str(zst_path)], cwd=root)
    tar_path.unlink()
    return zst_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timestamp", default=dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ"))
    parser.add_argument(
        "--command",
        default=(
            "make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate "
            "qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery "
            "experiments memcached-experiments"
        ),
    )
    args = parser.parse_args()

    root = repo_root()
    out_dir = root / "artifacts" / "repro" / args.timestamp
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    copy_tree(root / "artifacts" / "logs", out_dir / "logs")
    copy_tree(root / "experiments" / "results" / "raw", out_dir / "raw")
    copy_tree(root / "experiments" / "results" / "processed", out_dir / "processed")
    copy_tree(root / "experiments" / "results" / "figures", out_dir / "figures")
    copy_tree(root / "paper" / "nsdi27", out_dir / "paper_nsdi27")
    copy_tree(root / "docs" / "audits", out_dir / "audits")
    status_path = root / "STATUS.md"
    if status_path.exists():
        shutil.copy2(status_path, out_dir / "STATUS.md")
    write_metadata(root, out_dir, args.command)

    bundle = make_tar(root, out_dir, root / "experiments" / "artifact_bundles")
    print(f"Archived repro evidence: {out_dir}")
    print(f"Bundle: {bundle}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
