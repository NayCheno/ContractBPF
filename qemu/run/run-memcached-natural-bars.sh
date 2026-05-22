#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KERNEL="${CONTRACTBPF_KERNEL_IMAGE:-$ROOT/build/linux/arch/x86/boot/bzImage}"
INITRD="${CONTRACTBPF_MEMCACHED_NATURAL_INITRD:-$ROOT/qemu/images/memcached-natural-initramfs.cpio.gz}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
TIMEOUT="${QEMU_TIMEOUT:-360s}"
LOG_DIR="$ROOT/artifacts/logs"
SCRATCH_IMG="${CONTRACTBPF_MEMCACHED_NATURAL_SCRATCH_IMG:-$ROOT/artifacts/traces/memcached-natural-scratch.img}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/${STAMP}-qemu-memcached-natural.log"

mkdir -p "$LOG_DIR" "$ROOT/artifacts/traces"

if [ ! -f "$KERNEL" ]; then
    echo "ERROR: kernel image missing: $KERNEL" >&2
    exit 1
fi

if [ ! -f "$INITRD" ]; then
    "$ROOT/qemu/rootfs/build-memcached-natural-rootfs.sh"
fi

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
    echo "ERROR: qemu-system-x86_64 not found" >&2
    exit 1
fi

if ! command -v mkfs.ext4 >/dev/null 2>&1; then
    echo "ERROR: mkfs.ext4 not found" >&2
    exit 1
fi

rm -f "$SCRATCH_IMG"
truncate -s "${CONTRACTBPF_MEMCACHED_NATURAL_SCRATCH_SIZE:-256M}" "$SCRATCH_IMG"
mkfs.ext4 -q -F "$SCRATCH_IMG"

KVM_ARGS=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_ARGS=(-enable-kvm -cpu host)
else
    KVM_ARGS=(-cpu max)
fi

APPEND_ARGS=(console=ttyS0 panic=-1 nokaslr)
for env_name in \
    CONTRACTBPF_MEMCACHED_NATURAL_OPS_A \
    CONTRACTBPF_MEMCACHED_NATURAL_OPS_B \
    CONTRACTBPF_MEMCACHED_NATURAL_VALUE_A \
    CONTRACTBPF_MEMCACHED_NATURAL_VALUE_B \
    CONTRACTBPF_MEMCACHED_NATURAL_FILE_MB \
    CONTRACTBPF_MEMCACHED_NATURAL_PRESSURE_MB \
    CONTRACTBPF_MEMCACHED_NATURAL_ITERATIONS \
    CONTRACTBPF_MEMCACHED_NATURAL_MEMORY_HIGH
do
    value="${!env_name:-}"
    if [ -n "$value" ]; then
        key="$(printf '%s' "$env_name" | tr '[:upper:]' '[:lower:]' | sed 's/^contractbpf_//')"
        APPEND_ARGS+=("contractbpf.$key=$value")
    fi
done
APPEND_LINE="${APPEND_ARGS[*]}"

CMD=(timeout "$TIMEOUT" "$QEMU_BIN" "${KVM_ARGS[@]}" \
    -machine q35,hmat=on \
    -smp "${QEMU_SMP:-1}" \
    -m 1024 \
    -object memory-backend-ram,id=mem0,size=512M \
    -object memory-backend-ram,id=mem1,size=512M \
    -numa node,nodeid=0,cpus=0,memdev=mem0 \
    -numa node,nodeid=1,memdev=mem1,initiator=0 \
    -numa dist,src=0,dst=0,val=10 \
    -numa dist,src=1,dst=1,val=10 \
    -numa dist,src=0,dst=1,val=30 \
    -numa dist,src=1,dst=0,val=30 \
    -numa hmat-lb,initiator=0,target=0,hierarchy=memory,data-type=access-latency,latency=10 \
    -numa hmat-lb,initiator=0,target=1,hierarchy=memory,data-type=access-latency,latency=80 \
    -numa hmat-lb,initiator=0,target=0,hierarchy=memory,data-type=access-bandwidth,bandwidth=102400M \
    -numa hmat-lb,initiator=0,target=1,hierarchy=memory,data-type=access-bandwidth,bandwidth=1024M \
    -drive "file=$SCRATCH_IMG,if=virtio,format=raw,cache=unsafe" \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "$APPEND_LINE" \
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
    CONTRACTBPF_SCHED_EXT_OK \
    CONTRACTBPF_MM_BPF_REGISTERED \
    MEMORY_PRESSURE_OK \
    CONTRACTBPF_MEMCACHED_NATURAL_BARS_OK
do
    if ! grep -q "$marker" "$LOG"; then
        echo "FAIL: $marker missing; log: $LOG" >&2
        tail -n 220 "$LOG" >&2
        exit 1
    fi
done

if grep -q "contractctl charge" "$LOG"; then
    echo "FAIL: natural memcached log unexpectedly contains contractctl charge; log: $LOG" >&2
    exit 1
fi

printf 'PASS: ContractBPF memcached natural bars probe passed in %s\n' "$LOG"
