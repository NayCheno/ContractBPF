# STATUS

## Current milestone
Maturation toward `ContractBPF_CCF_A_Mature_Tech_and_Acceptance_Gates.md`

## Last completed action
- Change: added `experiments/tests/test_acceptance_gate_audit.py` and `make acceptance-audit-tests` for native evidence provenance fixtures.
- Command: `docker compose run --rm contractbpf make acceptance-audit-tests`
- Result: PASS
- Evidence: 4 fixture tests pass: valid native bars with passing preflight/raw-log markers, rejection of QEMU markers in native raw logs, rejection of WSL preflight environment, and generation of `native_memcached_bars_table.tex` when native CSV evidence exists.
- Command: `docker compose run --rm contractbpf make acceptance-audit`
- Result: INCOMPLETE, exit 2
- Markdown audit: `docs/audits/acceptance_gate_audit_latest.md` (`20260522T190721Z`)
- Evidence: current result remains P0-P4/P7 complete and P5/P6/P8 partial because `experiments/results/processed/native_memcached_bars.csv` is still absent; the audit now records `experiments/artifact_bundles/20260522T190625Z.tar.zst` as the latest bundle.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T190625Z --command "acceptance audit fixtures and final no-native audit refresh"`
- Result: PASS
- Archive: `artifacts/repro/20260522T190625Z/`, `experiments/artifact_bundles/20260522T190625Z.tar.zst`
- Change: extended paper table generation and P8 auditing for future successful native evidence.
- Command: `docker compose run --rm contractbpf make paper-tables`
- Result: PASS
- Evidence: with no `native_memcached_bars.csv` present, `paper/nsdi27/generated/native_memcached_bars_table.tex` is absent and `evidence_manifest.json` lists only QEMU-derived tables. When native bars exist, the generator will emit the native table and include it in the manifest.
- Command: `docker compose run --rm contractbpf make -n native-mature-gates remote-native-mature-gates docker-remote-native-mature-gates`
- Result: PASS inside Docker
- Evidence: `native-mature-gates` now runs `native-p5p6-bars`, then `paper-tables`, then `acceptance-audit`, then `archive-repro`; the remote SSH runner now runs `make paper-tables` after native bars before the remote acceptance audit. The host-side `make -n` remains unreliable on this Windows/MSYS path, so Docker is the authoritative validation environment.
- Evidence: P8 audit now requires the generated native table when native bars pass and rejects stale paper language saying non-QEMU evidence is still future work after native evidence is present.
- Command: `docker compose run --rm contractbpf make acceptance-audit`
- Result: INCOMPLETE, exit 2
- Markdown audit: `docs/audits/acceptance_gate_audit_latest.md` (`20260522T190137Z`)
- Evidence: current no-native state still reports P5/P6/P8 partial, and the manifest has no native table because `native_memcached_bars.csv` is still missing.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T190100Z --command "native paper table path and conditional P8 audit"`
- Result: PASS
- Archive: `artifacts/repro/20260522T190100Z/`, `experiments/artifact_bundles/20260522T190100Z.tar.zst`
- Change: strengthened `acceptance_gate_audit.py` so P5/P6 native evidence cannot be satisfied by a copied or edited CSV alone.
- Command: `docker compose run --rm contractbpf python3 -m py_compile experiments/runners/acceptance_gate_audit.py`
- Result: PASS
- Command: `docker compose run --rm contractbpf make acceptance-audit`
- Result: INCOMPLETE, exit 2
- Markdown audit: `docs/audits/acceptance_gate_audit_latest.md` (`20260522T185728Z`)
- Evidence: native P5/P6 validation now requires `native_p5p6_preflight.json` with `preflight_ok=true`, a non-QEMU/non-WSL environment string, native raw logs referenced by the CSV, `CONTRACTBPF_NATIVE_MEMCACHED_BARS_BEGIN`, `CONTRACTBPF_NATIVE_MEMCACHED_BARS_OK`, `evidence_scope=native_memcached`, and absence of QEMU serial/run markers. Current status remains partial because `native_memcached_bars.csv` is missing.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T185700Z --command "strict native evidence provenance audit"`
- Result: PASS
- Archive: `artifacts/repro/20260522T185700Z/`, `experiments/artifact_bundles/20260522T185700Z.tar.zst`
- Change: added `experiments/analysis/generate_paper_tables.py`, `make paper-tables`, generated NSDI table inputs under `paper/nsdi27/generated/`, and strengthened the machine P8 audit so paper numeric tables must be tied to processed CSVs with source hashes.
- Command: `docker compose run --rm contractbpf make paper-tables`
- Result: PASS
- Generated: `paper/nsdi27/generated/controlled_qemu_matrix_table.tex`, `paper/nsdi27/generated/qemu_memcached_matrix_table.tex`, `paper/nsdi27/generated/qemu_memcached_natural_bars_table.tex`, `paper/nsdi27/generated/qemu_no_violation_overhead_table.tex`, and `paper/nsdi27/generated/evidence_manifest.json`
- Evidence: the NSDI draft now `\input{}`s generated numeric tables rather than hard-coded matrix numbers, and the surrounding prose was tightened so conflict/recovery claims point at the natural QEMU evidence rather than stale controlled-matrix wording.
- Command: `docker compose run --rm contractbpf make acceptance-audit`
- Result: INCOMPLETE, exit 2
- Markdown audit: `docs/audits/acceptance_gate_audit_latest.md` (`20260522T185307Z`)
- Evidence: stricter P8 subchecks now pass for generated paper tables, figure script/input mapping, QEMU/non-QEMU claim scope, and introduction length (`introduction_words=558 target<=1800`). P8 remains partial only because final native non-QEMU evidence is still missing.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T185300Z --command "paper table generation and stricter P8 audit"`
- Result: PASS
- Archive: `artifacts/repro/20260522T185300Z/`, `experiments/artifact_bundles/20260522T185300Z.tar.zst`
- Change: added `experiments/runners/run_remote_native_mature_gates.py`, `remote-native-mature-gates`, and `docker-remote-native-mature-gates` so the existing Docker service can drive native final-evidence runs on a separate ContractBPF-capable Linux host over SSH when the local Docker host is WSL2 or otherwise missing `/dev/contractbpf`/sched_ext.
- Command: `docker compose build contractbpf`
- Result: PASS
- Evidence: rebuilt `contractbpf-ubuntu:24.04` with `openssh-client`; `ssh -V` reports `OpenSSH_9.6p1 Ubuntu-3ubuntu13.16` and `rsync --version` reports `3.2.7`.
- Command: `docker compose run --rm contractbpf make remote-native-mature-gates`
- Result: BLOCKED, exit 2
- Log: `artifacts/logs/20260522T184314Z-remote-native-mature-gates.log`
- Processed JSON: `experiments/results/processed/remote_native_mature_gates.json`
- Evidence: the remote-native executor records `CONTRACTBPF_REMOTE_NATIVE_MATURE_GATES_BLOCKED` because no `CONTRACTBPF_REMOTE` SSH host is configured in this environment. The runner is now available to sync the current QEMU evidence to a compatible remote host, run `docker-compose.native.yml` there, fetch native bars/audits/bundles back, and rerun the local machine-readable acceptance audit.
- Command: `docker compose run --rm contractbpf make acceptance-audit`
- Result: INCOMPLETE, exit 2
- Markdown audit: `docs/audits/acceptance_gate_audit_latest.md` (`20260522T184541Z`)
- Evidence: post-remote audit still reports P0-P4 and P7 complete; P5, P6, and P8 remain partial because `experiments/results/processed/native_memcached_bars.csv` is still missing.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T184500Z --command "remote-native executor, rebuilt image, and acceptance audit refresh"`
- Result: PASS
- Archive: `artifacts/repro/20260522T184500Z/`, `experiments/artifact_bundles/20260522T184500Z.tar.zst`
- Change: added `docker-compose.native.yml` and host-attached Make targets (`docker-native-preflight`, `docker-native-p5p6-bars`, `docker-native-mature-gates`) so the existing Docker service can consume a patched non-QEMU Linux host when `/dev/contractbpf`, writable cgroups, debugfs, and sched_ext are available.
- Command: `docker compose -f docker-compose.yml -f docker-compose.native.yml run --rm contractbpf make native-p5p6-bars`
- Result: BLOCKED, exit 2
- Log: `artifacts/logs/20260522T182505Z-native-memcached-bars.log`
- Preflight log: `artifacts/logs/20260522T182505Z-native-p5p6-preflight.log`
- Evidence: the host-attached native Docker override runs and now passes cgroup v2 memory/writability checks, but final native P5/P6 still cannot run because the host kernel is WSL2 without `/dev/contractbpf` and without `/sys/kernel/sched_ext/state`.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T182531Z`
- Result: PASS
- Archive: `artifacts/repro/20260522T182531Z/`, `experiments/artifact_bundles/20260522T182531Z.tar.zst`
- Command: `docker compose run --rm contractbpf make acceptance-audit`
- Result: INCOMPLETE, exit 2
- Processed JSON: `experiments/results/processed/acceptance_gate_audit.json`
- Markdown audit: `docs/audits/acceptance_gate_audit_latest.md`
- Evidence: machine-readable P0-P8 audit now exists and intentionally fails until the mature gate is fully satisfied. Current result: P0-P4 and P7 are complete; P5, P6, and P8 are partial because `experiments/results/processed/native_memcached_bars.csv` is missing and the native bars runner is blocked by the current WSL2 Docker host attachment.
- Command: `docker compose run --rm contractbpf make native-p5p6-bars`
- Result: BLOCKED, exit 2
- Log: `artifacts/logs/20260522T181720Z-native-memcached-bars.log`
- Preflight log: `artifacts/logs/20260522T181720Z-native-p5p6-preflight.log`
- Processed JSON: `experiments/results/processed/native_p5p6_preflight.json`
- Evidence: the native P5/P6 same-load memcached bars runner now exists and refuses to produce final bars unless the host passes native ContractBPF preflight. In the current Docker attachment it records `CONTRACTBPF_NATIVE_MEMCACHED_BARS_BLOCKED` because the preflight reports host kernel `6.6.87.2-microsoft-standard-WSL2`, missing `/dev/contractbpf`, read-only `/sys/fs/cgroup`, and missing `/sys/kernel/sched_ext/state`. Required tools are built and present: `contractctl`, `scx_contract_boost`, `contract_mm_loader`, `bad_demote.bpf.o`, `memcached_ascii_load`, `memory_pressure`, and `/usr/bin/memcached`.
- Command: `docker compose run --rm contractbpf make native-p5p6-preflight`
- Result: BLOCKED, exit 2
- Log: `artifacts/logs/20260522T181320Z-native-p5p6-preflight.log`
- Processed JSON: `experiments/results/processed/native_p5p6_preflight.json`
- Evidence: final native P5/P6 evidence is not runnable in the current Docker attachment. The preflight reports host kernel `6.6.87.2-microsoft-standard-WSL2`, missing `/dev/contractbpf`, read-only `/sys/fs/cgroup`, and missing `/sys/kernel/sched_ext/state`. Built userspace/BPF/workload tools are present, so the remaining blocker is the host/kernel/container environment required for non-QEMU evidence.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T181807Z`
- Result: PASS
- Archive: `artifacts/repro/20260522T181807Z/`, `experiments/artifact_bundles/20260522T181807Z.tar.zst`
- Command: `docker compose run --rm contractbpf make qemu-mature-gates`
- Result: PASS
- Wrapper log: `artifacts/logs/20260522T175112Z-qemu-mature-gates-wrapper.log`
- Key logs: `artifacts/logs/20260522T175339Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260522T175346Z-qemu-smoke.log`, `artifacts/logs/20260522T175354Z-qemu-sched-ext.log`, `artifacts/logs/20260522T175408Z-qemu-sched-gate.log`, `artifacts/logs/20260522T175419Z-qemu-mm-hook.log`, `artifacts/logs/20260522T175426Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T175434Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T175443Z-qemu-contractd.log`, `artifacts/logs/20260522T175458Z-qemu-conflict.log`, `artifacts/logs/20260522T175510Z-qemu-conflict.log`, `artifacts/logs/20260522T175510Z-qemu-recovery.log`, `artifacts/logs/20260522T175523Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T175558Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T175617Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T175627Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T175638Z-qemu-policy-identity.log`, `artifacts/logs/20260522T175657Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T175714Z-qemu-no-violation-overhead.log`, `artifacts/logs/20260522T175731Z-qemu-memcached-natural.log`, `artifacts/logs/20260522T175927Z-qemu-experiment-matrix.log`, and `artifacts/logs/20260522T175955Z-qemu-memcached-matrix.log`.
- Processed CSV: `experiments/results/processed/memcached_natural_bars.csv`
- Processed CSV: `experiments/results/processed/no_violation_overhead.csv`
- Evidence: the single-command QEMU mature-gate aggregate passes. It includes P2 policy identity (`CONTRACTBPF_P2_SOURCE_IDENTITY_OK`), P3 runtime scope mapping (`CONTRACTBPF_SCOPE_RUNTIME_OK`), P5/P6 QEMU memcached natural quantitative proxy (`CONTRACTBPF_MEMCACHED_NATURAL_BARS_GATE_OK`), and P7 no-violation overhead (`CONTRACTBPF_NO_VIOLATION_OVERHEAD_GATE_OK`). Latest memcached natural bars: G4 P99 `402778 us` versus G1 `3472 us` and G2 `3385 us`; G9 recovery-window P99 `3312 us`; G9 unaffected-tenant P99 `3469 us` versus G4 `101720 us`; G9 `revoked_demotes=99280`. Latest no-violation overhead: P99 `-90.44%`, throughput `-130.22%`, and CPU utilization overhead `-2.93%`.
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py --timestamp 20260522T180132Z`
- Result: PASS
- Archive: `artifacts/repro/20260522T180132Z/`, `experiments/artifact_bundles/20260522T180132Z.tar.zst`
- Command: `docker compose run --rm contractbpf make qemu-policy-identity`
- Result: PASS
- Log: `artifacts/logs/20260522T171317Z-qemu-policy-identity.log`
- Evidence: P2 policy identity passes in QEMU. Two sched_ext binaries run in separate cases with distinct manifest-installed ContractBPF policy IDs: service-A `scx_contract_boost` uses `2934423261234883545` with `sched_dispatch_events=8`, and service-B `scx_simple` uses `5860564736192845840` with `sched_dispatch_events=8`. Two MM BPF policies load with distinct kernel program IDs: `phase_paging.bpf.o` uses `29`, and `bad_demote.bpf.o` uses `33`. `contractctl ledger` emits `effect_ledgers` for `latency_sched_A` and `aggressive_sched_B`; source grep appends `CONTRACTBPF_P2_SOURCE_IDENTITY_OK`.
- Command: `docker compose run --rm contractbpf make archive-repro`
- Result: PASS
- Archive: `artifacts/repro/20260522T171403Z/`, `experiments/artifact_bundles/20260522T171403Z.tar.zst`
- Command: `docker compose run --rm contractbpf make qemu-scope-runtime`
- Result: PASS
- Log: `artifacts/logs/20260522T170516Z-qemu-natural-conflict.log`
- Evidence: P3 runtime scope mapping passes in QEMU with `CONTRACTBPF_SCOPE_RUNTIME_OK`. `contractctl resolve-scope` maps service-A to `cgroup_id=24 memcg_id=24` and service-B to `cgroup_id=38 memcg_id=38`. Runtime scheduler/MM activity joins in service-A's ledger (`sched_boost_events=99`, `sched_queue_delay_us=2461000`, `pages_demoted=34852`, `refault_events=1272`, `major_fault_events=51`), while service-B remains separate (`sched_dispatch_events=8`, `sched_boost_events=1`, `pages_demoted=0`).
- Command: `docker compose run --rm contractbpf make archive-repro`
- Result: PASS
- Archive: `artifacts/repro/20260522T170559Z/`, `experiments/artifact_bundles/20260522T170559Z.tar.zst`
- Command: `docker compose run --rm contractbpf make qemu-no-violation-overhead`
- Result: PASS
- Log: `artifacts/logs/20260522T165754Z-qemu-no-violation-overhead.log`
- Processed CSV: `experiments/results/processed/no_violation_overhead.csv`
- Evidence: no-violation memcached comparison under QEMU reports `p99_overhead_pct=-45.25`, `throughput_overhead_pct=-61.96`, and `cpu_overhead_pct=2.22`; `CONTRACTBPF_NO_VIOLATION_OVERHEAD_GATE_OK`.
- Command: `docker compose run --rm contractbpf make archive-repro`
- Result: PASS
- Archive: `artifacts/repro/20260522T165827Z/`, `experiments/artifact_bundles/20260522T165827Z.tar.zst`
- Command: `docker compose run --rm contractbpf bash -lc "make bootstrap kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-mm-bpf qemu-contractd qemu-conflict qemu-recovery qemu-natural-conflict qemu-natural-recovery qemu-ledger-stress qemu-hotpath-timing experiments memcached-experiments"`
- Result: PASS
- Wrapper log: `artifacts/logs/20260523T004602Z-validation-expanded.log`
- Logs: `artifacts/logs/20260522T164839Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260522T164845Z-qemu-smoke.log`, `artifacts/logs/20260522T164854Z-qemu-sched-ext.log`, `artifacts/logs/20260522T164908Z-qemu-sched-gate.log`, `artifacts/logs/20260522T164920Z-qemu-mm-hook.log`, `artifacts/logs/20260522T164927Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T164934Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T164944Z-qemu-contractd.log`, `artifacts/logs/20260522T165000Z-qemu-conflict.log`, `artifacts/logs/20260522T165013Z-qemu-conflict.log`, `artifacts/logs/20260522T165013Z-qemu-recovery.log`, `artifacts/logs/20260522T165025Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T165103Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T165122Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T165133Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T165144Z-qemu-experiment-matrix.log`, `artifacts/logs/20260522T165213Z-qemu-memcached-matrix.log`
- Auto-archive: `artifacts/repro/20260522T165242Z/`, `experiments/artifact_bundles/20260522T165242Z.tar.zst`
- Evidence: clean kernel extraction plus patch application is now stable after the 0026/0027 idempotence fix and new 0028 hotpath patch.
- Evidence: P7 QEMU hotpath timing passes: `scheduler_gate_median_ns=100` (target 200 ns), `mm_gate_median_ns=95` (target 500 ns), and `CONTRACTBPF_HOTPATH_GATE_OK` in `artifacts/logs/20260522T165133Z-qemu-natural-conflict.log`.
- Evidence: P7 QEMU ledger scalability passes: `scopes=1024`, `events=100000`, `events_per_sec=589928`, `global_lock_per_event=0` in `artifacts/logs/20260522T165122Z-qemu-natural-conflict.log`.
- Command: `docker compose run --rm contractbpf bash -lc "make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-mm-bpf qemu-contractd qemu-conflict qemu-recovery qemu-natural-conflict qemu-natural-recovery qemu-ledger-stress experiments memcached-experiments"`
- Result: PASS
- Wrapper log: `artifacts/logs/20260523T002723Z-validation-full.log`
- Logs: `artifacts/logs/20260522T162947Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260522T162954Z-qemu-smoke.log`, `artifacts/logs/20260522T163002Z-qemu-sched-ext.log`, `artifacts/logs/20260522T163016Z-qemu-sched-gate.log`, `artifacts/logs/20260522T163028Z-qemu-mm-hook.log`, `artifacts/logs/20260522T163035Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T163043Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T163052Z-qemu-contractd.log`, `artifacts/logs/20260522T163107Z-qemu-conflict.log`, `artifacts/logs/20260522T163120Z-qemu-conflict.log`, `artifacts/logs/20260522T163120Z-qemu-recovery.log`, `artifacts/logs/20260522T163132Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T163212Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T163231Z-qemu-natural-conflict.log`, `artifacts/logs/20260522T163242Z-qemu-experiment-matrix.log`, `artifacts/logs/20260522T163311Z-qemu-memcached-matrix.log`
- Auto-archive: `artifacts/repro/20260522T163341Z/`, `experiments/artifact_bundles/20260522T163341Z.tar.zst`
- Evidence: QEMU natural conflict now passes 5 independent runs without `cross_scenario`, `mm_simulate_bad_demote`, or `contractctl charge`: `CONTRACTBPF_NATURAL_CONFLICT_5RUN_OK` with real demotion/refault/fault/delay counters in `20260522T163132Z-qemu-natural-conflict.log`.
- Evidence: QEMU natural recovery now revokes demote while preserving scheduler activity: `CONTRACTBPF_NATURAL_RECOVERY_OK`, `pages_demoted_delta=0`, `demote_degrade_state=2`, `sched_degrade_state=0`, `revoked_demotes=183037`, `conflict_latency_us=732192`, `recovery_latency_us=118693` in `20260522T163212Z-qemu-natural-conflict.log`.
- Evidence: QEMU ledger stress supports 1024 scopes and sustains 100000 events at `events_per_sec=587144` with `global_lock_per_event=0` in `20260522T163231Z-qemu-natural-conflict.log`.
- Command: `docker compose run --rm contractbpf bash -lc "rustup component add rustfmt >/dev/null && cargo fmt --manifest-path userspace/libcontract/Cargo.toml && cargo fmt --manifest-path userspace/contractctl/Cargo.toml && cargo fmt --manifest-path userspace/contractd/Cargo.toml && cargo test --manifest-path userspace/libcontract/Cargo.toml && cargo build --manifest-path userspace/contractd/Cargo.toml && cargo build --manifest-path userspace/contractctl/Cargo.toml"`
- Result: PASS
- Command: `docker compose run --rm contractbpf make kernel`
- Result: PASS
- Command: `docker compose run --rm contractbpf make bpf`
- Result: PASS
- Evidence: `bpf/mm/*.bpf.c` now builds real `SEC("syscall")` BPF objects under `build/bpf/*.bpf.o`, and `build/bpf/contract_mm_loader` is built with libbpf.
- Command: `docker compose run --rm contractbpf bash -lc "rustup component add rustfmt >/dev/null && cargo fmt --manifest-path userspace/libcontract/Cargo.toml && cargo fmt --manifest-path userspace/contractctl/Cargo.toml && cargo fmt --manifest-path userspace/contractd/Cargo.toml && cargo test --manifest-path userspace/libcontract/Cargo.toml && cargo build --manifest-path userspace/contractctl/Cargo.toml && cargo build --manifest-path userspace/contractd/Cargo.toml"`
- Result: PASS
- Command: `docker compose run --rm contractbpf make experiments`
- Result: PASS
- Log: `artifacts/logs/20260522T133924Z-qemu-experiment-matrix.log`
- Evidence: the synthetic G1-G9 matrix now uses `contractctl reset/load/gate/charge/ledger --format lines` and `/dev/contractbpf` for controlled accounting. `qemu/rootfs/matrix-init.sh` no longer contains or emits debugfs control writes for `cross_scenario`, `mm_simulate_bad_demote`, `sched_gate_enable`, `mm_gate_enable`, or `sched_boost_budget`. G9 records ioctl ledger evidence with `pages_demoted_per_epoch=8`, `refault_events=8`, and `demote_degrade_state=2`.
- Command: `docker compose run --rm contractbpf make memcached-experiments`
- Result: PASS
- Log: `artifacts/logs/20260522T134004Z-qemu-memcached-matrix.log`
- Evidence: the memcached G1-G9 companion matrix now uses the same ioctl-controlled path. `qemu/rootfs/memcached-matrix-init.sh` no longer contains or emits debugfs control writes for `cross_scenario`, `mm_simulate_bad_demote`, `sched_gate_enable`, `mm_gate_enable`, or `sched_boost_budget`.
- Command: `docker compose run --rm contractbpf make qemu-contractd`
- Result: PASS
- Log: `artifacts/logs/20260522T134114Z-qemu-contractd.log`
- Evidence: `contractd`/`contractctl` still install tokens and enable sched/MM gates through `/dev/contractbpf`.
- Command: `docker compose run --rm contractbpf make qemu-contractd`
- Result: PASS
- Log: `artifacts/logs/20260522T135113Z-qemu-contractd.log`
- Evidence: `contractctl ledger` now emits `effect_ledgers` with explicit `policy`, `effect`, `scope`, and named primary/secondary counters. The log shows service-A `latency_sched_A`/`sched_boost` and `phase_paging_A`/`mm_demote_page`, plus service-B `aggressive_sched_B`/`sched_boost` and `stale_paging_B`/`mm_demote_page`.
- Command: `docker compose run --rm contractbpf make qemu-conflict qemu-recovery qemu-sched-gate`
- Result: PASS
- Logs: `artifacts/logs/20260522T134554Z-qemu-conflict.log`, `artifacts/logs/20260522T134614Z-qemu-conflict.log`, `artifacts/logs/20260522T134614Z-qemu-recovery.log`, `artifacts/logs/20260522T134724Z-qemu-sched-gate.log`
- Evidence: `qemu-conflict`/`qemu-recovery` now emit unguarded/guarded snapshots from `/dev/contractbpf` ledger reads instead of `cross_scenario`; recovery CSV `artifacts/traces/20260522T134614Z-recovery.csv` records unguarded `sched_queue_delay_us=86000`, `pages_demoted=8`, `refault_events=8`, `demote_degrade_state=0`, and guarded `sched_queue_delay_us=30000`, `demote_degrade_state=2`, `recovered=1`. `qemu-sched-gate` now uses `service_a_sched_gate.yaml` with a low manifest budget instead of writing `sched_boost_budget`; it still records service-A runtime sched_ext scope `1:24:0`.
- Command: `docker compose run --rm contractbpf bash -lc "make kselftest qemu-smoke qemu-sched qemu-mm-hook qemu-recovery"`
- Result: PASS
- Logs: `artifacts/logs/20260522T134136Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260522T134143Z-qemu-smoke.log`, `artifacts/logs/20260522T134151Z-qemu-sched-ext.log`, `artifacts/logs/20260522T134200Z-qemu-mm-hook.log`, `artifacts/logs/20260522T134208Z-qemu-conflict.log`
- Command: `docker compose run --rm contractbpf make qemu-mm-bpf`
- Result: PASS
- Log: `artifacts/logs/20260522T143819Z-qemu-mm-bpf.log`
- Evidence: QEMU loads `phase_paging.bpf.o`, `bad_demote.bpf.o`, and `conservative_noop_paging.bpf.o` as BPF programs, updates the BPF read-only `contract_mm_state` map, runs each program with `BPF_PROG_RUN`, registers each program/map pair with `/dev/contractbpf`, and exercises the kernel MM hook entry point. The live hook reports BPF program-derived kernel policy IDs `4`, `8`, and `12`; `phase_paging`/`bad_demote` return `demote` and allow the demotion boundary, while `conservative_noop` returns `no_op` and denies it.
- Command: `docker compose run --rm contractbpf make qemu-mm-hook`
- Result: PASS
- Logs: `artifacts/logs/20260522T140235Z-qemu-mm-hook.log`, `artifacts/logs/20260522T140242Z-qemu-mm-bpf.log`
- Evidence: the existing P0 `qemu-mm-hook` target now runs both the conservative kernel MM hook selftest and the QEMU MM-BPF load/run validation.
- Command: `docker compose run --rm contractbpf bash -lc "make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery experiments memcached-experiments"`
- Result: PASS
- Logs: `artifacts/logs/20260522T143939Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260522T143945Z-qemu-smoke.log`, `artifacts/logs/20260522T143954Z-qemu-sched-ext.log`, `artifacts/logs/20260522T144008Z-qemu-sched-gate.log`, `artifacts/logs/20260522T144019Z-qemu-mm-hook.log`, `artifacts/logs/20260522T144026Z-qemu-mm-bpf.log`, `artifacts/logs/20260522T144036Z-qemu-contractd.log`, `artifacts/logs/20260522T144050Z-qemu-conflict.log`, `artifacts/logs/20260522T144102Z-qemu-conflict.log`, `artifacts/logs/20260522T144102Z-qemu-recovery.log`, `artifacts/logs/20260522T144115Z-qemu-experiment-matrix.log`, `artifacts/logs/20260522T144144Z-qemu-memcached-matrix.log`
- Auto-archive from full P0 chain: `artifacts/repro/20260522T144213Z/`, `experiments/artifact_bundles/20260522T144213Z.tar.zst`
- Command: `docker compose run --rm contractbpf python3 experiments/runners/archive_repro.py`
- Result: PASS
- Evidence directory: `artifacts/repro/20260522T144432Z/`
- Bundle: `experiments/artifact_bundles/20260522T144432Z.tar.zst`

