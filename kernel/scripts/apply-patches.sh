#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${CONTRACTBPF_LINUX_DIR:-$ROOT/build/linux}"
SERIES="$ROOT/kernel/patches/series"

if [ ! -d "$SRC_DIR" ]; then
    echo "ERROR: Linux source not found at $SRC_DIR. Run make bootstrap first." >&2
    exit 1
fi

if [ ! -f "$SERIES" ]; then
    echo "ERROR: patch series not found at $SERIES" >&2
    exit 1
fi

applied=0
while IFS= read -r patch_name; do
    case "$patch_name" in
        ''|'#'*) continue ;;
    esac
    patch_path="$ROOT/kernel/patches/$patch_name"
    if [ ! -f "$patch_path" ]; then
        echo "ERROR: listed patch missing: $patch_path" >&2
        exit 1
    fi
    if patch --batch --forward --dry-run -d "$SRC_DIR" -p1 < "$patch_path" >/dev/null 2>&1; then
        patch --batch --forward -d "$SRC_DIR" -p1 < "$patch_path"
        applied=$((applied + 1))
        continue
    fi
    if patch --batch --reverse --dry-run -d "$SRC_DIR" -p1 < "$patch_path" >/dev/null 2>&1; then
        echo "Already applied: $patch_name"
        continue
    fi
    case "$patch_name" in
        0001-*)
            if [ -f "$SRC_DIR/include/linux/contractbpf.h" ] &&
               grep -q 'config CONTRACTBPF' "$SRC_DIR/kernel/bpf/Kconfig"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0002-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_sched.c" ] &&
               grep -q 'contract_sched_ext_dispatch' "$SRC_DIR/kernel/sched/ext.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0004-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_mm.c" ] &&
               grep -q 'contract_mm_demote_allowed' "$SRC_DIR/mm/vmscan.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0005-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_cross.c" ] &&
               grep -q 'contract_cross_check' "$SRC_DIR/kernel/bpf/contractbpf_mm.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
    esac
    echo "ERROR: patch does not apply cleanly and is not recognized as applied: $patch_name" >&2
    exit 1
done < "$SERIES"

printf 'Applied %s ContractBPF patch(es)\n' "$applied"
