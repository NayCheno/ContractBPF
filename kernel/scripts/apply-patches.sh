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
    case "$patch_name" in
        0011-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_control.c" ] &&
               grep -q 'struct contract_ioctl_charge' "$SRC_DIR/include/linux/contractbpf.h" &&
               grep -q 'contract_ioctl_charge_effect' "$SRC_DIR/kernel/bpf/contractbpf_control.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0012-*)
            if [ -f "$SRC_DIR/include/linux/contractbpf.h" ] &&
               grep -q 'CONTRACTBPF_IOC_CHARGE_EFFECT' "$SRC_DIR/include/linux/contractbpf.h"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0024-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q '#define CONTRACT_MAX_LEDGERS 1024' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'contract_find_ledger' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'ledger = contract_lookup_ledger(scope);' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0025-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q 'CONTRACT_LEDGER_STRESS_EVENTS' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'contract_ledger_debugfs_init' "$SRC_DIR/include/linux/contractbpf.h" &&
               grep -q 'contract_ledger_debugfs_init(contract_debugfs_dir)' "$SRC_DIR/kernel/bpf/contractbpf_core.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0026-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q 'CONTRACTBPF_LEDGER_STRESS_OK' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'debugfs_create_file("ledger_stress"' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'DEFINE_SHOW_ATTRIBUTE(contract_ledger_stress)' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0027-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q 'debugfs_create_file("ledger_stress"' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               tail -n 5 "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" | grep -q '^}$'; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0028-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_core.c" ] &&
               grep -q 'contract_find_token' "$SRC_DIR/kernel/bpf/contractbpf_core.c" &&
               grep -q 'CONTRACTBPF_HOTPATH_TIMING_OK' "$SRC_DIR/kernel/bpf/contractbpf_core.c" &&
               grep -q 'debugfs_create_file("hotpath_timing"' "$SRC_DIR/kernel/bpf/contractbpf_core.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
    esac
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
        0007-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_control.c" ] &&
               grep -q 'CONTRACTBPF_IOC_INSTALL_TOKEN' "$SRC_DIR/include/linux/contractbpf.h"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0008-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_identity.c" ] &&
               grep -q 'contract_effect_policy_id' "$SRC_DIR/kernel/bpf/contractbpf_sched.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0009-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_identity.c" ] &&
               grep -q 'return scope;' "$SRC_DIR/kernel/bpf/contractbpf_identity.c" &&
               ! grep -q 'CONTRACT_MM_PROG_ID' "$SRC_DIR/kernel/bpf/contractbpf_mm.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0010-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_mm.c" ] &&
               grep -q 'contract_effect_policy_id(CONTRACT_EFFECT_MM_DEMOTE_PAGE)' "$SRC_DIR/kernel/bpf/contractbpf_mm.c" &&
               grep -q 'scope=%u:%llu:%llu' "$SRC_DIR/kernel/bpf/contractbpf_mm.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0011-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_control.c" ] &&
               grep -q 'struct contract_ioctl_charge' "$SRC_DIR/include/linux/contractbpf.h" &&
               grep -q 'contract_ioctl_charge_effect' "$SRC_DIR/kernel/bpf/contractbpf_control.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0012-*)
            if [ -f "$SRC_DIR/include/linux/contractbpf.h" ] &&
               grep -q 'CONTRACTBPF_IOC_CHARGE_EFFECT' "$SRC_DIR/include/linux/contractbpf.h"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0013-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_sched.c" ] &&
               grep -q 'contract_task_scope(p)' "$SRC_DIR/kernel/bpf/contractbpf_sched.c" &&
               grep -q 'contract_folio_scope(folio)' "$SRC_DIR/kernel/bpf/contractbpf_mm.c" &&
               grep -q 'contract_effect_policy_id_for_scope' "$SRC_DIR/kernel/bpf/contractbpf_core.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0014-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_mm.c" ] &&
               grep -q 'contract_mm_validate_decision(scope, CONTRACT_MM_RECLAIM_HINT, 1)' "$SRC_DIR/kernel/bpf/contractbpf_mm.c" &&
               grep -q 'contract_mm_install_tokens(contract_mm_scope())' "$SRC_DIR/kernel/bpf/contractbpf_mm.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0015-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_core.c" ] &&
               grep -q 'saw_effect_token' "$SRC_DIR/kernel/bpf/contractbpf_core.c" &&
               grep -q '!contract_effect_policy_id_for_scope(CONTRACT_EFFECT_SCHED_DISPATCH, scope)' "$SRC_DIR/kernel/bpf/contractbpf_sched.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0016-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_control.c" ] &&
               grep -q 'CONTRACTBPF_IOC_SET_GATE' "$SRC_DIR/include/linux/contractbpf.h" &&
               grep -q 'contract_ioctl_set_gate' "$SRC_DIR/kernel/bpf/contractbpf_control.c" &&
               grep -q 'contract_sched_set_enabled' "$SRC_DIR/kernel/bpf/contractbpf_sched.c" &&
               grep -q 'contract_mm_set_enabled' "$SRC_DIR/kernel/bpf/contractbpf_mm.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0017-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_sched.c" ] &&
               grep -A4 'void contract_sched_set_enabled' "$SRC_DIR/kernel/bpf/contractbpf_sched.c" | grep -q 'contract_sched_gate_enabled = enabled;' &&
               ! grep -A4 'void contract_sched_set_enabled' "$SRC_DIR/kernel/bpf/contractbpf_sched.c" | grep -q 'contract_sched_install_tokens' &&
               grep -A4 'void contract_mm_set_enabled' "$SRC_DIR/kernel/bpf/contractbpf_mm.c" | grep -q 'contract_mm_gate_enabled = enabled;' &&
               ! grep -A4 'void contract_mm_set_enabled' "$SRC_DIR/kernel/bpf/contractbpf_mm.c" | grep -q 'contract_mm_install_tokens'; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0018-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_mm.c" ] &&
               grep -q 'CONTRACTBPF_IOC_SET_MM_BPF_POLICY' "$SRC_DIR/include/linux/contractbpf.h" &&
               grep -q 'contract_mm_register_bpf_policy' "$SRC_DIR/kernel/bpf/contractbpf_mm.c" &&
               grep -q 'contract_ioctl_mm_test_hook' "$SRC_DIR/kernel/bpf/contractbpf_control.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0019-*)
            if [ -f "$SRC_DIR/include/linux/contractbpf.h" ] &&
               grep -A14 'struct contract_mm_region_state' "$SRC_DIR/include/linux/contractbpf.h" | grep -q 'u32 flags;' &&
               grep -A15 'struct contract_mm_region_state' "$SRC_DIR/include/linux/contractbpf.h" | grep -q 'u32 reserved;'; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0024-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q '#define CONTRACT_MAX_LEDGERS 1024' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'contract_find_ledger' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'ledger = contract_lookup_ledger(scope);' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0025-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q 'CONTRACT_LEDGER_STRESS_EVENTS' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'contract_ledger_debugfs_init' "$SRC_DIR/include/linux/contractbpf.h" &&
               grep -q 'contract_ledger_debugfs_init(contract_debugfs_dir)' "$SRC_DIR/kernel/bpf/contractbpf_core.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0026-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q 'CONTRACTBPF_LEDGER_STRESS_OK' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               grep -q 'debugfs_create_file("ledger_stress"' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0027-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" ] &&
               grep -q 'debugfs_create_file("ledger_stress"' "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" &&
               tail -n 5 "$SRC_DIR/kernel/bpf/contractbpf_ledger.c" | grep -q '^}$'; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
        0028-*)
            if [ -f "$SRC_DIR/kernel/bpf/contractbpf_core.c" ] &&
               grep -q 'contract_find_token' "$SRC_DIR/kernel/bpf/contractbpf_core.c" &&
               grep -q 'CONTRACTBPF_HOTPATH_TIMING_OK' "$SRC_DIR/kernel/bpf/contractbpf_core.c" &&
               grep -q 'debugfs_create_file("hotpath_timing"' "$SRC_DIR/kernel/bpf/contractbpf_core.c"; then
                echo "Already applied or superseded: $patch_name"
                continue
            fi
            ;;
    esac
    echo "ERROR: patch does not apply cleanly and is not recognized as applied: $patch_name" >&2
    exit 1
done < "$SERIES"

printf 'Applied %s ContractBPF patch(es)\n' "$applied"
