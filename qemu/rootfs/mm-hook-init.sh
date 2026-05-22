#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug

MM_SELFTEST=/sys/kernel/debug/contractbpf/mm_selftest
MM_SNAPSHOT=/sys/kernel/debug/contractbpf/mm_snapshot

if [ ! -r "$MM_SELFTEST" ]; then
    echo "ERROR: $MM_SELFTEST is not available"
    /bin/poweroff-contractbpf
fi

out="$(cat "$MM_SELFTEST")"
echo "$out"
cat "$MM_SNAPSHOT"

if echo "$out" | grep -q '^PASS'; then
    echo CONTRACTBPF_MM_HOOK_OK
    echo CONTRACTBPF_DEGRADE_OK
    /bin/poweroff-contractbpf
fi

echo "ERROR: ContractBPF MM hook selftest failed"
/bin/poweroff-contractbpf
