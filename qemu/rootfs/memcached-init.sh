#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug || true
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true

/usr/local/bin/memcached -u root -l 127.0.0.1 -p 11211 -m 32 > /tmp/memcached.log 2>&1 &
memcached_pid=$!

sleep 1

if ! kill -0 "$memcached_pid" 2>/dev/null; then
    echo "ERROR: memcached exited before load"
    cat /tmp/memcached.log || true
    /bin/poweroff-contractbpf
fi

/usr/local/bin/memcached_ascii_load 11211 120 > /tmp/memcached-load.log 2>&1 || {
    echo "ERROR: memcached load failed"
    cat /tmp/memcached.log || true
    cat /tmp/memcached-load.log || true
    kill "$memcached_pid" 2>/dev/null || true
    /bin/poweroff-contractbpf
}

cat /tmp/memcached-load.log
cat /tmp/memcached.log || true

kill "$memcached_pid" 2>/dev/null || true
wait "$memcached_pid" 2>/dev/null || true

echo CONTRACTBPF_MEMCACHED_OK
/bin/poweroff-contractbpf
