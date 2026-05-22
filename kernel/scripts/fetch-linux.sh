#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="$(tr -d '[:space:]' < "$ROOT/kernel/versions/pinned-kernel.txt")"
VERSION="${PIN#linux-}"
MAJOR="${VERSION%%.*}"
SRC_DIR="${CONTRACTBPF_LINUX_DIR:-$ROOT/build/linux}"
DOWNLOAD_DIR="$ROOT/build/downloads"
TARBALL="$DOWNLOAD_DIR/linux-$VERSION.tar.xz"
URL="${KERNEL_TARBALL_URL:-https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${VERSION}.tar.xz}"

mkdir -p "$DOWNLOAD_DIR" "$ROOT/artifacts/logs"

if [ ! -f "$TARBALL" ]; then
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$URL" -o "$TARBALL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TARBALL" "$URL"
    else
        echo "ERROR: curl or wget is required to fetch $URL" >&2
        exit 1
    fi
fi

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
tar -xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

printf 'Fetched %s into %s\n' "$URL" "$SRC_DIR"

