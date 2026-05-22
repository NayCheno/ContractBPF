# QEMU Validation

QEMU is the only supported place to boot experimental kernels or load experimental BPF policies for this artifact.

M1 smoke boot:

```sh
make bootstrap
make kernel
make qemu-smoke
```

The smoke log must contain `CONTRACTBPF_BOOT_OK`.

