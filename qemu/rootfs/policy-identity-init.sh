#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true
mount -t bpf bpf /sys/fs/bpf 2>/dev/null || true

json_numeric_value() {
    key="$1"
    file="$2"
    sed -n "s/^[[:space:]]*\"$key\": \([0-9][0-9]*\),\{0,1\}$/\1/p" "$file"
}

line_numeric_value() {
    key="$1"
    file="$2"
    sed -n "s/^$key=\([0-9][0-9]*\)$/\1/p" "$file"
}

wait_sched_enabled() {
    i=0
    while [ "$i" -lt 10 ]; do
        state="$(cat /sys/kernel/sched_ext/state)"
        echo "SCHED_EXT_STATE_POLL=$state"
        if [ "$state" = "enabled" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    return 1
}

wait_sched_stopped() {
    i=0
    while [ "$i" -lt 10 ]; do
        state="$(cat /sys/kernel/sched_ext/state)"
        echo "SCHED_EXT_STATE_AFTER_STOP=$state"
        if [ "$state" != "enabled" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    return 1
}

run_sched_case() {
    label="$1"
    service="$2"
    manifest="$3"
    binary="$4"
    shift 4

    echo "POLICY_IDENTITY_SCHED_BEGIN label=$label service=$service binary=$binary"
    /usr/local/bin/contractctl reset --test-only > "/tmp/reset-$label.log" 2>&1
    cat "/tmp/reset-$label.log"

    mkdir -p "/sys/fs/cgroup/$service" 2>/dev/null || true
    echo $$ > "/sys/fs/cgroup/$service/cgroup.procs" 2>/dev/null || true

    /usr/local/bin/contractctl \
        --state-dir "/tmp/policy-identity-$label" \
        load "$manifest" > "/tmp/load-$label.log" 2>&1
    cat "/tmp/load-$label.log"
    policy_id="$(json_numeric_value policy_id "/tmp/load-$label.log")"
    if [ -z "$policy_id" ] || [ "$policy_id" = "0" ]; then
        echo "ERROR: missing nonzero sched policy_id for $label"
        /bin/poweroff-contractbpf
    fi

    /usr/local/bin/contractctl \
        --state-dir "/tmp/policy-identity-$label" \
        gate "$manifest" --enable 1 > "/tmp/gate-$label.log" 2>&1
    cat "/tmp/gate-$label.log"

    "$binary" "$@" > "/tmp/scx-$label.log" 2>&1 &
    scx_pid=$!
    if ! wait_sched_enabled; then
        echo "ERROR: sched_ext did not enable for $label"
        cat "/tmp/scx-$label.log" || true
        kill "$scx_pid" 2>/dev/null || true
        /bin/poweroff-contractbpf
    fi

    /usr/local/bin/synthetic_phase_service 10 12 >/tmp/synthetic-"$label".log 2>&1 || true
    sleep 1

    cat /sys/kernel/debug/contractbpf/sched_snapshot > "/tmp/sched-$label.snapshot"
    cat "/tmp/sched-$label.snapshot"
    /usr/local/bin/contractctl \
        --state-dir "/tmp/policy-identity-$label" \
        ledger --scope "$service" > "/tmp/ledger-$label.json" 2>&1
    cat "/tmp/ledger-$label.json"

    dispatch_events="$(line_numeric_value sched_dispatch_events "/tmp/sched-$label.snapshot")"
    boost_events="$(line_numeric_value sched_boost_events "/tmp/sched-$label.snapshot")"
    queue_delay="$(line_numeric_value sched_queue_delay_us "/tmp/sched-$label.snapshot")"
    scope_line="$(sed -n 's/^scope=\(.*\)$/\1/p' "/tmp/sched-$label.snapshot")"

    if [ -z "$dispatch_events" ] || [ "$dispatch_events" = "0" ]; then
        echo "ERROR: missing dispatch events for $label"
        cat "/tmp/scx-$label.log" || true
        kill "$scx_pid" 2>/dev/null || true
        /bin/poweroff-contractbpf
    fi
    if ! grep -q "policy_id=$policy_id" "/tmp/sched-$label.snapshot"; then
        echo "ERROR: sched snapshot policy_id mismatch for $label expected=$policy_id"
        cat "/tmp/scx-$label.log" || true
        kill "$scx_pid" 2>/dev/null || true
        /bin/poweroff-contractbpf
    fi
    if ! grep -q "\"policy\": \"$(sed -n 's/^policy: \(.*\)$/\1/p' "$manifest")\"" "/tmp/ledger-$label.json"; then
        echo "ERROR: ledger missing policy attribution for $label"
        cat "/tmp/scx-$label.log" || true
        kill "$scx_pid" 2>/dev/null || true
        /bin/poweroff-contractbpf
    fi

    echo "policy_identity_sched label=$label service=$service binary=$binary policy_id=$policy_id scope=$scope_line dispatch_events=$dispatch_events boost_events=${boost_events:-0} queue_delay_us=${queue_delay:-0}"

    kill -TERM "$scx_pid" 2>/dev/null || true
    wait "$scx_pid" 2>/dev/null || true
    if ! wait_sched_stopped; then
        echo "ERROR: sched_ext remained enabled after $label"
        cat "/tmp/scx-$label.log" || true
        /bin/poweroff-contractbpf
    fi
    cat "/tmp/scx-$label.log" || true
    echo "POLICY_IDENTITY_SCHED_END label=$label"
}

run_mm_policy() {
    label="$1"
    obj="$2"
    log="/tmp/mm-$label.log"

    /usr/local/bin/contract_mm_loader "$obj" > "$log" 2>&1
    cat "$log"
    policy_id="$(sed -n 's/^CONTRACTBPF_MM_BPF_REGISTERED policy=.* kernel_policy_id=\([0-9][0-9]*\)$/\1/p' "$log")"
    if [ -z "$policy_id" ] || [ "$policy_id" = "0" ]; then
        echo "ERROR: missing nonzero MM BPF policy id for $label"
        /bin/poweroff-contractbpf
    fi
    echo "policy_identity_mm label=$label policy_id=$policy_id"
}

run_sched_case A service-A /etc/contractbpf/service_a_sched.yaml /usr/local/bin/scx_contract_boost
run_sched_case B service-B /etc/contractbpf/service_b_sched.yaml /usr/local/bin/scx_simple -f

policy_a="$(json_numeric_value policy_id /tmp/load-A.log)"
policy_b="$(json_numeric_value policy_id /tmp/load-B.log)"
if [ "$policy_a" = "$policy_b" ]; then
    echo "ERROR: sched policy IDs are not distinct: $policy_a"
    /bin/poweroff-contractbpf
fi

run_mm_policy phase /usr/local/lib/contractbpf/phase_paging.bpf.o
run_mm_policy bad /usr/local/lib/contractbpf/bad_demote.bpf.o

mm_phase="$(sed -n 's/^CONTRACTBPF_MM_BPF_REGISTERED policy=.* kernel_policy_id=\([0-9][0-9]*\)$/\1/p' /tmp/mm-phase.log)"
mm_bad="$(sed -n 's/^CONTRACTBPF_MM_BPF_REGISTERED policy=.* kernel_policy_id=\([0-9][0-9]*\)$/\1/p' /tmp/mm-bad.log)"
if [ "$mm_phase" = "$mm_bad" ]; then
    echo "ERROR: MM BPF policy IDs are not distinct: $mm_phase"
    /bin/poweroff-contractbpf
fi

echo "policy_identity_summary sched_A=$policy_a sched_B=$policy_b mm_phase=$mm_phase mm_bad=$mm_bad"
echo CONTRACTBPF_POLICY_IDENTITY_SCHED_OK
echo CONTRACTBPF_POLICY_IDENTITY_LEDGER_OK
echo CONTRACTBPF_POLICY_IDENTITY_MM_OK

/bin/poweroff-contractbpf
