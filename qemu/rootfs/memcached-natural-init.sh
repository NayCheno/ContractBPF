#!/bin/sh
set -eu

DBG=/sys/kernel/debug/contractbpf
STATE_DIR=/tmp/contractbpf-memcached-natural-state
CTL=/usr/local/bin/contractctl
PRESSURE_FILE=/tmp/contractbpf-memcached-natural-pressure.bin
SCX_PID=
MEMCACHED_A_PID=
MEMCACHED_B_PID=
OPS_A="${CONTRACTBPF_MEMCACHED_NATURAL_OPS_A:-80}"
OPS_B="${CONTRACTBPF_MEMCACHED_NATURAL_OPS_B:-40}"
VALUE_A="${CONTRACTBPF_MEMCACHED_NATURAL_VALUE_A:-16384}"
VALUE_B="${CONTRACTBPF_MEMCACHED_NATURAL_VALUE_B:-1024}"
FILE_MB="${CONTRACTBPF_MEMCACHED_NATURAL_FILE_MB:-16}"
PRESSURE_MB="${CONTRACTBPF_MEMCACHED_NATURAL_PRESSURE_MB:-128}"
ITERATIONS="${CONTRACTBPF_MEMCACHED_NATURAL_ITERATIONS:-1}"
MEMORY_HIGH="${CONTRACTBPF_MEMCACHED_NATURAL_MEMORY_HIGH:-134217728}"

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

value_of()
{
    key="$1"
    file="$2"
    value=0

    while IFS='=' read -r name rest; do
        if [ "$name" = "$key" ]; then
            value="$rest"
        fi
    done < "$file"

    case "$value" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$value" ;;
    esac
}

run_in_cgroup_bg()
{
    service="$1"
    shift
    /bin/sh -c 'echo "$$" > "/sys/fs/cgroup/$1/cgroup.procs" 2>/dev/null || true; shift; exec "$@"' \
        "$service" "$service" "$@" &
    BG_PID=$!
}

reset_contract()
{
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR" /sys/fs/cgroup/service-A /sys/fs/cgroup/service-B
    contractctl reset --test-only >/tmp/contractctl-reset.log 2>&1 || true
}

