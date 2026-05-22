# ContractBPF Mature-Gate Acceptance Audit

Date: 2026-05-23 Asia/Shanghai; evidence timestamps are UTC
Scope: `D:\Download\ContractBPF_CCF_A_Mature_Tech_and_Acceptance_Gates.md`
Environment used in this iteration: existing Docker Compose service `contractbpf`

## Summary

The repository has made concrete progress through P7 in QEMU, including a
passing single-command `qemu-mature-gates` aggregate with P2 policy-identity,
P3 two-tenant runtime scope-mapping, and QEMU memcached P5/P6 quantitative proxy
targets. A native P5/P6 preflight and native memcached G1/G2/G4/G9 bars runner
now exist and were run inside the current Docker service; they block because
this Docker environment is attached to an unpatched WSL2 host kernel with no
`/dev/contractbpf` and no visible sched_ext state. The native override does
make cgroup v2 memory and writable service scopes visible in Docker.
`docker-compose.native.yml` now provides a privileged host-attached Docker mode
for compatible patched Linux hosts. A remote native mature-gate runner now also
exists for the case where the current Docker service must drive a separate
ContractBPF-capable Linux host over SSH. With no remote host configured, it
records `CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_BLOCKED` instead of producing
native evidence. The machine-readable `acceptance-audit` target verifies P0-P8
and returns nonzero until the full objective is satisfied.
The full P0-P8 objective is still not complete. The current artifact remains a
QEMU correctness/reproducibility prototype plus QEMU synthetic and memcached
matrices. It is not yet CCF-A/NSDI Traditional Research Track ready under the
mature gate definition.

## Gate Status

