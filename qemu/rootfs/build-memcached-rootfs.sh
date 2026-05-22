#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/memcached-initramfs"
PKG_ROOT="$ROOT/build/memcached-pkgs/root"
DEB_DIR="$ROOT/build/memcached-pkgs/debs"
OUT="$ROOT/qemu/images/memcached-initramfs.cpio.gz"
LOAD_BIN="${LOAD_BIN:-$ROOT/workloads/memcached/memcached_ascii_load}"
CC_BIN="${CC:-cc}"

copy_one() {
    local src="$1"
    local dst="$2"
    mkdir -p "$WORK$(dirname "$dst")"
    cp -L "$src" "$WORK$dst"
}

dep_dst() {
    local src="$1"
    case "$src" in
        "$PKG_ROOT"/*) printf '%s\n' "${src#$PKG_ROOT}" ;;
        *) printf '%s\n' "$src" ;;
    esac
}

copy_deps() {
    local bin="$1"
    LD_LIBRARY_PATH="$PKG_ROOT/lib/x86_64-linux-gnu:$PKG_ROOT/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" \
        ldd "$bin" | awk '
            $2 == "=>" && $3 ~ /^\// { print $3 }
            $1 ~ /^\// { print $1 }
        ' | while IFS= read -r lib; do
            [ -n "$lib" ] || continue
            copy_one "$lib" "$(dep_dst "$lib")"
        done
}

copy_bin() {
    local src="$1"
    local dst="${2:-$1}"
    copy_one "$src" "$dst"
    copy_deps "$src"
}

prepare_memcached() {
    if [ -n "${MEMCACHED_BIN:-}" ]; then
        if [ ! -x "$MEMCACHED_BIN" ]; then
            echo "ERROR: MEMCACHED_BIN is not executable: $MEMCACHED_BIN" >&2
            exit 1
        fi
        printf '%s\n' "$MEMCACHED_BIN"
        return
    fi

    if command -v memcached >/dev/null 2>&1; then
        command -v memcached
        return
    fi

    for tool in apt-get dpkg-deb; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: memcached unavailable and required tool missing: $tool" >&2
            exit 1
        fi
    done

    mkdir -p "$DEB_DIR" "$PKG_ROOT"
    if [ ! -x "$PKG_ROOT/usr/bin/memcached" ]; then
        (
            cd "$DEB_DIR"
            apt-get download memcached libevent-2.1-7t64 libsasl2-2 libssl3t64 >&2
        )
        for deb in "$DEB_DIR"/*.deb; do
            dpkg-deb -x "$deb" "$PKG_ROOT" >&2
        done
    fi

    if [ ! -x "$PKG_ROOT/usr/bin/memcached" ]; then
        echo "ERROR: downloaded memcached package did not provide usr/bin/memcached" >&2
        exit 1
    fi
    printf '%s\n' "$PKG_ROOT/usr/bin/memcached"
}

for tool in "$CC_BIN" cpio gzip ldd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing: $tool" >&2
        exit 1
    fi
done

if [ ! -x "$LOAD_BIN" ]; then
    echo "ERROR: memcached load client missing: $LOAD_BIN" >&2
    echo "Run: make -C $ROOT/workloads/memcached" >&2
    exit 1
fi

MEMCACHED_REAL_BIN="$(prepare_memcached)"

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/dev" "$WORK/etc" "$WORK/proc" "$WORK/sys/kernel/debug" "$WORK/sys/fs/cgroup" "$WORK/tmp" "$WORK/usr/local/bin" "$(dirname "$OUT")"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$WORK/etc/passwd"
printf 'root:x:0:\n' > "$WORK/etc/group"

"$CC_BIN" -Os -static -Wall -Wextra -o "$WORK/bin/poweroff-contractbpf" "$ROOT/qemu/rootfs/poweroff.c"
chmod 0755 "$WORK/bin/poweroff-contractbpf"

copy_bin /bin/sh
copy_bin /bin/cat
copy_bin /bin/kill
copy_bin /bin/mount
copy_bin /bin/sleep
copy_bin "$MEMCACHED_REAL_BIN" /usr/local/bin/memcached
copy_bin "$LOAD_BIN" /usr/local/bin/memcached_ascii_load

cp "$ROOT/qemu/rootfs/memcached-init.sh" "$WORK/init"
chmod 0755 "$WORK/init"

(
    cd "$WORK"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$OUT"

printf 'Built memcached initramfs: %s\n' "$OUT"
