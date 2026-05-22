# Kernel Workspace

This directory contains version pins, config fragments, patch placeholders, selftests, and scripts for the Linux/QEMU artifact.

M1 uses a vanilla pinned kernel. ContractBPF patches must remain inactive until the vanilla `sched_ext`-capable kernel builds and boots in QEMU.

Default generated paths:

- Linux source: `build/linux/`
- downloaded tarballs: `build/downloads/`
- build logs: `artifacts/logs/`
- boot image: `build/linux/arch/x86/boot/bzImage`

