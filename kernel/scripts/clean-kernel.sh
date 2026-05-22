#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${CONTRACTBPF_LINUX_DIR:-$ROOT/build/linux}"

if [ -d "$SRC_DIR" ]; then
    make -C "$SRC_DIR" clean
fi

