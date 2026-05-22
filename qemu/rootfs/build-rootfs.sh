#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/initramfs"
OUT="$ROOT/qemu/images/initramfs.cpio.gz"
CC_BIN="${CC:-cc}"

for tool in "$CC_BIN" cpio gzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p "$WORK/dev" "$WORK/proc" "$WORK/sys" "$WORK/tmp" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/init" "$ROOT/qemu/rootfs/init.c"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built initramfs: %s\n' "$OUT"
