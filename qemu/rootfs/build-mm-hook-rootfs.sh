#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/mm-hook-initramfs"
OUT="$ROOT/qemu/images/mm-hook-initramfs.cpio.gz"
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

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/proc" "$WORK/sys/kernel/debug" "$WORK/tmp" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/grep
copy_bin /bin/mount

cp "$ROOT/qemu/rootfs/mm-hook-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built MM hook initramfs: %s\n' "$OUT"
