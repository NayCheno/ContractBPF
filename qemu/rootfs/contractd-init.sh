#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
mount -t cgroup2 cgroup2 /sys/fs/cgroup || true
mkdir -p /sys/fs/cgroup/service-A 2>/dev/null || true
mkdir -p /sys/fs/cgroup/service-B 2>/dev/null || true

set +e
/usr/local/bin/contractd \
    --state-dir /tmp/contractbpf-state \
    --manifest /etc/contractbpf/service_a_sched.yaml \
    --manifest /etc/contractbpf/service_a_paging.yaml \
    --manifest /etc/contractbpf/service_a_composition.yaml \
    > /tmp/contractd.log 2>&1
status=$?
set -e
cat /tmp/contractd.log

set +e
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    load /etc/contractbpf/service_a_sched.yaml > /tmp/contractctl.log 2>&1
ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    load /etc/contractbpf/service_a_paging.yaml >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    load /etc/contractbpf/service_b_sched.yaml >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    load /etc/contractbpf/service_b_paging.yaml >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    load /etc/contractbpf/service_a_composition.yaml >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    charge --policy latency_sched_A --effect boost_task --scope service-A --primary 3 --secondary 900 >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    charge --policy phase_paging_A --effect demote_page --scope service-A --primary 2 --secondary 2 >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    charge --policy aggressive_sched_B --effect boost_task --scope service-B --primary 5 --secondary 1100 >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    charge --policy stale_paging_B --effect demote_page --scope service-B --primary 4 --secondary 4 >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    status >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    ledger --scope service-A >> /tmp/contractctl.log 2>&1 || ctl_status=$?
/usr/local/bin/contractctl \
    --state-dir /tmp/contractctl-state \
    ledger --scope service-B >> /tmp/contractctl.log 2>&1 || ctl_status=$?

if [ "$(grep -c '"status": "charged"' /tmp/contractctl.log || true)" -ne 4 ]; then
    ctl_status=40
fi
if [ "$(grep -c '"result": 0' /tmp/contractctl.log || true)" -lt 4 ]; then
    ctl_status=41
fi
for needle in \
    '"sched_boost_events": 3' \
    '"sched_queue_delay_us": 900' \
    '"pages_demoted": 2' \
    '"refault_events": 2' \
    '"sched_boost_events": 5' \
    '"sched_queue_delay_us": 1100' \
    '"pages_demoted": 4' \
    '"refault_events": 4'
do
    if ! grep -q "$needle" /tmp/contractctl.log; then
        ctl_status=42
    fi
done
set -e
cat /tmp/contractctl.log

if [ "$ctl_status" -eq 0 ]; then
    echo CONTRACTBPF_CONTRACTCTL_OK
fi

if [ "$status" -eq 0 ] && [ "$ctl_status" -eq 0 ] &&
    grep -q CONTRACTBPF_CONTRACTD_OK /tmp/contractd.log; then
    /bin/poweroff-contractbpf
fi

echo "ERROR: contractd failed with status $status, contractctl status $ctl_status"
/bin/poweroff-contractbpf