| Gate | Status | Current Evidence | Remaining Work |
|---|---|---|---|
| P0 reproduce current artifact | Complete for current QEMU artifact | Fresh Docker Compose aggregate passed with `make qemu-mature-gates`. Wrapper log: `artifacts/logs/20260522T175112Z-qemu-mature-gates-wrapper.log`. Latest logs include `20260522T175339Z-qemu-contractbpf-kselftest.log`, `20260522T175346Z-qemu-smoke.log`, `20260522T175354Z-qemu-sched-ext.log`, `20260522T175408Z-qemu-sched-gate.log`, `20260522T175419Z-qemu-mm-hook.log`, `20260522T175426Z-qemu-mm-bpf.log`, `20260522T175434Z-qemu-mm-bpf.log`, `20260522T175443Z-qemu-contractd.log`, `20260522T175458Z-qemu-conflict.log`, `20260522T175510Z-qemu-conflict.log`, `20260522T175510Z-qemu-recovery.log`, `20260522T175523Z-qemu-natural-conflict.log`, `20260522T175558Z-qemu-natural-conflict.log`, `20260522T175617Z-qemu-natural-conflict.log`, `20260522T175627Z-qemu-natural-conflict.log`, `20260522T175638Z-qemu-policy-identity.log`, `20260522T175657Z-qemu-natural-conflict.log`, `20260522T175714Z-qemu-no-violation-overhead.log`, `20260522T175731Z-qemu-memcached-natural.log`, `20260522T175927Z-qemu-experiment-matrix.log`, and `20260522T175955Z-qemu-memcached-matrix.log`. Final evidence bundle: `experiments/artifact_bundles/20260522T180132Z.tar.zst`. | This proves current QEMU artifact reproducibility only, not final P5-P8 mature non-QEMU evidence. |
| P1 remove debugfs final control path | Complete for current QEMU harness | `0007-contractbpf-device-control.patch` adds `/dev/contractbpf` ioctl token install, ledger snapshot, and reset. `0011`/`0012` add `/dev/contractbpf` charge-effect ioctl for non-debugfs controlled evidence. `0016`/`0017` add `/dev/contractbpf` sched/MM gate enable without rewriting manifest token budgets. `contractctl` supports load/gate/unload/status/ledger/events/charge/degrade/reset commands. QEMU logs `20260522T134724Z-qemu-sched-gate.log`, `20260522T134114Z-qemu-contractd.log`, and `20260522T134614Z-qemu-conflict.log` show manifest token install, ioctl gate enable, ioctl charge/reset/ledger use, and `CONTRACTBPF_CONTRACTCTL_OK`/conflict/recovery markers. The synthetic matrix, memcached matrix, conflict/recovery scenario, and sched-gate scenario now use `contractctl reset/load/gate/charge/ledger --format lines` plus manifest budgets; `rg` finds no remaining `cross_scenario`, `mm_simulate_bad_demote`, `sched_gate_enable`, `mm_gate_enable`, or `sched_boost_budget` references under `qemu/rootfs`, `userspace`, or `experiments`. | This is still controlled QEMU evidence, not final natural policy lifecycle or a kernel event stream. Debugfs remains available for snapshots/selftests and kernel development, but not as the harness control path. |
| P2 real policy identity | Complete for current QEMU artifact | `0008`, `0009`, and `0010` move sched/MM/cross hot paths to active manifest-installed policy IDs. `0013`, `0014`, and `0015` add scope-derived policy lookup and avoid fallback policy creation for unknown scopes. `0018`/`0019` add MM-BPF registration. QEMU log `20260522T175638Z-qemu-policy-identity.log` runs two sched_ext binaries in separate cases with distinct policy IDs and scopes: service-A `scx_contract_boost` uses policy ID `2934423261234883545` with `sched_dispatch_events=8`, and service-B `scx_simple` uses policy ID `5860564736192845840` with `sched_dispatch_events=8`. The same log loads two MM BPF policies with distinct kernel program IDs: `phase_paging.bpf.o` ID `29` and `bad_demote.bpf.o` ID `33`. It also shows `effect_ledgers` entries for `latency_sched_A` and `aggressive_sched_B`, then appends `CONTRACTBPF_P2_SOURCE_IDENTITY_OK` after a source grep of final non-`.orig` kernel files for hard-coded `CONTRACT_*_PROG_ID 0` identity use. | This satisfies P2 in QEMU. Scheduler policy identity is the manifest-installed ContractBPF policy ID exercised by separate sched_ext binaries; MM identity is kernel BPF program-derived. |
| P3 real scope mapping | Complete for current QEMU artifact | QEMU log `20260522T175657Z-qemu-natural-conflict.log` resolves service-A and service-B as separate cgroup/memcg scopes. The target starts both tenants in their own scopes, then records service-A scheduler/MM runtime activity into one ledger: `sched_boost_events=125`, `sched_queue_delay_us=2441000`, `pages_demoted=35098`, `refault_events=4173`, and `major_fault_events=78`. Service-B remains separate with its own scheduler activity (`sched_dispatch_events=8`, `sched_boost_events=1`, `sched_queue_delay_us=2006000`) and no paging demotion (`pages_demoted=0`). The run ends with `CONTRACTBPF_SCOPE_RUNTIME_OK`. | This satisfies the P3 acceptance bullets in QEMU. It is still not a substitute for P5-P8 bare-metal/networked-service evidence. |
| P4 real BPF paging path | Complete for current QEMU hook-entry evidence | `bpf/mm/phase_paging.bpf.c`, `bad_demote.bpf.c`, and `conservative_noop_paging.bpf.c` build as real `SEC("syscall")` BPF objects. QEMU log `20260522T144026Z-qemu-mm-bpf.log` shows libbpf loading all three policies, writing read-only-to-BPF `contract_mm_state`, running each program with `BPF_PROG_RUN`, registering each program/map pair through `/dev/contractbpf`, and invoking the kernel MM hook entry point. The hook reports `phase_paging` and `bad_demote` as `demote`/allowed, while `conservative_noop` returns `no_op`/denied. | This satisfies P4 for the QEMU hook-entry path. It is still not P5 natural memory-pressure evidence, not a five-run conflict, and not a production PageFlex-equivalent claim. |
| P5 natural scheduler-paging conflict | Partial, QEMU natural and QEMU memcached quantitative proxy evidence | `artifacts/logs/20260522T175523Z-qemu-natural-conflict.log` records five independent natural runs under QEMU HMAT memory pressure without `cross_scenario`, `mm_simulate_bad_demote`, or `contractctl charge`. It ends with `CONTRACTBPF_NATURAL_CONFLICT_5RUN_OK`; all five runs include page demotions, scheduler queue delay, and refault or major-fault counters. `artifacts/logs/20260522T175731Z-qemu-memcached-natural.log` and `experiments/results/processed/memcached_natural_bars.csv` add same-load memcached proxy bars without `contractctl charge`: G4 P99 `402778 us` versus G1 `3472 us` and G2 `3385 us`, G4 `refault_events=28344`, and G4 `sched_queue_delay_us=3852000`. Native override runner log `artifacts/logs/20260522T182505Z-native-memcached-bars.log` reports `CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED` after preflight failure. Remote executor log `artifacts/logs/20260522T184314Z-remote-native-mature-gates.log` reports `CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_BLOCKED` because no SSH host is configured. The machine audit now rejects native-looking CSVs unless `native_p5p6_preflight.json` passed, raw native logs are present, native markers are present, and QEMU run markers are absent. | Quantitative bars now exist in QEMU only. Final mature-gate evidence still needs non-QEMU/bare-metal networked-service runs on a host exposing `/dev/contractbpf` and sched_ext, either through `docker-compose.native.yml` locally or through the remote native executor. |
| P6 bounded degradation recovery | Partial, QEMU natural and QEMU memcached quantitative proxy evidence | `artifacts/logs/20260522T175558Z-qemu-natural-conflict.log` records a natural conflict followed by recovery. Conflict window: `pages_demoted=24474`, `refault_events=1817`, `major_fault_events=46`, `sched_queue_delay_us=3095000`, `demote_degrade_state=2`, `sched_degrade_state=0`, `latency_us=136635`. Recovery window: `pages_demoted_delta=0`, `revoked_demotes=55376`, `sched_degrade_state=0`, `recovery_latency_us=70244`, ending with `CONTRACTBPF_NATURAL_RECOVERY_OK`. The memcached proxy run reports G9 recovery-window P99 `3312 us` versus G4 `402778 us`, `demote_degrade_state=2`, `sched_degrade_state=0`, `revoked_demotes=99280`, and unaffected-tenant P99 `3469 us` versus G4 `101720 us`, ending with `CONTRACTBPF_MEMCACHED_NATURAL_BARS_GATE_OK`. Native preflight JSON `experiments/results/processed/native_p5p6_preflight.json` records the current Docker host blockers while confirming cgroup writability and native runner dependencies are present. Remote native JSON `experiments/results/processed/remote_native_mature_gates.json` records that no remote SSH host was configured in this run. The machine audit now requires successful native raw-log/preflight provenance before it can accept `native_memcached_bars.csv`. | Recovery bars now exist in QEMU only. Final mature-gate evidence still needs non-QEMU/bare-metal networked-service runs on a ContractBPF-capable host. |
| P7 overhead and scalability | Complete for current QEMU artifact | `0024` raises ledgers to 1024 and removes the global ledger lock from the existing-ledger event update path. `artifacts/logs/20260522T175617Z-qemu-natural-conflict.log` reports `scopes=1024`, `events=100000`, `events_per_sec=583970`, and `global_lock_per_event=0`, ending with `CONTRACTBPF_LEDGER_STRESS_GATE_OK`. `0028-contractbpf-hotpath-timing-selftest.patch` adds a lockless existing-token fast path and direct gate timing selftest. `artifacts/logs/20260522T175627Z-qemu-natural-conflict.log` reports `scheduler_gate_median_ns=100` with target 200 ns and `mm_gate_median_ns=96` with target 500 ns, ending with `CONTRACTBPF_HOTPATH_GATE_OK`. `artifacts/logs/20260522T175714Z-qemu-no-violation-overhead.log` and `experiments/results/processed/no_violation_overhead.csv` report no-violation memcached overhead: P99 `-90.44%`, throughput `-130.22%`, CPU utilization `-2.93%`, ending with `CONTRACTBPF_NO_VIOLATION_OVERHEAD_GATE_OK`. | This satisfies P7 for the QEMU artifact only. It is not bare-metal performance evidence. |
| P8 paper evidence integrity | Partial | `archive_repro.py` bundles raw logs, processed CSVs, figures, metadata, patch hashes, and paper artifacts. Latest bundle before this native-table refresh is `experiments/artifact_bundles/20260522T185700Z.tar.zst`. `make paper-tables` now generates NSDI numeric tables under `paper/nsdi27/generated/` from processed CSVs with `Source-SHA256` comments and `evidence_manifest.json`. It also emits `native_memcached_bars_table.tex` when `experiments/results/processed/native_memcached_bars.csv` exists. The machine audit checks generated table inputs, figure script/input CSV pairs, QEMU/non-QEMU claim scope, introduction length, native raw-log provenance, and stale future-work language after native evidence passes. `make acceptance-audit-tests` now exercises valid native evidence, QEMU-marker rejection, WSL/preflight rejection, and native table generation fixtures. The paper text currently labels the current results as QEMU correctness/reproducibility evidence rather than production performance, and the native preflight/native-bars/remote-native artifacts record why final non-QEMU evidence is absent in this Docker attachment. | Paper still must be audited against final non-QEMU evidence; no bare-metal/networked-service final evidence exists, and P5-P6 final same-load real-service quantitative bars are QEMU-only. |