## Current failure / blocker
P0-P8 from `D:\Download\ContractBPF_CCF_A_Mature_Tech_and_Acceptance_Gates.md` are not all complete.

Completed/progress in this iteration:
- P7 QEMU overhead evidence now exists: `qemu-no-violation-overhead` compares memcached under sched_ext without ContractBPF gates versus sched_ext with ContractBPF gates and no violation injection. Processed results are archived in `experiments/results/processed/no_violation_overhead.csv`: latest P99 overhead `-90.44%`, throughput overhead `-130.22%`, and CPU utilization overhead `-2.93%`.
- P7 hot-path/scalability evidence now exists in QEMU: patch `0028-contractbpf-hotpath-timing-selftest.patch` adds a direct gate timing selftest and a lockless existing-token fast path; `qemu-hotpath-timing` reports scheduler gate median 100 ns and MM gate median 95 ns. Ledger stress still reports 1024 scopes and >100k events/sec without a global lock per existing-ledger event.
- P0 exact Docker command chain passes with the single `qemu-mature-gates` aggregate, including `qemu-mm-bpf`, `qemu-natural-conflict`, `qemu-natural-recovery`, `qemu-ledger-stress`, `qemu-hotpath-timing`, `qemu-policy-identity`, `qemu-scope-runtime`, `qemu-no-violation-overhead`, and `qemu-memcached-natural-bars`. Latest wrapper log: `artifacts/logs/20260522T175112Z-qemu-mature-gates-wrapper.log`. Latest archive: `artifacts/repro/20260522T180132Z/` plus `experiments/artifact_bundles/20260522T180132Z.tar.zst`.
- P0 exact Docker command chain passes after the MM-BPF kernel hook registration path was added to `qemu-mm-hook`. The latest full-chain auto-archive is `artifacts/repro/20260522T144213Z/` plus `experiments/artifact_bundles/20260522T144213Z.tar.zst`; the latest post-audit archive is `artifacts/repro/20260522T144432Z/` plus `experiments/artifact_bundles/20260522T144432Z.tar.zst`.
- P1 control path is complete for the current QEMU harness: `contractctl` supports `load`, `gate`, `unload`, `status`, `ledger`, `events`, `charge`, `degrade`, `resolve-scope`, and `reset --test-only`; `contractd` can load manifests and emit structured audit logs. Kernel patch `0007-contractbpf-device-control.patch` adds `/dev/contractbpf` ioctl token install, ledger snapshot, and reset operations; patches `0011` and `0012` add an ioctl charge path for test/evidence use; patches `0016` and `0017` add ioctl gate enable for sched/MM without rewriting manifest token budgets. QEMU evidence shows both `contractd` and `contractctl` using ioctl paths and reporting `kernel_install.gate`. The synthetic matrix, memcached matrix, conflict/recovery scenario, and sched-gate scenario now use ioctl reset/load/gate/charge/ledger plus manifest budgets instead of debugfs control writes.
- P2 is complete for the current QEMU artifact: patches `0008-contractbpf-active-policy-scope-identity.patch`, `0009-contractbpf-identity-fixups.patch`, and `0010-contractbpf-mm-identity-snapshot.patch` make sched/MM/cross hot paths use active manifest-installed policy IDs and unified cgroup/memcg service scope. `qemu-policy-identity` runs two separate sched_ext binaries under distinct policy IDs/scopes, loads two MM BPF policies with distinct kernel program IDs, verifies `effect_ledgers` policy/effect/scope attribution, and checks final kernel source paths for hard-coded `CONTRACT_*_PROG_ID 0` identity use.
- P3 is complete for the current QEMU artifact: `qemu-scope-runtime` resolves service-A and service-B cgroup/memcg IDs, then records scheduler and MM runtime activity into service-A's unified ledger while service-B remains a distinct ledger with no paging demotion. Latest log: `artifacts/logs/20260522T175657Z-qemu-natural-conflict.log`.
- P4 is complete for the current QEMU hook-entry path: `bpf/mm/phase_paging.bpf.c`, `bad_demote.bpf.c`, and `conservative_noop_paging.bpf.c` are real `SEC("syscall")` BPF programs. QEMU evidence shows they load through libbpf, receive read-only region state through `contract_mm_state`, return distinct keep/demote/reclaim_hint/no_op decisions, register with `/dev/contractbpf`, and are invoked by the kernel MM hook entry point before ContractBPF validates/allows/ignores the demotion decision.
- P5 has QEMU natural-conflict evidence: five independent runs of `memory_pressure` under HMAT-backed NUMA memory pressure produce real page demotions, refault/major-fault counters, and scheduler queue delay without controlled counter injection. Latest log: `artifacts/logs/20260522T175523Z-qemu-natural-conflict.log`.
- P6 has QEMU natural-recovery evidence: after a natural conflict, ContractBPF revokes demote (`demote_degrade_state=2`), scheduler state stays active (`sched_degrade_state=0`), later demote attempts are rejected (`revoked_demotes=55376`), and the recovery window reports `pages_demoted_delta=0`. Latest log: `artifacts/logs/20260522T175558Z-qemu-natural-conflict.log`.
- P5/P6 now also have QEMU memcached same-load quantitative proxy evidence without `contractctl charge`: `qemu-memcached-natural-bars` records G4 P99 `402778 us` (>=1.5x G1/G2), G4 refaults `28344` (G1 is 0), G4 queue delay `3852000 us`, G9 recovery-window P99 `3312 us`, G9 scheduler active/degrade state `0`, G9 demote revoke state `2`, and unaffected-tenant P99 improves from G4 `101720 us` to G9 `3469 us`. Latest log: `artifacts/logs/20260522T175731Z-qemu-memcached-natural.log`; CSV: `experiments/results/processed/memcached_natural_bars.csv`.
- P7 scalability progressed: `CONTRACT_MAX_LEDGERS=1024`, the existing-ledger update path no longer takes the global ledger lock per event, and `ledger_stress` sustains 583970 events/sec for 100000 events across 1024 scopes. Latest log: `artifacts/logs/20260522T175617Z-qemu-natural-conflict.log`.
- Recovery reproducibility hardened: `qemu/run/run-recovery.sh` and `experiments/analysis/plot_recovery.py` now tolerate serial clocksource noise appended to numeric CSV fields, and `qemu/run/run-conflict.sh` defaults to one vCPU to avoid the observed KVM CPU1 clocksource boot flake in this controlled harness.

