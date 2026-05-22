#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/policy-identity-initramfs"
OUT="$ROOT/qemu/images/policy-identity-initramfs.cpio.gz"
SCX_BOOST="${SCX_BOOST:-$ROOT/build/scx/build/bin/scx_contract_boost}"
SCX_SIMPLE="${SCX_SIMPLE:-$ROOT/build/scx/build/bin/scx_simple}"
CONTRACTCTL="${CONTRACTCTL:-$ROOT/userspace/contractctl/target/debug/contractctl}"
MM_LOADER="${MM_LOADER:-$ROOT/build/bpf/contract_mm_loader}"
BPF_OUT="${BPF_OUT:-$ROOT/build/bpf}"
SYNTHETIC="${SYNTHETIC:-$ROOT/workloads/synthetic_phase_service/synthetic_phase_service}"
CC_BIN="${CC:-cc}"

copy_one() {
    local src="$1"
    local dst="$2"
    mkdir -p "$WORK$(dirname "$dst")"
    cp -L "$src" "$WORK$dst"
}

copy_deps() {
    local bin="$1"
    ldd "$bin" | awk '
        $2 == "=>" && $3 ~ /^\// { print $3 }
        $1 ~ /^\// { print $1 }
    ' | while IFS= read -r lib; do
        [ -n "$lib" ] || continue
        copy_one "$lib" "$lib"
    done
}

copy_bin() {
    local src="$1"
    local dst="${2:-$1}"
    copy_one "$src" "$dst"
    copy_deps "$src"
}

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

for bin in "$SCX_BOOST" "$SCX_SIMPLE" "$CONTRACTCTL" "$MM_LOADER" "$SYNTHETIC"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: required binary missing: $bin" >&2
        exit 1
    fi
done

for obj in phase_paging.bpf.o bad_demote.bpf.o; do
    if [ ! -r "$BPF_OUT/$obj" ]; then
        echo "ERROR: BPF object missing: $BPF_OUT/$obj" >&2
        echo "Run: make bpf" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p \
    "$WORK/bin" \
    "$WORK/dev" \
    "$WORK/etc/contractbpf" \
    "$WORK/proc" \
    "$WORK/sys/fs/bpf" \
    "$WORK/sys/fs/cgroup" \
    "$WORK/sys/kernel/debug" \
    "$WORK/tmp" \
    "$WORK/usr/local/bin" \
    "$WORK/usr/local/lib/contractbpf" \
    "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/grep
copy_bin /bin/mkdir
copy_bin /bin/mount
copy_bin /bin/sed
copy_bin /bin/sleep
copy_bin "$SCX_BOOST" /usr/local/bin/scx_contract_boost
copy_bin "$SCX_SIMPLE" /usr/local/bin/scx_simple
copy_bin "$CONTRACTCTL" /usr/local/bin/contractctl
copy_bin "$MM_LOADER" /usr/local/bin/contract_mm_loader
copy_bin "$SYNTHETIC" /usr/local/bin/synthetic_phase_service

copy_one "$BPF_OUT/phase_paging.bpf.o" /usr/local/lib/contractbpf/phase_paging.bpf.o
copy_one "$BPF_OUT/bad_demote.bpf.o" /usr/local/lib/contractbpf/bad_demote.bpf.o

cp "$ROOT/bpf/contracts/service_a_sched.yaml" "$WORK/etc/contractbpf/service_a_sched.yaml"
cp "$ROOT/bpf/contracts/service_b_sched.yaml" "$WORK/etc/contractbpf/service_b_sched.yaml"

cp "$ROOT/qemu/rootfs/policy-identity-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built policy identity initramfs: %s\n' "$OUT"
