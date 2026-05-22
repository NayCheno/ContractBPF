#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/contractd-initramfs"
OUT="$ROOT/qemu/images/contractd-initramfs.cpio.gz"
CONTRACTD="${CONTRACTD:-$ROOT/userspace/contractd/target/debug/contractd}"
CONTRACTCTL="${CONTRACTCTL:-$ROOT/userspace/contractctl/target/debug/contractctl}"
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

if [ ! -x "$CONTRACTD" ]; then
    echo "ERROR: contractd missing: $CONTRACTD" >&2
    echo "Run: cargo build --manifest-path $ROOT/userspace/contractd/Cargo.toml" >&2
    exit 1
fi

if [ ! -x "$CONTRACTCTL" ]; then
    echo "ERROR: contractctl missing: $CONTRACTCTL" >&2
    echo "Run: cargo build --manifest-path $ROOT/userspace/contractctl/Cargo.toml" >&2
    exit 1
fi

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/etc/contractbpf" "$WORK/proc" "$WORK/sys/kernel/debug" "$WORK/sys/fs/cgroup" "$WORK/tmp" "$WORK/usr/local/bin" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/grep
copy_bin /bin/mkdir
copy_bin /bin/mount
copy_bin "$CONTRACTD" /usr/local/bin/contractd
copy_bin "$CONTRACTCTL" /usr/local/bin/contractctl
cp "$ROOT/bpf/contracts/service_a_sched.yaml" "$WORK/etc/contractbpf/service_a_sched.yaml"
cp "$ROOT/bpf/contracts/service_a_paging.yaml" "$WORK/etc/contractbpf/service_a_paging.yaml"
cp "$ROOT/bpf/contracts/service_a_composition.yaml" "$WORK/etc/contractbpf/service_a_composition.yaml"
cp "$ROOT/bpf/contracts/service_b_sched.yaml" "$WORK/etc/contractbpf/service_b_sched.yaml"
cp "$ROOT/bpf/contracts/service_b_paging.yaml" "$WORK/etc/contractbpf/service_b_paging.yaml"

cp "$ROOT/qemu/rootfs/contractd-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built contractd initramfs: %s\n' "$OUT"