Still incomplete:
- P5/P6 are still not final mature-gate passes because the same-load real-service quantitative bars now exist only as QEMU evidence, not bare-metal/networked-service evidence.
- P7 is complete for the current QEMU artifact: no-violation P99/throughput/CPU overhead, scheduler/MM gate median timing, and 1024-scope/100k event/sec scalability all have passing QEMU evidence. It is still not bare-metal performance evidence.
- P8 is still not final: the paper now labels current QEMU evidence as non-production, but it cannot be audited against final non-QEMU/bare-metal evidence because no bare-metal networked-service experiment exists.
- `native-p5p6-preflight` now makes the final P5/P6 environment requirement executable, and `native-p5p6-bars` is the final non-QEMU memcached G1/G2/G4/G9 runner behind that preflight. With `docker-compose.native.yml`, cgroup v2 memory and writable service scopes are now visible; the current Docker host still lacks `/dev/contractbpf` and sched_ext state.
- `docker-compose.native.yml` now defines the privileged host-attached container mode required for final non-QEMU evidence on a compatible patched Linux host; the default Docker service remains the QEMU correctness workspace.
- `remote-native-mature-gates` now provides a second final-evidence route from the existing Docker service: rsync the repo and current QEMU evidence to an SSH host, run the privileged native Docker override on that host, fetch logs/processed results/audits/bundles back, and rerun the local acceptance audit. The current run is blocked only because no `CONTRACTBPF_REMOTE` host is configured.
- `acceptance-audit` now performs the completion check required by the goal. It writes `acceptance_gate_audit.json` and `acceptance_gate_audit_latest.md`, and it returns nonzero until all P0-P8 gates have authoritative evidence.

