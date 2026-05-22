#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/mm-bpf-initramfs"
OUT="$ROOT/qemu/images/mm-bpf-initramfs.cpio.gz"
LOADER="${LOADER:-$ROOT/build/bpf/contract_mm_loader}"
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

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

if [ ! -x "$LOADER" ]; then
    echo "ERROR: contract_mm_loader missing: $LOADER" >&2
    echo "Run: make bpf" >&2
    exit 1
fi

for obj in phase_paging.bpf.o bad_demote.bpf.o conservative_noop_paging.bpf.o; do
    if [ ! -r "$BPF_OUT/$obj" ]; then
        echo "ERROR: BPF object missing: $BPF_OUT/$obj" >&2
        echo "Run: make bpf" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/proc" "$WORK/sys" "$WORK/usr/local/bin" "$WORK/usr/local/lib/contractbpf" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/mkdir
copy_bin /bin/mount
copy_bin "$LOADER" /usr/local/bin/contract_mm_loader
copy_one "$BPF_OUT/phase_paging.bpf.o" /usr/local/lib/contractbpf/phase_paging.bpf.o
copy_one "$BPF_OUT/bad_demote.bpf.o" /usr/local/lib/contractbpf/bad_demote.bpf.o
copy_one "$BPF_OUT/conservative_noop_paging.bpf.o" /usr/local/lib/contractbpf/conservative_noop_paging.bpf.o

cp "$ROOT/qemu/rootfs/mm-bpf-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built MM BPF initramfs: %s\n' "$OUT"
