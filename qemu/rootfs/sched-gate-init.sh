#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug

echo 2 > /sys/kernel/debug/contractbpf/sched_boost_budget
echo 1 > /sys/kernel/debug/contractbpf/sched_gate_enable
cat /sys/kernel/debug/contractbpf/sched_snapshot

/usr/local/bin/scx_contract_boost > /tmp/scx_contract_boost.log 2>&1 &
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
    cat /tmp/scx_contract_boost.log || true
    kill "$scx_pid" 2>/dev/null || true
    /bin/poweroff-contractbpf
fi

sleep 3
cat /sys/kernel/debug/contractbpf/sched_snapshot > /tmp/sched_snapshot
cat /tmp/sched_snapshot

if grep -Eq 'violations=[1-9][0-9]*' /tmp/sched_snapshot &&
   grep -Eq 'throttled_boosts=[1-9][0-9]*' /tmp/sched_snapshot &&
   grep -Eq 'boost_degrade_state=[1-9][0-9]*' /tmp/sched_snapshot; then
    echo CONTRACTBPF_SCHED_GATE_OK
    echo CONTRACTBPF_DEGRADE_OK
else
    echo "ERROR: ContractBPF sched gate did not throttle boost"
    cat /tmp/scx_contract_boost.log || true
    kill "$scx_pid" 2>/dev/null || true
    /bin/poweroff-contractbpf
fi

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

cat /tmp/scx_contract_boost.log || true

if [ "$(cat /sys/kernel/sched_ext/state)" = "enabled" ]; then
    echo "ERROR: sched_ext remained enabled after scx_contract_boost exit"
    /bin/poweroff-contractbpf
fi

/bin/poweroff-contractbpf

