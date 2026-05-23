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

## Full QEMU Mature-Gate Artifact

This is intentionally long-running. It builds the kernel and executes the QEMU
selftests, sched_ext scenarios, ContractBPF daemon scenario, conflict/recovery
scenarios, policy-identity and runtime-scope checks, QEMU natural conflict and
recovery probes, QEMU overhead/scalability probes, synthetic experiment matrix,
and memcached companion matrices.

```sh
docker compose run --rm contractbpf make qemu-mature-gates
```

Equivalent Make target:

```sh
make docker-full
```

`make docker-mature-gates` is an explicit alias for the same command.

## Native Final-Evidence Preflight

P5/P6 final mature-gate evidence requires a non-QEMU host kernel with
ContractBPF loaded, `/dev/contractbpf` exposed to the container, writable
cgroup v2 service scopes, sched_ext state visible from the container, multiple
memory tiers, and `numa/demotion_enabled=true`. Check that host attachment
before attempting native same-load service runs. On a compatible Linux host,
use the native override so the container runs privileged with host cgroups,
debugfs, kernel modules, and sched_ext visibility:

```sh
docker compose -f docker-compose.yml -f docker-compose.native.yml run --rm contractbpf make native-p5p6-preflight
```

Equivalent Make target:

```sh
make docker-native-preflight
```

This command is expected to fail on Docker Desktop/WSL2 unless the container is
attached to a compatible patched Linux host. It writes a log under
`artifacts/logs/` and a processed JSON report under
`experiments/results/processed/native_p5p6_preflight.json`.

When the preflight passes, run the native same-load memcached bars:

```sh
docker compose -f docker-compose.yml -f docker-compose.native.yml run --rm contractbpf make native-p5p6-bars
```

Equivalent Make target:

```sh
make docker-native-p5p6-bars
```

The runner executes the native G1/G2/G4/G9 memcached matrix and writes
`experiments/results/processed/native_memcached_bars.csv`. If the preflight
fails, it writes `CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED` instead of emitting
final P5/P6 evidence.

To run the native final evidence and then audit/archive in one host-attached
container command:

```sh
make docker-native-mature-gates
```

## Remote Native Mature-Gate Executor

If the local Docker host is WSL2 or otherwise lacks `/dev/contractbpf` and
sched_ext, but a compatible patched Linux host is reachable over SSH, the
existing Docker service can drive the native run remotely. The remote host must
have Docker Compose, a ContractBPF-capable kernel, `/dev/contractbpf`, cgroup
v2 memory support, writable host cgroups, debugfs, and sched_ext.

```sh
docker compose run --rm \
  -e CONTRACTBPF_REMOTE=user@native-host \
  -e CONTRACTBPF_REMOTE_DIR=~/ContractBPF-native \
  contractbpf make remote-native-mature-gates
```

Equivalent Make target when those environment variables and SSH credentials are
already available inside the container:

```sh
make docker-remote-native-mature-gates
```

The runner uses `rsync` to copy the current source tree plus existing QEMU
evidence to the remote host, runs the privileged native Docker override there,
fetches logs, processed results, audits, and bundles back, then reruns the local
acceptance audit. With no `CONTRACTBPF_REMOTE` configured it writes
`CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_BLOCKED` and
`experiments/results/processed/remote_native_mature_gates.json`.

## Acceptance Audit

Generate paper table inputs from the current processed evidence before the
audit when paper/evidence integrity is in scope:

```sh
docker compose run --rm contractbpf make paper-tables
```

Check every P0-P8 gate against the current evidence:

```sh
docker compose run --rm contractbpf make acceptance-audit
```

This target returns nonzero until every mature gate is complete. It writes
`experiments/results/processed/acceptance_gate_audit.json` and
`docs/audits/acceptance_gate_audit_latest.md`. P8 now also checks that NSDI
numeric tables are generated from processed CSVs with source hashes, required
figures have scripts and input CSVs, the paper distinguishes QEMU correctness
from non-QEMU performance, and the introduction stays within the configured
length bound.

For P5/P6, a native CSV alone is not sufficient. The audit also requires a
passing `native_p5p6_preflight.json`, native raw-log markers, raw logs referenced
by the CSV, `evidence_scope=native_memcached`, and absence of QEMU serial/run
markers in the native evidence.

When native evidence exists, `make paper-tables` also emits
`paper/nsdi27/generated/native_memcached_bars_table.tex`, and P8 requires that
generated table plus updated paper claim scope. Stale paper language that still
describes non-QEMU P5/P6 evidence as absent keeps P8 partial after native bars
pass.

The native provenance checks have fixture tests:

```sh
docker compose run --rm contractbpf make acceptance-audit-tests
```

Those tests cover a valid native fixture, QEMU marker rejection, WSL/preflight
rejection, and native paper-table generation.

## Optional KVM Acceleration

QEMU falls back to TCG when `/dev/kvm` is unavailable. On a Linux host with KVM
available, use the override file:

```sh
docker compose -f docker-compose.yml -f docker-compose.kvm.yml run --rm contractbpf make qemu-smoke
```

On Docker Desktop for Windows, `/dev/kvm` is usually unavailable, so QEMU will
run without hardware acceleration and kernel builds/boots will be slower.
