#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true

/usr/local/bin/contractd > /tmp/contractd.log 2>&1
status=$?
cat /tmp/contractd.log

if [ "$status" -eq 0 ] && grep -q CONTRACTBPF_CONTRACTD_OK /tmp/contractd.log; then
    /bin/poweroff-contractbpf
fi

echo "ERROR: contractd failed with status $status"
/bin/poweroff-contractbpf
