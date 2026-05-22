#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug

/usr/local/bin/contractbpf_selftest.sh > /tmp/contractbpf-selftest.log 2>&1
status=$?
cat /tmp/contractbpf-selftest.log

if [ "$status" -eq 0 ]; then
    echo CONTRACTBPF_LEDGER_OK
    echo CONTRACTBPF_DEGRADE_OK
    /bin/poweroff-contractbpf
fi

echo "ERROR: contractbpf selftest failed with status $status"
/bin/poweroff-contractbpf

