#!/bin/sh
set -eu

STATE_DIR=/tmp/contractbpf-natural-state
CTL=/usr/local/bin/contractctl
HOST_MOUNT=/mnt/host
PRESSURE_FILE=/tmp/contractbpf-natural-pressure.bin
SCX_PID=
SERVICE_BG_PID=
OK_RUNS=0
RUNS="${CONTRACTBPF_NATURAL_RUNS:-5}"
FILE_MB="${CONTRACTBPF_NATURAL_FILE_MB:-4}"
PRESSURE_MB="${CONTRACTBPF_NATURAL_PRESSURE_MB:-128}"
ITERATIONS="${CONTRACTBPF_NATURAL_ITERATIONS:-1}"
MEMORY_HIGH="${CONTRACTBPF_NATURAL_MEMORY_HIGH:-134217728}"
RECOVERY_MODE="${CONTRACTBPF_NATURAL_RECOVERY:-0}"
LEDGER_STRESS_MODE="${CONTRACTBPF_LEDGER_STRESS:-0}"
HOTPATH_TIMING_MODE="${CONTRACTBPF_HOTPATH_TIMING:-0}"
SCOPE_RUNTIME_MODE="${CONTRACTBPF_SCOPE_RUNTIME:-0}"

poweroff_guest()
{
    if [ -n "${SCX_PID:-}" ]; then
        kill "$SCX_PID" 2>/dev/null || true
        wait "$SCX_PID" 2>/dev/null || true
    fi
    /bin/poweroff-contractbpf
}

collect_metrics()
{
    label="$1"
    ledger_file="/tmp/natural-ledger.$label"
    mm_file="/tmp/natural-mm.$label"

    echo "DEVICE_LEDGER_BEGIN label=$label"
    contractctl ledger --scope service-A --format lines > "$ledger_file"
    cat "$ledger_file"
    echo "DEVICE_LEDGER_END label=$label"

    echo "MM_SNAPSHOT_BEGIN label=$label"
    cat /sys/kernel/debug/contractbpf/mm_snapshot > "$mm_file" 2>/dev/null || true
    cat "$mm_file" || true
    echo "MM_SNAPSHOT_END label=$label"
}

