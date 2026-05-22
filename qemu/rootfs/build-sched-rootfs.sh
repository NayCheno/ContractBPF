#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/sched-initramfs"
OUT="$ROOT/qemu/images/sched-ext-initramfs.cpio.gz"
SCX_SIMPLE="${SCX_SIMPLE:-$ROOT/build/scx/build/bin/scx_simple}"
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

if [ ! -x "$SCX_SIMPLE" ]; then
    echo "ERROR: scx_simple missing: $SCX_SIMPLE" >&2
    echo "Run: make -C build/linux/tools/sched_ext O=$ROOT/build/scx LLVM=1 scx_simple" >&2
    exit 1
fi

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/proc" "$WORK/sys" "$WORK/tmp" "$WORK/usr/local/bin" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/mount
copy_bin /bin/sleep
copy_bin "$SCX_SIMPLE" /usr/local/bin/scx_simple

cp "$ROOT/qemu/rootfs/sched-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built sched_ext initramfs: %s\n' "$OUT"

