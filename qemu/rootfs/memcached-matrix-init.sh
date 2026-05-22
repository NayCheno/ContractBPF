#!/bin/sh
set -eu

DBG=/sys/kernel/debug/contractbpf
SCX_PID=
MEMCACHED_A_PID=
MEMCACHED_B_PID=

poweroff_guest()
{
    if [ -n "${SCX_PID:-}" ]; then
        kill "$SCX_PID" 2>/dev/null || true
        wait "$SCX_PID" 2>/dev/null || true
    fi
    if [ -n "${MEMCACHED_A_PID:-}" ]; then
        kill "$MEMCACHED_A_PID" 2>/dev/null || true
        wait "$MEMCACHED_A_PID" 2>/dev/null || true
    fi
    if [ -n "${MEMCACHED_B_PID:-}" ]; then
        kill "$MEMCACHED_B_PID" 2>/dev/null || true
        wait "$MEMCACHED_B_PID" 2>/dev/null || true
    fi
    /bin/poweroff-contractbpf
}

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true

echo CONTRACTBPF_BOOT_OK

if [ ! -w "$DBG/cross_scenario" ]; then
    echo "ERROR: $DBG/cross_scenario is not available"
    poweroff_guest
fi

/usr/local/bin/memcached -u root -l 127.0.0.1 -p 11211 -m 32 > /tmp/memcached-a.log 2>&1 &
MEMCACHED_A_PID=$!
/usr/local/bin/memcached -u root -l 127.0.0.1 -p 11212 -m 32 > /tmp/memcached-b.log 2>&1 &
MEMCACHED_B_PID=$!
sleep 1

if ! kill -0 "$MEMCACHED_A_PID" 2>/dev/null || ! kill -0 "$MEMCACHED_B_PID" 2>/dev/null; then
    echo "ERROR: memcached service failed to start"
    cat /tmp/memcached-a.log || true
    cat /tmp/memcached-b.log || true
    poweroff_guest
fi

reset_contract()
{
    echo reset > "$DBG/cross_scenario" || true
    echo 0 > "$DBG/sched_gate_enable" || true
    echo 0 > "$DBG/mm_gate_enable" || true
}

start_scx()
{
    gate="${1:-1}"
    echo 100 > "$DBG/sched_boost_budget"
    echo "$gate" > "$DBG/sched_gate_enable"
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

run_services()
{
    echo SERVICE_A_BEGIN
    /usr/local/bin/memcached_ascii_load 11211 60
    echo SERVICE_A_END
    echo SERVICE_B_BEGIN
    /usr/local/bin/memcached_ascii_load 11212 20
    echo SERVICE_B_END
}

begin_group()
{
    echo CONTRACTBPF_GROUP_BEGIN
    echo "group=$1"
    echo "description=$2"
    echo "workload=memcached"
    echo "evidence_scope=qemu_memcached_controlled_effects"
}

emit_snapshots()
{
    echo SNAPSHOT_BEGIN
    echo CROSS_SNAPSHOT_BEGIN
    cat "$DBG/cross_snapshot" || true
    echo CROSS_SNAPSHOT_END
    if [ -r "$DBG/sched_snapshot" ]; then
        echo SCHED_SNAPSHOT_BEGIN
        cat "$DBG/sched_snapshot" || true
        echo SCHED_SNAPSHOT_END
    fi
    if [ -r "$DBG/mm_snapshot" ]; then
        echo MM_SNAPSHOT_BEGIN
        cat "$DBG/mm_snapshot" || true
        echo MM_SNAPSHOT_END
    fi
    echo SNAPSHOT_END
}

end_group()
{
    emit_snapshots
    echo CONTRACTBPF_GROUP_END
}

begin_group G1 "Linux default scheduler plus default paging"
reset_contract
echo "control_mode=default"
run_services
end_group

begin_group G2 "sched_ext policy only"
reset_contract
echo "control_mode=sched_only"
start_scx 0
run_services
end_group
stop_scx

begin_group G3 "BPF/PageFlex-style paging policy only"
reset_contract
echo "control_mode=paging_only"
echo 1 > "$DBG/mm_gate_enable"
echo 3 > "$DBG/mm_demote_budget"
echo 8 > "$DBG/mm_simulate_bad_demote"
run_services
end_group

begin_group G4 "sched_ext plus paging, no ledger"
reset_contract
echo "control_mode=combined_no_ledger"
start_scx 0
run_services
echo unguarded > "$DBG/cross_scenario"
end_group
stop_scx

begin_group G5 "cgroup/memcg quota-style controls"
reset_contract
echo "control_mode=cgroup_memcg"
if [ -r /sys/fs/cgroup/cgroup.controllers ]; then
    echo "cgroup_controllers=$(cat /sys/fs/cgroup/cgroup.controllers)"
fi
mkdir -p /sys/fs/cgroup/contractbpf-memcached-a 2>/dev/null || true
if [ -w /sys/fs/cgroup/contractbpf-memcached-a/memory.max ]; then
    echo 67108864 > /sys/fs/cgroup/contractbpf-memcached-a/memory.max || true
    echo "memory_max=67108864"
fi
run_services
end_group

begin_group G6 "static checker only"
reset_contract
echo "control_mode=static_checker_only"
echo "static_checker_runtime_enforcement=0"
run_services
end_group

begin_group G7 "per-subsystem ledger only"
reset_contract
echo "control_mode=per_subsystem_ledger"
echo 0 > "$DBG/cross_rule_enable"
start_scx 1
echo 1 > "$DBG/mm_gate_enable"
echo 3 > "$DBG/mm_demote_budget"
echo 8 > "$DBG/mm_simulate_bad_demote"
run_services
end_group
stop_scx

begin_group G8 "kill-whole-policy fallback"
reset_contract
echo "control_mode=whole_policy_fallback"
start_scx 0
run_services
echo unguarded > "$DBG/cross_scenario"
echo "whole_policy_fallback=1"
stop_scx
end_group

begin_group G9 "full ContractBPF-Ledger"
reset_contract
echo "control_mode=full_contractbpf"
start_scx 1
run_services
echo guarded > "$DBG/cross_scenario"
end_group
stop_scx

cat /tmp/scx_contract_boost.log 2>/dev/null || true
cat /tmp/memcached-a.log 2>/dev/null || true
cat /tmp/memcached-b.log 2>/dev/null || true
echo CONTRACTBPF_MEMCACHED_MATRIX_OK
poweroff_guest
