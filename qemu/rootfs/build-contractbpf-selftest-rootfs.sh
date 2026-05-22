#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/contractbpf-selftest-initramfs"
OUT="$ROOT/qemu/images/contractbpf-selftest-initramfs.cpio.gz"
SELFTEST="${SELFTEST:-$ROOT/build/linux/tools/testing/selftests/contractbpf/contractbpf_selftest.sh}"
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

if [ ! -f "$SELFTEST" ]; then
    echo "ERROR: ContractBPF selftest missing: $SELFTEST" >&2
    exit 1
fi

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/proc" "$WORK/sys/kernel/debug" "$WORK/tmp" "$WORK/usr/local/bin" "$(dirname "$OUT")"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/grep
copy_bin /bin/mount

cp "$SELFTEST" "$WORK/usr/local/bin/contractbpf_selftest.sh"
chmod 0755 "$WORK/usr/local/bin/contractbpf_selftest.sh"

cp "$ROOT/qemu/rootfs/contractbpf-selftest-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built ContractBPF selftest initramfs: %s\n' "$OUT"