load_contracts()
{
    paging_manifest="$1"

    reset_contract
    /usr/local/bin/contract_mm_loader /usr/local/lib/contractbpf/bad_demote.bpf.o >/tmp/mm-loader.log 2>&1
    cat /tmp/mm-loader.log
    contractctl reset --test-only >/tmp/contractctl-reset-after-loader.log 2>&1 || true
    contractctl load /etc/contractbpf/service_a_sched_natural.yaml >/tmp/contractctl-load-sched.log
    contractctl load "$paging_manifest" >/tmp/contractctl-load-paging.log
    contractctl gate /etc/contractbpf/service_a_sched_natural.yaml --enable 1 >/tmp/contractctl-gate-sched.log
    contractctl gate "$paging_manifest" --enable 1 >/tmp/contractctl-gate-mm.log
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

start_memcached()
{
    /usr/local/bin/memcached -u root -l 127.0.0.1 -p 11211 -m 128 > /tmp/memcached-a.log 2>&1 &
    MEMCACHED_A_PID=$!
    /usr/local/bin/memcached -u root -l 127.0.0.1 -p 11212 -m 64 > /tmp/memcached-b.log 2>&1 &
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
}

run_load_pair()
{
    label="$1"

    run_in_cgroup_bg service-A /usr/local/bin/memcached_ascii_load 11211 "$OPS_A" "$VALUE_A" > "/tmp/load-a.$label.log" 2>&1
    load_a_pid="$BG_PID"
    run_in_cgroup_bg service-B /usr/local/bin/memcached_ascii_load 11212 "$OPS_B" "$VALUE_B" > "/tmp/load-b.$label.log" 2>&1
    load_b_pid="$BG_PID"
    wait "$load_a_pid" 2>/dev/null || true
    wait "$load_b_pid" 2>/dev/null || true

    echo SERVICE_A_BEGIN
    cat "/tmp/load-a.$label.log"
    echo SERVICE_A_END
    echo SERVICE_B_BEGIN
    cat "/tmp/load-b.$label.log"
    echo SERVICE_B_END
}

run_pressure_bg()
{
    label="$1"
    run_in_cgroup_bg service-A /usr/local/bin/memory_pressure "$PRESSURE_FILE.$label" \
        "$FILE_MB" "$PRESSURE_MB" "$ITERATIONS" > "/tmp/memory-pressure.$label.log" 2>&1
    PRESSURE_PID="$BG_PID"
}

begin_group()
{
    echo CONTRACTBPF_GROUP_BEGIN
    echo "group=$1"
    echo "description=$2"
    echo "workload=memcached"
    echo "evidence_scope=qemu_memcached_natural"
}

emit_metrics()
{
    label="$1"
    ledger_file="/tmp/ledger.$label"
    mm_file="/tmp/mm.$label"
    sched_file="/tmp/sched.$label"

    echo SNAPSHOT_BEGIN
    echo DEVICE_LEDGER_BEGIN
    contractctl ledger --scope service-A --format lines > "$ledger_file" 2>/dev/null || true
    cat "$ledger_file"
    echo DEVICE_LEDGER_END
    if [ -r "$DBG/sched_snapshot" ]; then
        echo SCHED_SNAPSHOT_BEGIN
        cat "$DBG/sched_snapshot" > "$sched_file" 2>/dev/null || true
        cat "$sched_file" || true
        echo SCHED_SNAPSHOT_END
    fi
    if [ -r "$DBG/mm_snapshot" ]; then
        echo MM_SNAPSHOT_BEGIN
        cat "$DBG/mm_snapshot" > "$mm_file" 2>/dev/null || true
        cat "$mm_file" || true
        echo MM_SNAPSHOT_END
    fi
    echo SNAPSHOT_END
}

end_group()
{
    emit_metrics "$1"
    echo CONTRACTBPF_GROUP_END
}

run_baseline_group()
{
    group="$1"
    description="$2"
    mode="$3"

    begin_group "$group" "$description"
    reset_contract
    echo "control_mode=$mode"
    if [ "$mode" = "sched_only" ]; then
        start_scx
    fi
    run_load_pair "$group"
    if [ "$mode" = "sched_only" ]; then
        stop_scx
    fi
    end_group "$group"
}

run_conflict_group()
{
    group="$1"
    description="$2"
    paging_manifest="$3"

    begin_group "$group" "$description"
    load_contracts "$paging_manifest"
    echo "control_mode=$group"
    start_scx
    if [ "$group" = "G9" ]; then
        run_pressure_bg "$group-prerecovery"
        wait "$PRESSURE_PID" 2>/dev/null || true
        cat "/tmp/memory-pressure.$group-prerecovery.log" || true
    else
        run_pressure_bg "$group"
    fi
    run_load_pair "$group"
    if [ "$group" != "G9" ]; then
        wait "$PRESSURE_PID" 2>/dev/null || true
        cat "/tmp/memory-pressure.$group.log" || true
    fi
    end_group "$group"
    stop_scx
}

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug || true
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true
mkdir -p /sys/fs/cgroup/service-A /sys/fs/cgroup/service-B /mnt/scratch /tmp

OPS_A="$(cmdline_value contractbpf.memcached_natural_ops_a "$OPS_A")"
OPS_B="$(cmdline_value contractbpf.memcached_natural_ops_b "$OPS_B")"
VALUE_A="$(cmdline_value contractbpf.memcached_natural_value_a "$VALUE_A")"
VALUE_B="$(cmdline_value contractbpf.memcached_natural_value_b "$VALUE_B")"
FILE_MB="$(cmdline_value contractbpf.memcached_natural_file_mb "$FILE_MB")"
PRESSURE_MB="$(cmdline_value contractbpf.memcached_natural_pressure_mb "$PRESSURE_MB")"
ITERATIONS="$(cmdline_value contractbpf.memcached_natural_iterations "$ITERATIONS")"
MEMORY_HIGH="$(cmdline_value contractbpf.memcached_natural_memory_high "$MEMORY_HIGH")"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    echo "+memory" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi
if [ -w /sys/fs/cgroup/service-A/memory.high ]; then
    echo "$MEMORY_HIGH" > /sys/fs/cgroup/service-A/memory.high 2>/dev/null || true
    echo "service_a_memory_high=$(cat /sys/fs/cgroup/service-A/memory.high)"
fi
if [ -b /dev/vda ] && mount -t ext4 -o noatime /dev/vda /mnt/scratch 2>/tmp/scratch-mount.log; then
    PRESSURE_FILE=/mnt/scratch/contractbpf-memcached-natural-pressure.bin
    echo "scratch_ext4_mount=1"
else
    echo "scratch_ext4_mount=0"
    cat /tmp/scratch-mount.log 2>/dev/null || true
fi

if [ -w /sys/kernel/mm/numa/demotion_enabled ]; then
    echo true > /sys/kernel/mm/numa/demotion_enabled
fi

echo "memcached_natural_config ops_a=$OPS_A ops_b=$OPS_B value_a=$VALUE_A value_b=$VALUE_B file_mb=$FILE_MB pressure_mb=$PRESSURE_MB iterations=$ITERATIONS memory_high=$MEMORY_HIGH pressure_file=$PRESSURE_FILE"

if [ ! -c /dev/contractbpf ]; then
    echo "ERROR: /dev/contractbpf is not available"
    poweroff_guest
fi

start_memcached

run_baseline_group G1 "Linux default scheduler plus default paging" default
run_baseline_group G2 "sched_ext policy only" sched_only
run_conflict_group G4 "sched_ext plus bad paging natural conflict window" /etc/contractbpf/service_a_paging_norevoke.yaml
run_conflict_group G9 "full ContractBPF-Ledger bounded degradation" /etc/contractbpf/service_a_paging.yaml

cat /tmp/scx_contract_boost.log 2>/dev/null || true
cat /tmp/memcached-a.log 2>/dev/null || true
cat /tmp/memcached-b.log 2>/dev/null || true
echo CONTRACTBPF_MEMCACHED_NATURAL_BARS_OK
poweroff_guest
