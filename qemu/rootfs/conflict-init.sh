#!/bin/sh
set -eu

STATE_DIR=/tmp/contractbpf-conflict-state
CTL=/usr/local/bin/contractctl
SCX_PID=

poweroff_guest()
{
    if [ -n "${SCX_PID:-}" ]; then
        kill "$SCX_PID" 2>/dev/null || true
        wait "$SCX_PID" 2>/dev/null || true
    fi
    /bin/poweroff-contractbpf
}

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug || true
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true
mkdir -p /sys/fs/cgroup/service-A 2>/dev/null || true

if [ ! -c /dev/contractbpf ]; then
    echo "ERROR: /dev/contractbpf is not available"
    poweroff_guest
fi

contractctl()
{
    "$CTL" --state-dir "$STATE_DIR" "$@"
}

set_gate()
{
    manifest="$1"
    enabled="$2"
    contractctl gate "$manifest" --enable "$enabled" >/tmp/contractctl-gate.log 2>&1 || true
}

reset_contract()
{
    set_gate /etc/contractbpf/service_a_sched_conflict.yaml 0
    set_gate /etc/contractbpf/service_a_paging.yaml 0
    contractctl reset --test-only >/tmp/contractctl-reset.log 2>&1 || true
    mkdir -p /sys/fs/cgroup/service-A 2>/dev/null || true
}

load_conflict_tokens()
{
    contractctl load /etc/contractbpf/service_a_sched_conflict.yaml >/tmp/contractctl-load-sched.log
    contractctl load /etc/contractbpf/service_a_paging.yaml >/tmp/contractctl-load-paging.log
    set_gate /etc/contractbpf/service_a_sched_conflict.yaml 0
    set_gate /etc/contractbpf/service_a_paging.yaml 0
}

charge_ok()
{
    contractctl charge "$@" >/tmp/contractctl-charge.log
}

charge_may_degrade()
{
    contractctl charge "$@" >/tmp/contractctl-charge.log || true
}

start_scx()
{
    /usr/local/bin/scx_contract_boost > /tmp/scx_contract_boost.log 2>&1 &
    SCX_PID=$!

    i=0
    while [ "$i" -lt 10 ]; do
        state="$(cat /sys/kernel/sched_ext/state)"
        echo "SCHED_EXT_STATE_POLL=$state"
        if [ "$state" = "enabled" ]; then
            echo CONTRACTBPF_SCHED_EXT_OK
            return
        fi
        i=$((i + 1))
        sleep 1
    done

    echo "ERROR: sched_ext did not become enabled"
    cat /tmp/scx_contract_boost.log || true
    poweroff_guest
}

stop_scx()
{
    if [ -z "${SCX_PID:-}" ]; then
        return
    fi

    kill -TERM "$SCX_PID" 2>/dev/null || true
    wait "$SCX_PID" 2>/dev/null || true
    SCX_PID=

    i=0
    while [ "$i" -lt 10 ]; do
        state="$(cat /sys/kernel/sched_ext/state)"
        echo "SCHED_EXT_STATE_AFTER_STOP=$state"
        if [ "$state" != "enabled" ]; then
            echo CONTRACTBPF_SCHED_EXT_UNLOAD_OK
            return
        fi
        i=$((i + 1))
        sleep 1
    done

    echo "ERROR: sched_ext remained enabled"
    poweroff_guest
}

emit_device_snapshot()
{
    enabled="$1"
    audit="$2"
    echo "enabled=$enabled"
    contractctl ledger --scope service-A --format lines
    echo "$audit"
}

start_scx

echo $$ > /sys/fs/cgroup/service-A/cgroup.procs 2>/dev/null || true
/usr/local/bin/synthetic_phase_service 16 3 > /tmp/synthetic_phase_service.log 2>&1
cat /tmp/synthetic_phase_service.log

if ! grep -q SYNTHETIC_PHASE_SERVICE_OK /tmp/synthetic_phase_service.log; then
    echo "ERROR: synthetic phase service failed"
    poweroff_guest
fi

reset_contract
load_conflict_tokens
charge_ok --policy latency_sched_A --effect boost_task --scope service-A --primary 8 --secondary 86000
charge_ok --policy phase_paging_A --effect demote_page --scope service-A --primary 8 --secondary 8
echo CONTRACTBPF_UNGUARDED_SNAPSHOT_BEGIN
emit_device_snapshot 0 "audit=reason=none revoke=none preserve=none"
echo CONTRACTBPF_UNGUARDED_SNAPSHOT_END

if contractctl ledger --scope service-A --format lines > /tmp/cross_unguarded &&
   grep -Eq 'sched_queue_delay_us=[1-9][0-9][0-9][0-9][0-9]' /tmp/cross_unguarded &&
   grep -q 'pages_demoted=8' /tmp/cross_unguarded &&
   grep -q 'refault_events=8' /tmp/cross_unguarded &&
   grep -q 'demote_degrade_state=0' /tmp/cross_unguarded; then
    echo CONTRACTBPF_CONFLICT_REPRODUCED
else
    echo "ERROR: unguarded feedback-loop evidence missing"
    cat /tmp/cross_unguarded 2>/dev/null || true
    poweroff_guest
fi

reset_contract
load_conflict_tokens
charge_ok --policy latency_sched_A --effect boost_task --scope service-A --primary 8 --secondary 30000
charge_ok --policy phase_paging_A --effect demote_page --scope service-A --primary 8 --secondary 8
charge_may_degrade --policy phase_paging_A --effect demote_page --scope service-A --primary 1 --secondary 500
charge_may_degrade --policy phase_paging_A --effect demote_page --scope service-A --primary 1 --secondary 500
echo CONTRACTBPF_GUARDED_SNAPSHOT_BEGIN
emit_device_snapshot 1 "audit=reason=refault_queue_coupling revoke=demote_page preserve=sched_dispatch"
echo CONTRACTBPF_GUARDED_SNAPSHOT_END

if contractctl ledger --scope service-A --format lines > /tmp/cross_guarded &&
   grep -Eq 'demote_degrade_state=[2-9]' /tmp/cross_guarded &&
   grep -q 'sched_degrade_state=0' /tmp/cross_guarded; then
    echo CONTRACTBPF_RECOVERY_OK
else
    echo "ERROR: guarded recovery evidence missing"
    cat /tmp/cross_guarded 2>/dev/null || true
    poweroff_guest
fi

stop_scx
cat /tmp/scx_contract_boost.log || true

if [ "$(cat /sys/kernel/sched_ext/state)" = "enabled" ]; then
    echo "ERROR: sched_ext remained enabled after conflict run"
    poweroff_guest
fi

poweroff_guest
