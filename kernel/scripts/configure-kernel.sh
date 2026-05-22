#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${CONTRACTBPF_LINUX_DIR:-$ROOT/build/linux}"

if [ ! -d "$SRC_DIR" ]; then
    echo "ERROR: Linux source not found at $SRC_DIR. Run ./kernel/scripts/fetch-linux.sh first." >&2
    exit 1
fi

make -C "$SRC_DIR" x86_64_defconfig

CFG="$SRC_DIR/scripts/config"
if [ ! -x "$CFG" ]; then
    echo "ERROR: kernel scripts/config is missing or not executable in $SRC_DIR" >&2
    exit 1
fi

"$CFG" --file "$SRC_DIR/.config" \
    --enable BPF \
    --enable BPF_SYSCALL \
    --enable BPF_JIT \
    --enable BPF_JIT_ALWAYS_ON \
    --enable BPF_JIT_DEFAULT_ON \
    --enable BPF_EVENTS \
    --disable DEBUG_INFO_NONE \
    --enable DEBUG_INFO_DWARF5 \
    --enable DEBUG_INFO_BTF \
    --enable DEBUG_FS \
    --enable CONTRACTBPF \
    --enable SCHED_CLASS_EXT \
    --enable CGROUPS \
    --enable CGROUP_BPF \
    --enable MEMCG \
    --enable NAMESPACES \
    --enable BLK_DEV_INITRD \
    --enable DEVTMPFS \
    --enable DEVTMPFS_MOUNT \
    --enable PROC_FS \
    --enable SYSFS \
    --enable TMPFS \
    --enable SERIAL_8250 \
    --enable SERIAL_8250_CONSOLE \
    --enable VIRTIO \
    --enable VIRTIO_PCI \
    --enable NET_9P \
    --enable 9P_FS

make -C "$SRC_DIR" olddefconfig

missing=0
for symbol in \
    CONFIG_BPF \
    CONFIG_BPF_SYSCALL \
    CONFIG_BPF_JIT \
    CONFIG_BPF_JIT_ALWAYS_ON \
    CONFIG_BPF_JIT_DEFAULT_ON \
    CONFIG_DEBUG_INFO_BTF \
    CONFIG_DEBUG_FS \
    CONFIG_CONTRACTBPF \
    CONFIG_SCHED_CLASS_EXT \
    CONFIG_CGROUPS \
    CONFIG_CGROUP_BPF \
    CONFIG_MEMCG
do
    if ! grep -q "^${symbol}=y$" "$SRC_DIR/.config"; then
        echo "ERROR: ${symbol}=y missing after olddefconfig" >&2
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "ERROR: kernel config gate failed; inspect $SRC_DIR/.config" >&2
    exit 1
fi

printf 'Configured kernel at %s\n' "$SRC_DIR"