run_pressure_window()
{
    label="$1"
    pressure_mb="$2"
    log_file="/tmp/memory-pressure.$label.log"

    run_service_a_bg /usr/local/bin/synthetic_phase_service 8 12
    bg1="$SERVICE_BG_PID"
    run_service_a_bg /usr/local/bin/synthetic_phase_service 8 12
    bg2="$SERVICE_BG_PID"
    if run_in_service_a /usr/local/bin/memory_pressure "$PRESSURE_FILE.$label" \
       "$FILE_MB" "$pressure_mb" "$ITERATIONS" > "$log_file" 2>&1; then
        status=0
    else
        status=$?
    fi
    cat "$log_file"
    echo "memory_pressure_status=$status label=$label"
    wait "$bg1" 2>/dev/null || true
    wait "$bg2" 2>/dev/null || true

    return "$status"
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

run_in_service_a()
{
    /bin/sh -c 'echo "$$" > /sys/fs/cgroup/service-A/cgroup.procs 2>/dev/null || true; exec "$@"' service-a "$@"
}

run_service_a_bg()
{
    /bin/sh -c 'echo "$$" > /sys/fs/cgroup/service-A/cgroup.procs 2>/dev/null || true; exec "$@"' service-a "$@" &
    SERVICE_BG_PID=$!
}

run_in_service_b()
{
    /bin/sh -c 'echo "$$" > /sys/fs/cgroup/service-B/cgroup.procs 2>/dev/null || true; exec "$@"' service-b "$@"
}

run_service_b_bg()
{
    /bin/sh -c 'echo "$$" > /sys/fs/cgroup/service-B/cgroup.procs 2>/dev/null || true; exec "$@"' service-b "$@" &
    SERVICE_BG_PID=$!
}

reset_and_load()
{
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR" /sys/fs/cgroup/service-A /sys/fs/cgroup/service-B
    contractctl reset --test-only >/tmp/contractctl-reset.log 2>&1 || true
    /usr/local/bin/contract_mm_loader /usr/local/lib/contractbpf/bad_demote.bpf.o
    contractctl reset --test-only >/tmp/contractctl-reset-after-loader.log 2>&1 || true
    contractctl load /etc/contractbpf/service_a_sched_natural.yaml >/tmp/contractctl-load-sched.log
    contractctl load /etc/contractbpf/service_a_paging.yaml >/tmp/contractctl-load-paging.log
    contractctl gate /etc/contractbpf/service_a_sched_natural.yaml --enable 1 >/tmp/contractctl-gate-sched.log
    contractctl gate /etc/contractbpf/service_a_paging.yaml --enable 1 >/tmp/contractctl-gate-mm.log
}

reset_and_load_two_tenant()
{
    reset_and_load
    contractctl load /etc/contractbpf/service_b_sched.yaml >/tmp/contractctl-load-sched-b.log
    contractctl load /etc/contractbpf/service_b_paging.yaml >/tmp/contractctl-load-paging-b.log
    contractctl gate /etc/contractbpf/service_b_sched.yaml --enable 1 >/tmp/contractctl-gate-sched-b.log
    contractctl gate /etc/contractbpf/service_b_paging.yaml --enable 1 >/tmp/contractctl-gate-mm-b.log
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

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug || true
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true

RUNS="$(cmdline_value contractbpf.natural_runs "$RUNS")"
FILE_MB="$(cmdline_value contractbpf.natural_file_mb "$FILE_MB")"
PRESSURE_MB="$(cmdline_value contractbpf.natural_pressure_mb "$PRESSURE_MB")"
ITERATIONS="$(cmdline_value contractbpf.natural_iterations "$ITERATIONS")"
MEMORY_HIGH="$(cmdline_value contractbpf.natural_memory_high "$MEMORY_HIGH")"
RECOVERY_MODE="$(cmdline_value contractbpf.natural_recovery "$RECOVERY_MODE")"
LEDGER_STRESS_MODE="$(cmdline_value contractbpf.ledger_stress "$LEDGER_STRESS_MODE")"
HOTPATH_TIMING_MODE="$(cmdline_value contractbpf.hotpath_timing "$HOTPATH_TIMING_MODE")"
SCOPE_RUNTIME_MODE="$(cmdline_value contractbpf.scope_runtime "$SCOPE_RUNTIME_MODE")"

mkdir -p /sys/fs/cgroup/service-A /sys/fs/cgroup/service-B "$HOST_MOUNT" \
    /mnt/scratch /tmp
if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    echo "+memory" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi
if [ -w /sys/fs/cgroup/service-A/memory.high ]; then
    echo "$MEMORY_HIGH" > /sys/fs/cgroup/service-A/memory.high 2>/dev/null || true
    echo "service_a_memory_high=$(cat /sys/fs/cgroup/service-A/memory.high)"
fi

if mount -t 9p -o trans=virtio,version=9p2000.L host0 "$HOST_MOUNT" 2>/tmp/host0-mount.log; then
    mkdir -p "$HOST_MOUNT/artifacts/traces"
    echo "host_9p_mount=1"
else
    echo "host_9p_mount=0"
    cat /tmp/host0-mount.log || true
fi

if [ -b /dev/vda ] && mount -t ext4 -o noatime /dev/vda /mnt/scratch 2>/tmp/scratch-mount.log; then
    PRESSURE_FILE=/mnt/scratch/contractbpf-natural-pressure.bin
    echo "scratch_ext4_mount=1"
else
    echo "scratch_ext4_mount=0"
    cat /tmp/scratch-mount.log 2>/dev/null || true
fi

echo "natural_config runs=$RUNS file_mb=$FILE_MB pressure_mb=$PRESSURE_MB iterations=$ITERATIONS memory_high=$MEMORY_HIGH pressure_file=$PRESSURE_FILE"

if [ -w /sys/kernel/mm/numa/demotion_enabled ]; then
    echo true > /sys/kernel/mm/numa/demotion_enabled
fi

echo "numa_nodes=$(cat /sys/devices/system/node/online 2>/dev/null || echo unknown)"
echo "demotion_enabled=$(cat /sys/kernel/mm/numa/demotion_enabled 2>/dev/null || echo unavailable)"
if [ -d /sys/devices/virtual/memory_tiering ]; then
    for tier in /sys/devices/virtual/memory_tiering/memory_tier*; do
        [ -d "$tier" ] || continue
        tier_name="${tier##*/}"
        echo "memory_tier=$tier_name nodelist=$(cat "$tier/nodelist")"
    done
fi

if [ ! -c /dev/contractbpf ]; then
    echo "ERROR: /dev/contractbpf is not available"
    poweroff_guest
fi

if [ "$LEDGER_STRESS_MODE" -ne 0 ]; then
    echo CONTRACTBPF_LEDGER_STRESS_BEGIN
    if cat /sys/kernel/debug/contractbpf/ledger_stress > /tmp/ledger-stress.log &&
       grep -q CONTRACTBPF_LEDGER_STRESS_OK /tmp/ledger-stress.log &&
       grep -q 'scopes=1024' /tmp/ledger-stress.log &&
       grep -Eq 'events_per_sec=[1-9][0-9]{5,}' /tmp/ledger-stress.log &&
       grep -q 'global_lock_per_event=0' /tmp/ledger-stress.log; then
        cat /tmp/ledger-stress.log
        echo CONTRACTBPF_LEDGER_STRESS_GATE_OK
    else
        cat /tmp/ledger-stress.log 2>/dev/null || true
        echo "ERROR: ledger stress gate failed"
    fi
    poweroff_guest
fi

if [ "$HOTPATH_TIMING_MODE" -ne 0 ]; then
    echo CONTRACTBPF_HOTPATH_TIMING_BEGIN
    if cat /sys/kernel/debug/contractbpf/hotpath_timing > /tmp/hotpath-timing.log &&
       grep -q CONTRACTBPF_HOTPATH_TIMING_OK /tmp/hotpath-timing.log &&
       grep -q CONTRACTBPF_HOTPATH_GATE_OK /tmp/hotpath-timing.log; then
        cat /tmp/hotpath-timing.log
        echo CONTRACTBPF_HOTPATH_TIMING_GATE_OK
    else
        cat /tmp/hotpath-timing.log 2>/dev/null || true
        echo "ERROR: hotpath timing gate failed"
    fi
    poweroff_guest
fi

json_numeric_value()
{
    key="$1"
    file="$2"
    value=0

    while IFS= read -r line; do
        case "$line" in
            *"\"$key\":"*)
                value="${line#*:}"
                value="${value%%,*}"
                value="$(printf '%s' "$value" | sed 's/[^0-9]//g')"
                ;;
        esac
    done < "$file"

    case "$value" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$value" ;;
    esac
}

if [ "$SCOPE_RUNTIME_MODE" -ne 0 ]; then
    echo CONTRACTBPF_SCOPE_RUNTIME_BEGIN
    reset_and_load_two_tenant

    contractctl resolve-scope --scope service-A --type service \
        --cgroup /sys/fs/cgroup/service-A \
        --memcg /sys/fs/cgroup/service-A > /tmp/scope-service-a.json
    contractctl resolve-scope --scope service-B --type service \
        --cgroup /sys/fs/cgroup/service-B \
        --memcg /sys/fs/cgroup/service-B > /tmp/scope-service-b.json
    echo SCOPE_SERVICE_A_BEGIN
    cat /tmp/scope-service-a.json
    echo SCOPE_SERVICE_A_END
    echo SCOPE_SERVICE_B_BEGIN
    cat /tmp/scope-service-b.json
    echo SCOPE_SERVICE_B_END

    a_cgroup_id="$(json_numeric_value cgroup_id /tmp/scope-service-a.json)"
    a_memcg_id="$(json_numeric_value memcg_id /tmp/scope-service-a.json)"
    b_cgroup_id="$(json_numeric_value cgroup_id /tmp/scope-service-b.json)"
    b_memcg_id="$(json_numeric_value memcg_id /tmp/scope-service-b.json)"
    echo "scope_runtime_resolved service=A cgroup_id=$a_cgroup_id memcg_id=$a_memcg_id"
    echo "scope_runtime_resolved service=B cgroup_id=$b_cgroup_id memcg_id=$b_memcg_id"

    start_scx
    run_service_a_bg /usr/local/bin/synthetic_phase_service 10 16
    a_bg="$SERVICE_BG_PID"
    run_service_b_bg /usr/local/bin/synthetic_phase_service 10 16
    b_bg="$SERVICE_BG_PID"
    run_in_service_a /usr/local/bin/memory_pressure "$PRESSURE_FILE.scope" \
        "$FILE_MB" "$PRESSURE_MB" "$ITERATIONS" > /tmp/memory-pressure.scope.log 2>&1 || true
    cat /tmp/memory-pressure.scope.log
    wait "$a_bg" 2>/dev/null || true
    wait "$b_bg" 2>/dev/null || true

    collect_metrics service-A
    echo "DEVICE_LEDGER_BEGIN label=service-B"
    contractctl ledger --scope service-B --format lines > /tmp/scope-ledger.service-B
    cat /tmp/scope-ledger.service-B
    echo "DEVICE_LEDGER_END label=service-B"

    a_sched="$(value_of sched_boost_events /tmp/natural-ledger.service-A)"
    a_queue="$(value_of sched_queue_delay_us /tmp/natural-ledger.service-A)"
    a_pages="$(value_of pages_demoted /tmp/natural-ledger.service-A)"
    a_refaults="$(value_of refault_events /tmp/natural-ledger.service-A)"
    a_faults="$(value_of major_fault_events /tmp/natural-ledger.service-A)"
    b_sched="$(value_of sched_boost_events /tmp/scope-ledger.service-B)"
    b_queue="$(value_of sched_queue_delay_us /tmp/scope-ledger.service-B)"
    b_pages="$(value_of pages_demoted /tmp/scope-ledger.service-B)"

    echo "scope_runtime_metrics service=A sched_boost_events=$a_sched sched_queue_delay_us=$a_queue pages_demoted=$a_pages refault_events=$a_refaults major_fault_events=$a_faults"
    echo "scope_runtime_metrics service=B sched_boost_events=$b_sched sched_queue_delay_us=$b_queue pages_demoted=$b_pages"

    if [ "$a_cgroup_id" -gt 0 ] && [ "$a_memcg_id" -gt 0 ] &&
       [ "$b_cgroup_id" -gt 0 ] && [ "$b_memcg_id" -gt 0 ] &&
       [ "$a_cgroup_id" -ne "$b_cgroup_id" ] &&
       [ "$a_memcg_id" -ne "$b_memcg_id" ] &&
       [ $((a_sched + a_queue)) -gt 0 ] && [ "$a_pages" -gt 0 ] &&
       [ $((a_refaults + a_faults)) -gt 0 ] &&
       [ $((b_sched + b_queue)) -gt 0 ] && [ "$b_pages" -eq 0 ]; then
        echo CONTRACTBPF_SCOPE_RUNTIME_OK
    else
        echo "ERROR: scope runtime attribution gate failed"
    fi

    stop_scx
    cat /tmp/scx_contract_boost.log || true
    poweroff_guest
fi

if [ "$RECOVERY_MODE" -ne 0 ]; then
    echo CONTRACTBPF_NATURAL_RECOVERY_BEGIN
    reset_and_load
    start_scx

    run_pressure_window conflict "$PRESSURE_MB" || true
    collect_metrics conflict

    conflict_pages="$(value_of pages_demoted /tmp/natural-ledger.conflict)"
    conflict_refaults="$(value_of refault_events /tmp/natural-ledger.conflict)"
    conflict_major_faults="$(value_of major_fault_events /tmp/natural-ledger.conflict)"
    conflict_queue="$(value_of sched_queue_delay_us /tmp/natural-ledger.conflict)"
    conflict_demote_state="$(value_of demote_degrade_state /tmp/natural-ledger.conflict)"
    conflict_sched_state="$(value_of sched_degrade_state /tmp/natural-ledger.conflict)"
    conflict_latency="$(value_of LATENCY_SAMPLE_US /tmp/memory-pressure.conflict.log)"

    echo "natural_recovery_conflict pages_demoted=$conflict_pages refault_events=$conflict_refaults major_fault_events=$conflict_major_faults sched_queue_delay_us=$conflict_queue demote_degrade_state=$conflict_demote_state sched_degrade_state=$conflict_sched_state latency_us=$conflict_latency"

    if [ "$conflict_pages" -gt 0 ] && [ $((conflict_refaults + conflict_major_faults)) -gt 0 ] &&
       [ "$conflict_queue" -gt 0 ] && [ "$conflict_demote_state" -ge 2 ] &&
       [ "$conflict_sched_state" -eq 0 ]; then
        echo CONTRACTBPF_NATURAL_RECOVERY_CONFLICT_OK
    else
        echo "ERROR: natural recovery conflict window missing"
        stop_scx
        poweroff_guest
    fi

    run_pressure_window recovery "$PRESSURE_MB" || true
    collect_metrics recovery

    recovery_pages="$(value_of pages_demoted /tmp/natural-ledger.recovery)"
    recovery_refaults="$(value_of refault_events /tmp/natural-ledger.recovery)"
    recovery_major_faults="$(value_of major_fault_events /tmp/natural-ledger.recovery)"
    recovery_queue="$(value_of sched_queue_delay_us /tmp/natural-ledger.recovery)"
    recovery_demote_state="$(value_of demote_degrade_state /tmp/natural-ledger.recovery)"
    recovery_sched_state="$(value_of sched_degrade_state /tmp/natural-ledger.recovery)"
    recovery_latency="$(value_of LATENCY_SAMPLE_US /tmp/memory-pressure.recovery.log)"
    recovery_revoked="$(value_of revoked_demotes /tmp/natural-mm.recovery)"
    page_delta=$((recovery_pages - conflict_pages))

    echo "natural_recovery_metrics pages_demoted_before=$conflict_pages pages_demoted_after=$recovery_pages pages_demoted_delta=$page_delta refault_events=$recovery_refaults major_fault_events=$recovery_major_faults sched_queue_delay_us=$recovery_queue demote_degrade_state=$recovery_demote_state sched_degrade_state=$recovery_sched_state revoked_demotes=$recovery_revoked conflict_latency_us=$conflict_latency recovery_latency_us=$recovery_latency"

    if [ "$recovery_demote_state" -ge 2 ] && [ "$recovery_sched_state" -eq 0 ] &&
       [ "$recovery_revoked" -gt 0 ] && [ "$page_delta" -le 1024 ] &&
       [ "$recovery_latency" -gt 0 ] && [ "$conflict_latency" -gt 0 ] &&
       [ "$recovery_latency" -lt "$conflict_latency" ]; then
        echo CONTRACTBPF_NATURAL_RECOVERY_OK
    else
        echo "ERROR: natural recovery window missing"
    fi

    stop_scx
    cat /tmp/scx_contract_boost.log || true
    poweroff_guest
fi

run=1
while [ "$run" -le "$RUNS" ]; do
    echo "CONTRACTBPF_NATURAL_RUN_BEGIN run=$run"
    reset_and_load
    start_scx

    run_pressure_window "$run" "$PRESSURE_MB" || true
    collect_metrics "$run"

    pages="$(value_of pages_demoted /tmp/natural-ledger.$run)"
    refaults="$(value_of refault_events /tmp/natural-ledger.$run)"
    major_faults="$(value_of major_fault_events /tmp/natural-ledger.$run)"
    queue_delay="$(value_of sched_queue_delay_us /tmp/natural-ledger.$run)"
    bpf_runs="$(value_of bpf_runs /tmp/natural-mm.$run)"
    fault_events=$((refaults + major_faults))

    echo "natural_metrics run=$run pages_demoted=$pages refault_events=$refaults major_fault_events=$major_faults sched_queue_delay_us=$queue_delay bpf_runs=$bpf_runs"

    if [ "$pages" -gt 0 ] && [ "$fault_events" -gt 0 ] &&
       [ "$queue_delay" -gt 0 ] && [ "$bpf_runs" -gt 0 ]; then
        OK_RUNS=$((OK_RUNS + 1))
        echo "CONTRACTBPF_NATURAL_RUN_OK run=$run"
    else
        echo "CONTRACTBPF_NATURAL_RUN_FAIL run=$run"
    fi

    stop_scx
    echo "CONTRACTBPF_NATURAL_RUN_END run=$run"
    run=$((run + 1))
done

cat /tmp/scx_contract_boost.log || true

echo "natural_ok_runs=$OK_RUNS"
if [ "$OK_RUNS" -ge "$RUNS" ]; then
    echo CONTRACTBPF_NATURAL_CONFLICT_5RUN_OK
else
    echo "ERROR: natural conflict reproduced in $OK_RUNS/$RUNS runs"
fi

poweroff_guest
