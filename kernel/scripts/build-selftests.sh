#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${CONTRACTBPF_LINUX_DIR:-$ROOT/build/linux}"

if [ ! -d "$SRC_DIR/tools/testing/selftests" ]; then
    echo "ERROR: Linux selftests not found at $SRC_DIR/tools/testing/selftests" >&2
    exit 1
fi

make -C "$SRC_DIR/tools/testing/selftests" TARGETS="${TARGETS:-contractbpf}"