Historical note: `ContractBPF-Ledger_NSDI27_package.zip` was not present under `/home/nya`; the current unpacked package at repository root was preserved under `research/seed_package/` instead.

M5 note: the MM hook can now run a registered BPF paging program at the demotion
effect boundary and validate/allow/ignore the returned decision. This is still
not a PageFlex-equivalent or bare-metal memory-pressure evaluation.

M6 note: cgroup v2 memory controller is enabled and visible in QEMU. Scheduler
and MM prototype effects now charge into one service-A ledger scope. The
cross-subsystem invariant has QEMU kselftest evidence. The controlled QEMU
conflict scenario now reproduces unguarded feedback-loop counters and guarded
demote-page recovery. This is still a prototype scenario, not the full
real-service evaluation matrix.

M7 note: `make experiments` now runs a controlled G1-G9 QEMU matrix, stores raw
serial logs and matrix CSVs under `experiments/results/raw/`, writes processed
tables under `experiments/results/processed/`, and generates feedback,
tail-latency, recovery, ablation, and overhead SVG figures. The matrix is still
controlled synthetic QEMU evidence, not production performance evidence.

Real-service note: `make memcached-experiments` now boots QEMU, starts two real
memcached instances in the guest, runs ASCII protocol load clients, and records
a full G1-G9 companion matrix under `experiments/results/raw/` and
`experiments/results/processed/`. This is still QEMU evidence with controlled
kernel effect injection, not production performance evidence.