## Commands Verified In Docker

```sh
docker compose run --rm contractbpf bash -lc "make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery experiments memcached-experiments"
rustup component add rustfmt >/dev/null && cargo fmt --manifest-path userspace/libcontract/Cargo.toml && cargo fmt --manifest-path userspace/contractctl/Cargo.toml && cargo test --manifest-path userspace/libcontract/Cargo.toml && cargo build --manifest-path userspace/contractd/Cargo.toml && cargo build --manifest-path userspace/contractctl/Cargo.toml
make kernel
make qemu-sched-gate
make qemu-contractd
make kselftest qemu-mm-hook qemu-conflict
make kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery experiments memcached-experiments
make experiments
make memcached-experiments
make qemu-contractd qemu-sched-gate qemu-conflict
make kselftest qemu-smoke qemu-sched qemu-mm-hook qemu-recovery
make qemu-conflict
make qemu-recovery
make qemu-sched-gate
make bpf
make qemu-mm-bpf
make qemu-mm-hook
make archive-repro
make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-mm-bpf qemu-contractd qemu-conflict qemu-recovery qemu-natural-conflict qemu-natural-recovery qemu-ledger-stress experiments memcached-experiments
make bootstrap kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-mm-bpf qemu-contractd qemu-conflict qemu-recovery qemu-natural-conflict qemu-natural-recovery qemu-ledger-stress qemu-hotpath-timing experiments memcached-experiments
make qemu-no-violation-overhead
make archive-repro
make qemu-scope-runtime
make archive-repro
make qemu-policy-identity
make archive-repro
make qemu-memcached-natural-bars
make archive-repro
make qemu-mature-gates
python3 experiments/runners/archive_repro.py --timestamp 20260522T180132Z
make native-p5p6-preflight
python3 experiments/runners/archive_repro.py --timestamp 20260522T181329Z
make native-p5p6-bars
python3 experiments/runners/archive_repro.py --timestamp 20260522T181807Z
make acceptance-audit
python3 experiments/runners/archive_repro.py --timestamp 20260522T182229Z
docker compose -f docker-compose.yml -f docker-compose.native.yml run --rm contractbpf make native-p5p6-preflight
docker compose -f docker-compose.yml -f docker-compose.native.yml run --rm contractbpf make native-p5p6-bars
make remote-native-mature-gates
make paper-tables
make acceptance-audit
python3 experiments/runners/archive_repro.py --timestamp 20260522T182531Z
python3 experiments/runners/archive_repro.py --timestamp 20260522T131022Z
python3 experiments/runners/archive_repro.py --timestamp 20260522T132732Z
python3 experiments/runners/archive_repro.py --timestamp 20260522T134222Z
python3 experiments/runners/archive_repro.py --timestamp 20260522T134813Z
python3 experiments/runners/archive_repro.py --timestamp 20260522T135203Z
archive_repro.py via the full P0 make chain, producing 20260522T141141Z
python3 experiments/runners/archive_repro.py, producing 20260522T141241Z
make qemu-conflict qemu-recovery
archive_repro.py via the full P0 make chain, producing 20260522T142256Z
python3 experiments/runners/archive_repro.py, producing 20260522T142422Z
make qemu-mm-bpf
make qemu-mm-hook
archive_repro.py via the full P0 make chain, producing 20260522T144213Z
python3 experiments/runners/archive_repro.py, producing 20260522T144432Z
archive_repro.py via the expanded full chain, producing 20260522T163341Z
archive_repro.py via the clean expanded full chain, producing 20260522T165242Z
archive_repro.py after no-violation overhead, producing 20260522T165827Z
archive_repro.py after qemu-scope-runtime, producing 20260522T170559Z
archive_repro.py after qemu-policy-identity, producing 20260522T171403Z
archive_repro.py after qemu-memcached-natural-bars, producing 20260522T173418Z
archive_repro.py after audit/status refresh, producing 20260522T174122Z
archive_repro.py after qemu-mature-gates and audit/status refresh, producing 20260522T180132Z
archive_repro.py after native P5/P6 preflight, producing 20260522T181329Z
archive_repro.py after native P5/P6 bars runner, producing 20260522T181807Z
archive_repro.py after machine acceptance audit, producing 20260522T182229Z
archive_repro.py after native Docker override validation, producing 20260522T182531Z
remote-native-mature-gates no-host configured path after rebuilding the Docker image with OpenSSH client support, producing 20260522T184314Z-remote-native-mature-gates.log
paper table generation and stricter P8 audit, producing generated table inputs under paper/nsdi27/generated/
```

## Next Required Engineering Step

Run `remote-native-mature-gates` with `CONTRACTBPF_REMOTE=user@host` pointing to
a patched ContractBPF-capable Linux host, or rerun `docker-native-mature-gates`
on a local compatible host. The remaining target is P5/P6 same-load real-service
quantitative bars outside QEMU plus the final P8 evidence audit over those
artifacts.
