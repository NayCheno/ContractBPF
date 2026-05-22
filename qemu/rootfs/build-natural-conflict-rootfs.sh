#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/natural-conflict-initramfs"
OUT="$ROOT/qemu/images/natural-conflict-initramfs.cpio.gz"
SCX_BOOST="${SCX_BOOST:-$ROOT/build/scx/build/bin/scx_contract_boost}"
SYNTH="${SYNTH:-$ROOT/workloads/synthetic_phase_service/synthetic_phase_service}"
PRESSURE="${PRESSURE:-$ROOT/workloads/memory_pressure/pressure}"
CONTRACTCTL="${CONTRACTCTL:-$ROOT/userspace/contractctl/target/debug/contractctl}"
MM_LOADER="${MM_LOADER:-$ROOT/build/bpf/contract_mm_loader}"
BPF_OUT="${BPF_OUT:-$ROOT/build/bpf}"
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

copy_tool() {
    local tool="$1"
    local path

    path="$(command -v "$tool")"
    copy_bin "$path"
}

if [ ! -x "$SCX_BOOST" ]; then
    echo "ERROR: scx_contract_boost missing: $SCX_BOOST" >&2
    echo "Run: make -C build/linux/tools/sched_ext O=$ROOT/build/scx LLVM=1 scx_contract_boost" >&2
    exit 1
fi

if [ ! -x "$SYNTH" ]; then
    echo "ERROR: synthetic_phase_service missing: $SYNTH" >&2
    echo "Run: make -C $ROOT/workloads/synthetic_phase_service" >&2
    exit 1
fi

if [ ! -x "$PRESSURE" ]; then
    echo "ERROR: memory pressure workload missing: $PRESSURE" >&2
    echo "Run: make -C $ROOT/workloads/memory_pressure" >&2
    exit 1
fi

if [ ! -x "$CONTRACTCTL" ]; then
    echo "ERROR: contractctl missing: $CONTRACTCTL" >&2
    echo "Run: cargo build --manifest-path $ROOT/userspace/contractctl/Cargo.toml" >&2
    exit 1
fi

if [ ! -x "$MM_LOADER" ]; then
    echo "ERROR: contract_mm_loader missing: $MM_LOADER" >&2
    echo "Run: make -C $ROOT/bpf" >&2
    exit 1
fi

if [ ! -f "$BPF_OUT/bad_demote.bpf.o" ]; then
    echo "ERROR: bad_demote BPF object missing: $BPF_OUT/bad_demote.bpf.o" >&2
    echo "Run: make -C $ROOT/bpf" >&2
    exit 1
fi

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/etc/contractbpf" \
    "$WORK/mnt/host" "$WORK/proc" "$WORK/sys/kernel/debug" \
    "$WORK/sys/fs/cgroup" "$WORK/tmp" "$WORK/usr/local/bin" \
    "$WORK/usr/local/lib/contractbpf" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/grep
copy_bin /bin/mkdir
copy_bin /bin/mount
copy_bin /bin/rm
copy_bin /bin/sed
copy_bin /bin/sleep
copy_bin "$SCX_BOOST" /usr/local/bin/scx_contract_boost
copy_bin "$SYNTH" /usr/local/bin/synthetic_phase_service
copy_bin "$PRESSURE" /usr/local/bin/memory_pressure
copy_bin "$CONTRACTCTL" /usr/local/bin/contractctl
copy_bin "$MM_LOADER" /usr/local/bin/contract_mm_loader
copy_one "$BPF_OUT/bad_demote.bpf.o" /usr/local/lib/contractbpf/bad_demote.bpf.o
cp "$ROOT/bpf/contracts/service_a_sched_natural.yaml" "$WORK/etc/contractbpf/service_a_sched_natural.yaml"
cp "$ROOT/bpf/contracts/service_a_paging.yaml" "$WORK/etc/contractbpf/service_a_paging.yaml"
cp "$ROOT/bpf/contracts/service_b_sched.yaml" "$WORK/etc/contractbpf/service_b_sched.yaml"
cp "$ROOT/bpf/contracts/service_b_paging.yaml" "$WORK/etc/contractbpf/service_b_paging.yaml"

cp "$ROOT/qemu/rootfs/natural-conflict-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built natural conflict initramfs: %s\n' "$OUT"