## Next action
Continue final maturity work outside the current QEMU artifact: run `remote-native-mature-gates` with `CONTRACTBPF_REMOTE=user@host` on a ContractBPF-capable Linux host, or rerun `docker-native-mature-gates` on a local compatible host, then complete P8 paper/evidence integrity over the fetched native artifacts. CCF-A readiness remains blocked on bare-metal/networked-service evidence.

## Evidence checklist
- [x] Kernel builds
- [x] QEMU boots
- [x] sched_ext baseline loads
- [x] contractd starts
- [x] ledger counters update
- [x] bounded degrade triggers
- [x] paging hook works as conservative prototype
- [x] cross-subsystem rule path triggers in QEMU selftest
- [x] cross-subsystem conflict reproduced in controlled QEMU scenario
- [x] recovery curve produced for controlled QEMU scenario
- [x] G1-G9 controlled QEMU matrix produces raw logs and processed tables
- [x] Required M7 figures generated: feedback, tail latency, recovery, ablation, overhead
- [x] Real-service memcached smoke workload runs in QEMU
- [x] Full real-service memcached G1-G9 companion matrix runs in QEMU
- [x] Paper claims updated to match measured artifact evidence
- [x] Full real-service G1-G9 evaluation completed in QEMU with controlled effect injection
- [x] Fresh patch-series apply audit completed after latest changes
- [x] LaTeX builds without overfull boxes after paper update
- [x] Mature-gate requirement audit updated with current incomplete P1-P8 state
- [x] Non-debugfs contractctl charge path records service-A/service-B sched+MM counters through `/dev/contractbpf`
- [x] sched_ext runtime path records service-A task-derived scope counters after manifest token install
- [x] contractctl/contractd can enable sched/MM gates through `/dev/contractbpf` and emit `kernel_install.gate`
- [x] Main synthetic and memcached G1-G9 matrices no longer write debugfs control knobs
- [x] qemu-conflict/qemu-recovery and qemu-sched-gate no longer write debugfs control knobs
- [x] MM paging policies build as real BPF objects and load/run in QEMU with read-only state maps
- [x] Kernel MM hook entry point invokes registered MM BPF policies and validates/executes/ignores returned decisions in QEMU
- [x] Natural QEMU memory-pressure conflict reproduces for 5 runs without controlled counter injection
- [x] Natural QEMU recovery revokes demote and preserves scheduler activity
- [x] Ledger stress supports 1024 scopes and >=100k events/sec without a global lock per existing-ledger event
- [x] Scheduler/MM gate median timing bars met in QEMU hotpath selftest
- [x] P7 no-violation throughput/P99/CPU overhead bars met in QEMU no-violation memcached probe
- [x] P2 policy identity target runs two sched_ext policies, two MM BPF policies, effect-ledger attribution, and source identity grep in QEMU
- [x] P3 two-tenant runtime scope mapping joins service-A sched/MM events and keeps service-B separate in QEMU
- [x] P5/P6 same-load memcached quantitative proxy bars met in QEMU without controlled counter injection
- [x] Native P5/P6 final-evidence preflight added, run, and archived
- [x] Native P5/P6 memcached bars runner added and verified to block on failed preflight instead of fabricating native bars
- [x] Machine-readable P0-P8 acceptance audit added and run in Docker
- [x] Native host-attached Docker override and Make targets added for compatible patched Linux hosts
- [x] Remote native mature-gates executor added and verified to block when no SSH host is configured
- [ ] Native P5/P6 final-evidence preflight passes on a ContractBPF-capable non-QEMU host
- [ ] Native P5/P6 memcached bars pass on a ContractBPF-capable non-QEMU host
- [ ] Remote native mature-gates pass on a configured ContractBPF-capable Linux host
- [ ] P5/P6 real-service same-load quantitative bars met outside QEMU/bare-metal
- [ ] P8 final paper evidence integrity over non-QEMU/bare-metal artifacts
