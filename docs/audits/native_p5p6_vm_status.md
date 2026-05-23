# Native P5/P6 VM Status

Timestamp UTC: `20260522T220242Z`

## Host

- SSH target: `nya@192.168.128.150`
- Kernel: `6.12.30-contractbpf` (`#4 SMP PREEMPT_DYNAMIC Fri May 22 21:38:18 UTC 2026`)
- Command line: `numa=fake=2G memmap=8G!9G movablecore=4G contractbpf_lower_tier_node=2 panic=60`
- Build basis: the native kernel was built from the VM's bootable Ubuntu kernel config plus ContractBPF/test-required options. The QEMU fragment is not used as the full native config.

## Kernel And Topology Evidence

Observed required options include:

- `CONFIG_CONTRACTBPF=y`
- `CONFIG_SCHED_CLASS_EXT=y`
- `CONFIG_DEBUG_INFO_BTF=y`
- `CONFIG_CGROUP_BPF=y`
- `CONFIG_MEMCG=y`
- `CONFIG_NUMA=y`
- `CONFIG_NUMA_EMU=y`
- `CONFIG_MIGRATION=y`
- `CONFIG_MEMORY_HOTPLUG=y`
- `CONFIG_BLK_DEV_PMEM=y`
- `CONFIG_DEV_DAX_KMEM=y`

Native lower-tier evidence:

- `/sys/devices/virtual/memory_tiering/memory_tier4/nodelist`: `0-1`
- `/sys/devices/virtual/memory_tiering/memory_tier22/nodelist`: `2`
- `/sys/kernel/mm/numa/demotion_enabled`: `true`
- dmesg: `Demotion targets for Node 0: preferred: 2, fallback: 2`
- dmesg: `Demotion targets for Node 1: preferred: 2, fallback: 2`

Topology log: `artifacts/logs/20260522T215525Z-native-lower-tier-topology.log`

## Implementation Boundary

Pure VMware configuration was insufficient. e820 PMEM plus DAX/KMEM could expose PMEM and DAX mechanics, but the guest retained ordinary DRAM in the candidate node, so Linux kept all nodes in the default DRAM tier and produced no demotion target. Diagnostic log: `artifacts/logs/20260522T213500Z-native-pmem-dax-lower-tier-attempt.log`.

The passing run therefore uses kernel patch `0029-contractbpf-native-lower-tier-node.patch`, which adds explicit boot parameter `contractbpf_lower_tier_node=<nid>`. This models node2 as a lower memory tier for native VM evidence. It does not inject counters or fabricate workload results; demotion/refault/queue-delay counters are produced by the running kernel under memory pressure. It should not be described as stock bare-metal CXL/PMEM behavior.

## Passing Native Bars

Run timestamp: `20260522T215525Z`

Configuration:

- `CONTRACTBPF_NATIVE_OPS_A=1800`
- `CONTRACTBPF_NATIVE_OPS_B=3000`
- `CONTRACTBPF_NATIVE_VALUE_A=262144`
- `CONTRACTBPF_NATIVE_VALUE_B=1024`
- `CONTRACTBPF_NATIVE_FILE_MB=256`
- `CONTRACTBPF_NATIVE_PRESSURE_MB=3072`
- `CONTRACTBPF_NATIVE_ITERATIONS=1`
- `CONTRACTBPF_NATIVE_MEMORY_HIGH=134217728`
- `CONTRACTBPF_PRESSURE_MEMPOLICY=bind`
- `CONTRACTBPF_NATIVE_CONFLICT_WARMUP_S=2.0`
- `CONTRACTBPF_NATIVE_RECOVERY_SLEEP_S=2.0`

| Group | P99 us | Tenant-B P99 us | Queue delay us | Pages demoted | Refaults | Major faults | Sched state | Demote state |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| G1 | 8202 | 378 | 0 | 0 | 0 | 0 | 0 | 0 |
| G2 | 8354 | 137 | 0 | 0 | 0 | 0 | 0 | 0 |
| G4 | 167208 | 75 | 225184000 | 3520 | 186268 | 25258 | 0 | 2 |
| G9 | 18455 | 63 | 433953000 | 6072 | 251475 | 44327 | 0 | 2 |

Evidence files:

- CSV: `experiments/results/processed/native_memcached_bars.csv`
- Raw log: `experiments/results/raw/20260522T215525Z-native-memcached-bars.log`
- Artifact log: `artifacts/logs/20260522T215525Z-native-memcached-bars.log`
- Preflight log: `artifacts/logs/20260522T215525Z-native-p5p6-preflight.log`

## Final Gate Result

Commands:

- `docker compose run --rm contractbpf make acceptance-audit-tests`
- `docker compose run --rm contractbpf make paper-tables acceptance-audit`
- `docker compose run --rm contractbpf make archive-repro`
- `docker compose run --rm contractbpf make acceptance-audit`

Final audit:

- `docs/audits/acceptance_gate_audit_latest.md`
- `experiments/results/processed/acceptance_gate_audit.json`
- `experiments/artifact_bundles/20260522T220211Z.tar.zst`

Result: P0-P8 are complete and the final audit reports `CONTRACTBPF_ACCEPTANCE_AUDIT_OK`.
