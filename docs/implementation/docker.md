# Docker Ubuntu Workflow

The repository can run inside an Ubuntu 24.04 Docker image with the kernel,
QEMU, Rust, BPF, workload, and experiment toolchains installed.

## Build the Image

```sh
docker compose build
```

Equivalent Make target:

```sh
make docker-build
```

## Open a Shell

```sh
docker compose run --rm contractbpf
```

Equivalent Make target:

```sh
make docker-shell
```

All commands below run inside `/workspace`, which is the repository mounted into
the container.

## Smoke Validation

This downloads the pinned Linux kernel, applies the ContractBPF patches, builds
the kernel, builds a minimal initramfs, and boots the artifact in QEMU.

```sh
docker compose run --rm contractbpf make bootstrap kernel qemu-smoke
```

Equivalent Make target from the host:

```sh
make docker-smoke
```

## Full Prototype Gate

This is intentionally long-running. It builds the kernel and executes the QEMU
selftests, sched_ext scenarios, ContractBPF daemon scenario, conflict/recovery
scenarios, synthetic experiment matrix, and memcached companion matrix.

```sh
docker compose run --rm contractbpf make bootstrap kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery experiments memcached-experiments
```

Equivalent Make target:

```sh
make docker-full
```

## Optional KVM Acceleration

QEMU falls back to TCG when `/dev/kvm` is unavailable. On a Linux host with KVM
available, use the override file:

```sh
docker compose -f docker-compose.yml -f docker-compose.kvm.yml run --rm contractbpf make qemu-smoke
```

On Docker Desktop for Windows, `/dev/kvm` is usually unavailable, so QEMU will
run without hardware acceleration and kernel builds/boots will be slower.
