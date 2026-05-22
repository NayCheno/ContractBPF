#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys

if [ ! -r /sys/kernel/sched_ext/state ]; then
    echo "ERROR: /sys/kernel/sched_ext/state missing"
    /bin/poweroff-contractbpf
fi

echo "SCHED_EXT_STATE_BEFORE=$(cat /sys/kernel/sched_ext/state)"

/usr/local/bin/scx_simple -f > /tmp/scx_simple.log 2>&1 &
scx_pid=$!

i=0
while [ "$i" -lt 10 ]; do
    state="$(cat /sys/kernel/sched_ext/state)"
    echo "SCHED_EXT_STATE_POLL=$state"
    if [ "$state" = "enabled" ]; then
        echo CONTRACTBPF_SCHED_EXT_OK
        break
    fi
    i=$((i + 1))
    sleep 1
done

if [ "$(cat /sys/kernel/sched_ext/state)" != "enabled" ]; then
    echo "ERROR: sched_ext did not become enabled"
    cat /tmp/scx_simple.log || true
    kill "$scx_pid" 2>/dev/null || true
    /bin/poweroff-contractbpf
fi

sleep 2
kill -TERM "$scx_pid" 2>/dev/null || true
wait "$scx_pid" 2>/dev/null || true

i=0
while [ "$i" -lt 10 ]; do
    state="$(cat /sys/kernel/sched_ext/state)"
    echo "SCHED_EXT_STATE_AFTER_STOP=$state"
    if [ "$state" != "enabled" ]; then
        echo CONTRACTBPF_SCHED_EXT_UNLOAD_OK
        break
    fi
    i=$((i + 1))
    sleep 1
done

cat /tmp/scx_simple.log || true

if [ "$(cat /sys/kernel/sched_ext/state)" = "enabled" ]; then
    echo "ERROR: sched_ext remained enabled after scx_simple exit"
    /bin/poweroff-contractbpf
fi

/bin/poweroff-contractbpf
