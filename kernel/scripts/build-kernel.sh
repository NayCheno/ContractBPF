#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${CONTRACTBPF_LINUX_DIR:-$ROOT/build/linux}"
LOG_DIR="$ROOT/artifacts/logs"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/${STAMP}-kernel-build.log"
JOBS="${JOBS:-$(nproc)}"

if [ ! -f "$SRC_DIR/.config" ]; then
    echo "ERROR: kernel config missing at $SRC_DIR/.config. Run make bootstrap first." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

{
    printf 'Command: make -C %s -j%s bzImage\n' "$SRC_DIR" "$JOBS"
    printf 'Started: %s\n' "$STAMP"
} > "$LOG"

make -C "$SRC_DIR" -j"$JOBS" bzImage 2>&1 | tee -a "$LOG"

if [ ! -f "$SRC_DIR/arch/x86/boot/bzImage" ]; then
    echo "ERROR: bzImage missing after build" | tee -a "$LOG" >&2
    exit 1
fi

printf 'Kernel image: %s\n' "$SRC_DIR/arch/x86/boot/bzImage" | tee -a "$LOG"

