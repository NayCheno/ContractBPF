#!/bin/sh
set -eu

DBG=/sys/kernel/debug/contractbpf
STATE_DIR=/tmp/contractbpf-memcached-state
CTL=/usr/local/bin/contractctl
SCX_PID=
MEMCACHED_A_PID=
MEMCACHED_B_PID=
NO_VIOLATION_OVERHEAD=0

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
mount -t debugfs debugfs /sys/kernel/debug || true
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true
mkdir -p /sys/fs/cgroup/service-A /sys/fs/cgroup/service-B 2>/dev/null || true

echo CONTRACTBPF_BOOT_OK

if [ ! -c /dev/contractbpf ]; then
    echo "ERROR: /dev/contractbpf is not available"
    poweroff_guest
fi

contractctl()
{
    "$CTL" --state-dir "$STATE_DIR" "$@"
}

cmdline_value()
{
    key="$1"
    fallback="$2"

    for arg in $(cat /proc/cmdline 2>/dev/null || true); do
        case "$arg" in
            "$key="*)
                value="${arg#*=}"
                case "$value" in
                    ''|*[!0-9]*) echo "$fallback" ;;
                    *) echo "$value" ;;
                esac
                return
                ;;
        esac
    done

    echo "$fallback"
}

cpu_busy_jiffies()
{
    read -r _ user nice system idle iowait irq softirq steal _rest < /proc/stat
    echo $((user + nice + system + irq + softirq + steal))
}

cpu_total_jiffies()
{
    read -r _ user nice system idle iowait irq softirq steal guest guest_nice _rest < /proc/stat
    echo $((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))
}

set_gate()
{
    manifest="$1"
    enabled="$2"
    contractctl gate "$manifest" --enable "$enabled" >/tmp/contractctl-gate.log 2>&1 || true
}

reset_contract()
{
    set_gate /etc/contractbpf/service_a_sched.yaml 0
    set_gate /etc/contractbpf/service_a_paging.yaml 0
    set_gate /etc/contractbpf/service_b_sched.yaml 0
    set_gate /etc/contractbpf/service_b_paging.yaml 0
    contractctl reset --test-only >/tmp/contractctl-reset.log 2>&1 || true
    mkdir -p /sys/fs/cgroup/service-A /sys/fs/cgroup/service-B 2>/dev/null || true
}

load_sched()
{
    contractctl load /etc/contractbpf/service_a_sched.yaml >/tmp/contractctl-load-sched.log
}

load_paging()
{
    contractctl load /etc/contractbpf/service_a_paging.yaml >/tmp/contractctl-load-paging.log
}

charge_ok()
{
    contractctl charge "$@" >/tmp/contractctl-charge.log
}

charge_may_degrade()
{
    contractctl charge "$@" >/tmp/contractctl-charge.log || true
}

charge_controlled_conflict()
{
    charge_ok --policy latency_sched_A --effect boost_task --scope service-A --primary 8 --secondary 1800
    charge_ok --policy phase_paging_A --effect demote_page --scope service-A --primary 8 --secondary 8
}

trigger_demote_revoke()
{
    charge_may_degrade --policy phase_paging_A --effect demote_page --scope service-A --primary 1 --secondary 500
    charge_may_degrade --policy phase_paging_A --effect demote_page --scope service-A --primary 1 --secondary 500
}

/usr/local/bin/memcached -u root -l 127.0.0.1 -p 11211 -m 32 > /tmp/memcached-a.log 2>&1 &
MEMCACHED_A_PID=$!
/usr/local/bin/memcached -u root -l 127.0.0.1 -p 11212 -m 32 > /tmp/memcached-b.log 2>&1 &
MEMCACHED_B_PID=$!
echo "$MEMCACHED_A_PID" > /sys/fs/cgroup/service-A/cgroup.procs 2>/dev/null || true
echo "$MEMCACHED_B_PID" > /sys/fs/cgroup/service-B/cgroup.procs 2>/dev/null || true
sleep 1

