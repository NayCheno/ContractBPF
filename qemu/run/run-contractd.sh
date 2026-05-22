#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KERNEL="${CONTRACTBPF_KERNEL_IMAGE:-$ROOT/build/linux/arch/x86/boot/bzImage}"
INITRD="${CONTRACTBPF_CONTRACTD_INITRD:-$ROOT/qemu/images/contractd-initramfs.cpio.gz}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TIMEOUT="${QEMU_TIMEOUT:-60s}"
LOG_DIR="$ROOT/artifacts/logs"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/${STAMP}-qemu-contractd.log"

mkdir -p "$LOG_DIR"

if [ ! -f "$KERNEL" ]; then
    echo "ERROR: kernel image missing: $KERNEL" >&2
    exit 1
fi

if [ ! -f "$INITRD" ]; then
    "$ROOT/qemu/rootfs/build-contractd-rootfs.sh"
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

for marker in \
    CONTRACTBPF_BOOT_OK \
    CONTRACTBPF_CONTRACTD_OK
do
    if ! grep -q "$marker" "$LOG"; then
        echo "FAIL: $marker missing; log: $LOG" >&2
        tail -n 160 "$LOG" >&2
        exit 1
    fi
done

printf 'PASS: contractd started in %s\n' "$LOG"
