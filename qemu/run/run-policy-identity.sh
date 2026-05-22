#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KERNEL="${CONTRACTBPF_KERNEL_IMAGE:-$ROOT/build/linux/arch/x86/boot/bzImage}"
INITRD="${CONTRACTBPF_POLICY_IDENTITY_INITRD:-$ROOT/qemu/images/policy-identity-initramfs.cpio.gz}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TIMEOUT="${QEMU_TIMEOUT:-120s}"
LOG_DIR="$ROOT/artifacts/logs"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/${STAMP}-qemu-policy-identity.log"

mkdir -p "$LOG_DIR"

if [ ! -f "$KERNEL" ]; then
    echo "ERROR: kernel image missing: $KERNEL" >&2
    exit 1
fi

if [ ! -f "$INITRD" ]; then
    "$ROOT/qemu/rootfs/build-policy-identity-rootfs.sh"
fi

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
    echo "ERROR: qemu-system-x86_64 not found" >&2
    exit 1
fi

KVM_ARGS=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_ARGS=(-enable-kvm -cpu host)
else
    KVM_ARGS=(-cpu max)
fi

CMD=(timeout "$TIMEOUT" "$QEMU_BIN" "${KVM_ARGS[@]}" \
    -smp "${QEMU_SMP:-2}" \
    -m "${QEMU_MEM:-2048}" \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "console=ttyS0 panic=-1 nokaslr" \
    -nographic \
    -no-reboot)

{
    printf 'Command:'
    printf ' %q' "${CMD[@]}"
    printf '\n'
} > "$LOG"

set +e
"${CMD[@]}" >> "$LOG" 2>&1
status=$?
set -e

printf 'QEMU exit status: %s\n' "$status" >> "$LOG"

if find "$ROOT/build/linux/kernel/bpf" "$ROOT/build/linux/include/linux" \
    -type f \( -name '*.c' -o -name '*.h' \) ! -name '*.orig' -print0 |
    xargs -0 grep -nE 'CONTRACT_(SCHED|MM|CROSS)_PROG_ID[[:space:]]+0|contract_effect_gate[[:space:]]*\([[:space:]]*0' >> "$LOG"; then
    echo "FAIL: final kernel path still contains hard-coded policy identity; log: $LOG" >&2
    tail -n 160 "$LOG" >&2
    exit 1
fi
printf 'CONTRACTBPF_P2_SOURCE_IDENTITY_OK\n' >> "$LOG"

for marker in \
    CONTRACTBPF_BOOT_OK \
    CONTRACTBPF_POLICY_IDENTITY_SCHED_OK \
    CONTRACTBPF_POLICY_IDENTITY_LEDGER_OK \
    CONTRACTBPF_POLICY_IDENTITY_MM_OK \
    CONTRACTBPF_P2_SOURCE_IDENTITY_OK
do
    if ! grep -q "$marker" "$LOG"; then
        echo "FAIL: $marker missing; log: $LOG" >&2
        tail -n 180 "$LOG" >&2
        exit 1
    fi
done

sched_a="$(sed -n 's/^policy_identity_summary .*sched_A=\([0-9][0-9]*\).*/\1/p' "$LOG" | tail -n 1)"
sched_b="$(sed -n 's/^policy_identity_summary .*sched_B=\([0-9][0-9]*\).*/\1/p' "$LOG" | tail -n 1)"
mm_phase="$(sed -n 's/^policy_identity_summary .*mm_phase=\([0-9][0-9]*\).*/\1/p' "$LOG" | tail -n 1)"
mm_bad="$(sed -n 's/^policy_identity_summary .*mm_bad=\([0-9][0-9]*\).*/\1/p' "$LOG" | tail -n 1)"

for value in "$sched_a" "$sched_b" "$mm_phase" "$mm_bad"; do
    if [ -z "$value" ] || [ "$value" = "0" ]; then
        echo "FAIL: missing nonzero P2 policy identity in log: $LOG" >&2
        tail -n 180 "$LOG" >&2
        exit 1
    fi
done

if [ "$sched_a" = "$sched_b" ]; then
    echo "FAIL: scheduler policy IDs are not distinct: $sched_a; log: $LOG" >&2
    tail -n 180 "$LOG" >&2
    exit 1
fi

if [ "$mm_phase" = "$mm_bad" ]; then
    echo "FAIL: MM BPF policy IDs are not distinct: $mm_phase; log: $LOG" >&2
    tail -n 180 "$LOG" >&2
    exit 1
fi

for expected in \
    'policy_identity_sched label=A' \
    'policy_identity_sched label=B' \
    'policy_identity_mm label=phase' \
    'policy_identity_mm label=bad' \
    '"effect_ledgers"' \
    '"policy": "latency_sched_A"' \
    '"policy": "aggressive_sched_B"'
do
    if ! grep -q "$expected" "$LOG"; then
        echo "FAIL: expected P2 evidence missing: $expected; log: $LOG" >&2
        tail -n 180 "$LOG" >&2
        exit 1
    fi
done

printf 'PASS: ContractBPF P2 policy identity evidence passed in %s\n' "$LOG"
