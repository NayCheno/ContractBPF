#!/bin/sh
set -eu

DBG=/sys/kernel/debug/contractbpf

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true

if [ ! -w "$DBG/cross_scenario" ]; then
    echo "ERROR: $DBG/cross_scenario is not available"
    /bin/poweroff-contractbpf
fi

echo 100 > "$DBG/sched_boost_budget"
echo 1 > "$DBG/sched_gate_enable"

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

/usr/local/bin/synthetic_phase_service 16 3 > /tmp/synthetic_phase_service.log 2>&1
cat /tmp/synthetic_phase_service.log

if ! grep -q SYNTHETIC_PHASE_SERVICE_OK /tmp/synthetic_phase_service.log; then
    echo "ERROR: synthetic phase service failed"
    kill "$scx_pid" 2>/dev/null || true
    /bin/poweroff-contractbpf
fi

echo unguarded > "$DBG/cross_scenario"
cat "$DBG/cross_snapshot" > /tmp/cross_unguarded
echo CONTRACTBPF_UNGUARDED_SNAPSHOT_BEGIN
cat /tmp/cross_unguarded
echo CONTRACTBPF_UNGUARDED_SNAPSHOT_END

if grep -q 'enabled=0' /tmp/cross_unguarded &&
   grep -Eq 'sched_queue_delay_us=[1-9][0-9][0-9][0-9][0-9]' /tmp/cross_unguarded &&
   grep -q 'pages_demoted=8' /tmp/cross_unguarded &&
   grep -q 'refault_events=8' /tmp/cross_unguarded &&
   grep -q 'demote_degrade_state=0' /tmp/cross_unguarded; then
    echo CONTRACTBPF_CONFLICT_REPRODUCED
else
    echo "ERROR: unguarded feedback-loop evidence missing"
    cat /tmp/cross_unguarded
    kill "$scx_pid" 2>/dev/null || true
    /bin/poweroff-contractbpf
fi

echo guarded > "$DBG/cross_scenario"
cat "$DBG/cross_snapshot" > /tmp/cross_guarded
echo CONTRACTBPF_GUARDED_SNAPSHOT_BEGIN
cat /tmp/cross_guarded
echo CONTRACTBPF_GUARDED_SNAPSHOT_END

if grep -q 'enabled=1' /tmp/cross_guarded &&
   grep -Eq 'demote_degrade_state=[2-9]' /tmp/cross_guarded &&
   grep -q 'sched_degrade_state=0' /tmp/cross_guarded &&
   grep -q 'revoke=demote_page preserve=sched_dispatch' /tmp/cross_guarded; then
    echo CONTRACTBPF_RECOVERY_OK
else
    echo "ERROR: guarded recovery evidence missing"
    cat /tmp/cross_guarded
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
    echo "ERROR: sched_ext remained enabled after conflict run"
    /bin/poweroff-contractbpf
fi

/bin/poweroff-contractbpf