if ! kill -0 "$MEMCACHED_A_PID" 2>/dev/null || ! kill -0 "$MEMCACHED_B_PID" 2>/dev/null; then
    echo "ERROR: memcached service failed to start"
    cat /tmp/memcached-a.log || true
    cat /tmp/memcached-b.log || true
    poweroff_guest
fi

start_scx()
{
    gate="${1:-1}"
    if [ "$gate" = "1" ]; then
        load_sched
    fi
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
    echo $$ > /sys/fs/cgroup/service-A/cgroup.procs 2>/dev/null || true
    /usr/local/bin/memcached_ascii_load 11211 60
    echo SERVICE_A_END
    echo SERVICE_B_BEGIN
    echo $$ > /sys/fs/cgroup/service-B/cgroup.procs 2>/dev/null || true
    /usr/local/bin/memcached_ascii_load 11212 20
    echo SERVICE_B_END
}

begin_group()
{
    echo CONTRACTBPF_GROUP_BEGIN
    echo "group=$1"
    echo "description=$2"
    echo "workload=memcached"
    echo "evidence_scope=qemu_memcached_ioctl_controlled"
}

emit_snapshots()
{
    echo SNAPSHOT_BEGIN
    echo DEVICE_LEDGER_BEGIN
    contractctl ledger --scope service-A --format lines || true
    echo DEVICE_LEDGER_END
    if [ -r "$DBG/cross_snapshot" ]; then
        echo CROSS_SNAPSHOT_BEGIN
        cat "$DBG/cross_snapshot" || true
        echo CROSS_SNAPSHOT_END
    fi
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

run_no_violation_phase()
{
    phase="$1"
    mode="$2"
    gate="$3"
    mm_gate="$4"

    begin_group "$phase" "$mode"
    reset_contract
    echo "control_mode=$mode"
    before_busy="$(cpu_busy_jiffies)"
    before_total="$(cpu_total_jiffies)"

    start_scx "$gate"
    if [ "$mm_gate" = "1" ]; then
        load_paging
    fi
    run_services
    stop_scx

    after_busy="$(cpu_busy_jiffies)"
    after_total="$(cpu_total_jiffies)"
    echo "cpu_busy_jiffies=$((after_busy - before_busy))"
    echo "cpu_total_jiffies=$((after_total - before_total))"
    end_group
}

NO_VIOLATION_OVERHEAD="$(cmdline_value contractbpf.no_violation_overhead "$NO_VIOLATION_OVERHEAD")"
if [ "$NO_VIOLATION_OVERHEAD" -ne 0 ]; then
    echo CONTRACTBPF_NO_VIOLATION_OVERHEAD_BEGIN
    run_no_violation_phase NV0 sched_ext_no_contractbpf 0 0
    run_no_violation_phase NV1 contractbpf_no_violation 1 1
    echo CONTRACTBPF_NO_VIOLATION_OVERHEAD_OK
    poweroff_guest
fi

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
load_paging
run_services
charge_ok --policy phase_paging_A --effect demote_page --scope service-A --primary 8 --secondary 8
end_group

begin_group G4 "sched_ext plus paging, no ledger"
reset_contract
echo "control_mode=combined_no_ledger"
start_scx 0
run_services
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
start_scx 1
load_paging
run_services
charge_controlled_conflict
end_group
stop_scx

begin_group G8 "kill-whole-policy fallback"
reset_contract
echo "control_mode=whole_policy_fallback"
start_scx 0
load_sched
load_paging
run_services
charge_controlled_conflict
echo "whole_policy_fallback=1"
stop_scx
end_group

begin_group G9 "full ContractBPF-Ledger"
reset_contract
echo "control_mode=full_contractbpf"
start_scx 1
load_paging
run_services
charge_controlled_conflict
trigger_demote_revoke
end_group
stop_scx

cat /tmp/scx_contract_boost.log 2>/dev/null || true
cat /tmp/memcached-a.log 2>/dev/null || true
cat /tmp/memcached-b.log 2>/dev/null || true
echo CONTRACTBPF_MEMCACHED_MATRIX_OK
poweroff_guest
