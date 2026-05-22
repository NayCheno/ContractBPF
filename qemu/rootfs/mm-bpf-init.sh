#!/bin/sh
set -eu

echo CONTRACTBPF_BOOT_OK

mount -t devtmpfs devtmpfs /dev || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mkdir -p /sys/fs/bpf 2>/dev/null || true
mount -t bpf bpf /sys/fs/bpf 2>/dev/null || true

for obj in \
    /usr/local/lib/contractbpf/phase_paging.bpf.o \
    /usr/local/lib/contractbpf/bad_demote.bpf.o \
    /usr/local/lib/contractbpf/conservative_noop_paging.bpf.o
do
    /usr/local/bin/contract_mm_loader "$obj"
done

echo CONTRACTBPF_MM_BPF_LOAD_OK
echo CONTRACTBPF_MM_BPF_DECISION_OK
/bin/poweroff-contractbpf
