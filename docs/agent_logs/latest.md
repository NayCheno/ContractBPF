# Agent Log

Date: 2026-05-21

## Context inspected

- Read `docs/plan/ContractBPF_Agent_Prompt_and_Repo.md`.
- Read implementation, manifest, and submission checklist notes under `docs/`.
- Checked current worktree: the repository contained the planning package only, with no engineering skeleton.
- Searched for `ContractBPF-Ledger_NSDI27_package.zip` under `/home/nya`; no matching zip was present.

## Decisions

- Preserve the existing unpacked planning package as the seed package under `research/seed_package/`.
- Pin the initial kernel to Linux 6.12.30 because Linux 6.12 contains upstream `sched_ext`, and the kernel documentation for v6.12 documents `CONFIG_SCHED_CLASS_EXT` and `tools/sched_ext`.
- Kept ContractBPF kernel patches inactive until M1 passed, per the blueprint.
- Built `tools/sched_ext/scx_simple` for M2 and validated it inside QEMU, not on the host kernel.

## Commands and results

- `git status --short`
  - Result: PASS; repository had only untracked seed files before bootstrapping.
- `find /home/nya -maxdepth 5 -iname 'ContractBPF-Ledger_NSDI27_package.zip' -o -iname '*ContractBPF*package*.zip'`
  - Result: PASS; no package zip found.
- `mkdir -p ...`
  - Result: PASS; repository skeleton directories created.
- `cp -a README.md docs metadata paper research/seed_package/`
  - Result: PASS; unpacked package preserved.
- `cp -a paper/contractbpf_ledger_nsdi27.tex paper/references.bib paper/nsdi27/`
  - Result: PASS; LaTeX draft copied to the paper workspace.
- `bash -n kernel/scripts/*.sh kernel/selftests/contractbpf/*.sh userspace/scripts/*.sh qemu/rootfs/*.sh qemu/run/*.sh workloads/memcached/*.sh workloads/redis/*.sh workloads/memory_pressure/*.sh workloads/cpu_interferer/*.sh`
  - Result: PASS.
- `make bpf`
  - Result: PASS; scaffold binary builds under ignored `build/bpf/`.
- `cargo build --manifest-path userspace/contractd/Cargo.toml && cargo build --manifest-path userspace/contractctl/Cargo.toml && cargo build --manifest-path userspace/libcontract/Cargo.toml`
  - Result: PASS.
- `./qemu/rootfs/build-rootfs.sh`
  - Result: PASS; produced ignored `qemu/images/initramfs.cpio.gz`.
- `./kernel/scripts/fetch-linux.sh`
  - Result: PASS; fetched `https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.30.tar.xz` into ignored `build/linux/`.
- `./kernel/scripts/configure-kernel.sh`
  - First result: FAIL; `CONFIG_DEBUG_INFO_BTF` and `CONFIG_SCHED_CLASS_EXT` were missing because the debug-info choice still selected `CONFIG_DEBUG_INFO_NONE=y`.
  - Fix: select `CONFIG_DEBUG_INFO_DWARF5=y` before enabling BTF and sched_ext.
  - Second result: PASS.
- `grep -E 'CONFIG_(BPF|BPF_SYSCALL|BPF_JIT|BPF_JIT_ALWAYS_ON|BPF_JIT_DEFAULT_ON|DEBUG_INFO_BTF|SCHED_CLASS_EXT)=' build/linux/.config`
  - Result: PASS; all required symbols were `=y`.
- `./kernel/scripts/build-kernel.sh`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T175822Z-kernel-build.log`.
  - Kernel image: `build/linux/arch/x86/boot/bzImage`.
- `./qemu/run/run-smoke.sh`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T180152Z-qemu-smoke.log`.
  - Marker: `CONTRACTBPF_BOOT_OK`.
- `make -C build/linux/tools/sched_ext O=/home/nya/workspace/ContractBPF/build/scx LLVM=1 scx_simple`
  - Result: PASS; produced ignored `build/scx/build/bin/scx_simple`.
- `./qemu/rootfs/build-sched-rootfs.sh`
  - Result: PASS; produced ignored `qemu/images/sched-ext-initramfs.cpio.gz`.
- `./qemu/run/run-sched-ext.sh`
  - First result: FAIL; `/dev/null` was missing in the sched_ext initramfs, so the background `scx_simple` launch failed.
  - Fix: mount `devtmpfs` in `qemu/rootfs/sched-init.sh`.
  - Second result: PASS.
  - Log: `artifacts/logs/20260521T180533Z-qemu-sched-ext.log`.
  - Evidence: `SCHED_EXT_STATE_POLL=enabled`, `CONTRACTBPF_SCHED_EXT_OK`, `SCHED_EXT_STATE_AFTER_STOP=disabled`, `CONTRACTBPF_SCHED_EXT_UNLOAD_OK`.
- `./kernel/scripts/build-kernel.sh`
  - Result: PASS after adding M3 `CONFIG_CONTRACTBPF=y` core files.
  - Log: `artifacts/logs/20260521T181219Z-kernel-build.log`.
- `./kernel/scripts/build-selftests.sh`
  - Result: PASS; `tools/testing/selftests/contractbpf` had no compile step and installed shell test metadata cleanly.
- `./qemu/rootfs/build-contractbpf-selftest-rootfs.sh`
  - Result: PASS; produced ignored `qemu/images/contractbpf-selftest-initramfs.cpio.gz`.
- `./qemu/run/run-kselftest.sh`
  - Result: PASS after fixing debugfs read position handling.
  - Log: `artifacts/logs/20260521T181304Z-qemu-contractbpf-kselftest.log`.
  - Evidence: `PASS token_lookup ledger_charge degrade_transition`, `CONTRACTBPF_LEDGER_OK`, `CONTRACTBPF_DEGRADE_OK`.
- `./qemu/run/run-sched-ext.sh`
  - Result: PASS regression after M3 patch.
  - Log: `artifacts/logs/20260521T181437Z-qemu-sched-ext.log`.
- `patch --dry-run -d <clean-linux-6.12.30> -p1 < kernel/patches/0001-contractbpf-core-types-and-ledger.patch`
  - Result: PASS; the M3 patch applies cleanly to a fresh Linux 6.12.30 tree.
- `make kselftest && make qemu-sched`
  - Result: PASS.
  - Logs: `artifacts/logs/20260521T181631Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260521T181635Z-qemu-sched-ext.log`.
- `./kernel/scripts/build-kernel.sh`
  - Result: PASS after M4 sched_ext effect gate changes.
  - Log: `artifacts/logs/20260521T183018Z-kernel-build.log`.
- `make qemu-sched-gate`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T183111Z-qemu-sched-gate.log`.
  - Evidence: `scx_contract_boost` loaded in QEMU, `sched_dispatch_events=82`, `sched_boost_events=2`, `sched_queue_delay_us=9000`, `violations=80`, `boost_degrade_state=4`, `CONTRACTBPF_SCHED_GATE_OK`, `CONTRACTBPF_DEGRADE_OK`, and `CONTRACTBPF_SCHED_EXT_UNLOAD_OK`.
- `patch --dry-run -d <clean-linux-6.12.30+0001> -p1 < kernel/patches/0002-contractbpf-sched-ext-effect-gate.patch`
  - Result: PASS; the M4 patch applies cleanly after `0001`.

## Next action

Implement M6 unified service scope and cross-subsystem rule. First enable and
validate the required cgroup/memcg scope support and get `contractd` starting in
QEMU, then charge scheduler and paging effects into one service-A ledger.

## 2026-05-21 M5 update

- Added `kernel/patches/0004-contractbpf-mm-decision-hook.patch` and listed it
  in `kernel/patches/series`.
- Added `kernel/bpf/contractbpf_mm.c` in the patch series with demote-page and
  reclaim-hint tokens, debugfs controls, `mm_snapshot`, and `mm_selftest`.
- Added a conservative MM effect-boundary hook in `mm/vmscan.c` through
  `contract_mm_demote_allowed()`.
- Added refault and major-fault/fault-latency ledger accounting in
  `mm/workingset.c` and `mm/memory.c`.
- Added `qemu/rootfs/mm-hook-init.sh`,
  `qemu/rootfs/build-mm-hook-rootfs.sh`, `qemu/run/run-mm-hook.sh`, and the
  top-level `make qemu-mm-hook` target.
- Updated BPF paging stubs to document bad-demote, phase-aware, and conservative
  no-op decision shapes. These are model sources for the later BPF loading path,
  not host-loaded BPF programs.

Validation:

- `make -C build/linux -j$(nproc) kernel/bpf/contractbpf_mm.o mm/vmscan.o mm/workingset.o mm/memory.o`
  - Result: PASS.
- `./kernel/scripts/build-kernel.sh`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T184908Z-kernel-build.log`.
- `make kselftest`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T185004Z-qemu-contractbpf-kselftest.log`.
  - Evidence: `PASS token_lookup ledger_charge degrade_transition` and
    `PASS mm_demote_refault revoke_demote preserve_reclaim_hint prototype_path`.
- `make qemu-mm-hook`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T185012Z-qemu-mm-hook.log`.
  - Evidence: `CONTRACTBPF_MM_HOOK_OK`, `pages_demoted=3`,
    `reclaim_hints=8`, `refault_events=3`, `major_fault_events=3`,
    `fault_latency_us=750`, `revoked_demotes=4`,
    `demote_degrade_state=4`.
- `make qemu-sched-gate`
  - Result: PASS regression.
  - Log: `artifacts/logs/20260521T185023Z-qemu-sched-gate.log`.
- Fresh patch-series check from `linux-6.12.30.tar.xz`
  - Result: PASS for `0001`, `0002`, and `0004`.

## 2026-05-21 contractd QEMU update

- Replaced the placeholder `contractd` main with a minimal debugfs-aware daemon
  check. It discovers `/sys/kernel/debug/contractbpf`, prints service-A token
  intent for scheduler boost, MM demote, and reclaim hint effects, and exits
  only after printing `CONTRACTBPF_CONTRACTD_OK`.
- Added `qemu/rootfs/contractd-init.sh`,
  `qemu/rootfs/build-contractd-rootfs.sh`, and a real
  `qemu/run/run-contractd.sh`.
- Added the top-level `make qemu-contractd` target.

Validation:

- `make qemu-contractd`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T185517Z-qemu-contractd.log`.
  - Evidence: `CONTRACTBPF_BOOT_OK`, `contractd: debugfs=/sys/kernel/debug/contractbpf`,
    token lines for `latency_sched_A` and `phase_paging_A`, and
    `CONTRACTBPF_CONTRACTD_OK`.

## 2026-05-21 M6 scope and cross-rule update

- Enabled `CONFIG_MEMCG=y` in `kernel/scripts/configure-kernel.sh` and the
  checked-in QEMU config fragments.
- Updated the contractd guest path to mount cgroup v2 and require the `memory`
  controller in `/sys/fs/cgroup/cgroup.controllers`.
- Added `kernel/patches/0005-contractbpf-cross-subsystem-ledger.patch` and
  listed it in `kernel/patches/series`.
- Added `kernel/bpf/contractbpf_cross.c` with the initial invariant:
  refaults + queue delay + demotion implies `demote_page` revoke while
  preserving scheduler dispatch.
- Changed the scheduler and MM prototype front-ends to use the same service-A
  ledger scope via `contract_service_scope()`.
- Extended ContractBPF kselftest to read `cross_selftest`.

Validation:

- `./kernel/scripts/configure-kernel.sh`
  - Result: PASS.
  - Evidence: `CONFIG_MEMCG=y`, `CONFIG_CGROUPS=y`, and
    `CONFIG_CGROUP_BPF=y` in `build/linux/.config`.
- `./kernel/scripts/build-kernel.sh`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T190354Z-kernel-build.log`.
- `make kselftest`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T190451Z-qemu-contractbpf-kselftest.log`.
  - Evidence: `PASS cross_scope_shared revoke_demote preserve_sched_dispatch audit_event`.
- `make qemu-mm-hook`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T190504Z-qemu-mm-hook.log`.
- `make qemu-sched-gate`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T190508Z-qemu-sched-gate.log`.
- `make qemu-contractd`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T190516Z-qemu-contractd.log`.
  - Evidence: `contractd: cgroup.controllers=cpuset cpu io memory hugetlb pids rdma misc`
    and `CONTRACTBPF_CONTRACTD_OK`.
- Patch apply check
  - Result: PASS for `0005-contractbpf-cross-subsystem-ledger.patch` after
    `0001`, `0002`, and `0004`.

## 2026-05-21 M6 conflict and recovery update

- Extended `contractbpf_cross.c` with a debugfs `cross_scenario` control for
  deterministic `unguarded`, `guarded`, and `reset` scenarios. The unguarded
  scenario records harmful queue-delay/refault/demotion counters without
  degradation. The guarded scenario applies the cross rule and revokes only
  `demote_page`.
- Replaced the synthetic phase service placeholder with a small CPU/memory
  phase-changing workload.
- Added `qemu/rootfs/conflict-init.sh`,
  `qemu/rootfs/build-conflict-rootfs.sh`, and a real
  `qemu/run/run-conflict.sh`.
- Implemented `qemu/run/run-recovery.sh` to rerun the controlled QEMU conflict,
  parse serial snapshots into CSV, and generate a recovery SVG through
  `experiments/analysis/plot_recovery.py`.
- Updated `Makefile` targets `qemu-conflict` and `qemu-recovery`.

Validation:

- `./kernel/scripts/build-kernel.sh`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T191233Z-kernel-build.log`.
- `make qemu-conflict`
  - Result: PASS.
  - Log: `artifacts/logs/20260521T191323Z-qemu-conflict.log`.
  - Evidence: `SYNTHETIC_PHASE_SERVICE_OK`,
    `CONTRACTBPF_CONFLICT_REPRODUCED`, `CONTRACTBPF_RECOVERY_OK`,
    and `CONTRACTBPF_SCHED_EXT_UNLOAD_OK`.
- `make qemu-recovery`
  - Result: PASS after replacing a brittle grep check with CSV parsing.
  - Logs: `artifacts/logs/20260521T191616Z-qemu-conflict.log`,
    `artifacts/logs/20260521T191616Z-qemu-recovery.log`.
  - Evidence: `CONTRACTBPF_RECOVERY_CURVE_OK`.
  - CSV: `artifacts/traces/20260521T191616Z-recovery.csv`.
  - Figure: `experiments/results/figures/recovery.svg`.

## 2026-05-22 M7 experiment harness update

- Added a QEMU experiment matrix path:
  `qemu/rootfs/matrix-init.sh`,
  `qemu/rootfs/build-experiment-matrix-rootfs.sh`, and
  `qemu/run/run-experiment-matrix.sh`.
- Wired `make qemu-experiment-matrix` and `make experiments`.
- Expanded all `experiments/configs/g*.yaml` with `control_mode`, `workload`,
  and evidence-scope metadata.
- Replaced the M7 runner placeholders with parsers that produce:
  `experiments/results/raw/matrix_latest.csv`,
  `experiments/results/processed/matrix_summary.csv`,
  `tail_latency_table.csv`, `feedback_timeline.csv`, `ablation_table.csv`,
  `overhead_table.csv`, and `recovery_table.csv`.
- Implemented the required figure scripts for feedback timeline, tail latency,
  recovery, ablation, and overhead.
- Added latency samples to `workloads/synthetic_phase_service`, then fixed an
  unsigned timestamp subtraction bug that initially produced a bogus 2^64-scale
  latency value.
- Replaced memcached workload placeholders with a real server script, a Python
  host load generator, a C guest load client, and a QEMU memcached smoke path:
  `qemu/rootfs/memcached-init.sh`,
  `qemu/rootfs/build-memcached-rootfs.sh`, and `qemu/run/run-memcached.sh`.
  The rootfs builder downloads and extracts memcached runtime packages under
  ignored `build/` state when a host `memcached` binary is unavailable; it does
  not install packages onto the host.
- Fixed two memcached smoke issues found during validation:
  missing `/etc/passwd` for `-u root`, and an ASCII protocol value-length
  mismatch that caused the guest load client to wait until QEMU timeout.

Validation:

- `bash -n qemu/rootfs/build-experiment-matrix-rootfs.sh qemu/run/run-experiment-matrix.sh workloads/memcached/run-server.sh workloads/memcached/run-load.sh`
  - Result: PASS.
- `sh -n qemu/rootfs/matrix-init.sh`
  - Result: PASS.
- `python3 -m py_compile workloads/memcached/load_ascii.py experiments/runners/matrixlib.py experiments/runners/run_matrix.py experiments/runners/run_group.py experiments/analysis/plot_feedback_timeline.py experiments/analysis/plot_tail_latency.py experiments/analysis/plot_recovery.py experiments/analysis/plot_ablation.py experiments/analysis/plot_overhead.py`
  - Result: PASS.
- `make qemu-experiment-matrix`
  - Result: PASS.
  - Log: `artifacts/logs/20260522T032745Z-qemu-experiment-matrix.log`.
- `make experiments`
  - Result: PASS.
  - Log: `artifacts/logs/20260522T032809Z-qemu-experiment-matrix.log`.
  - Evidence: `CONTRACTBPF_EXPERIMENT_MATRIX_OK`,
    `CONTRACTBPF_EXPERIMENTS_OK`, all G1-G9 group markers, raw matrix CSV,
    processed summary CSV, and five SVG figures.
- `python3 experiments/runners/run_group.py experiments/configs/g9_full_contractbpf.yaml --log artifacts/logs/20260522T032809Z-qemu-experiment-matrix.log`
  - Result: PASS.
- `python3 experiments/analysis/parse_latency.py`,
  `python3 experiments/analysis/parse_faults.py`,
  `python3 experiments/analysis/parse_sched.py`, and
  `python3 experiments/runners/summarize.py`
  - Result: PASS.
- `make qemu-memcached`
  - Result: PASS.
  - Log: `artifacts/logs/20260522T033643Z-qemu-memcached.log`.
  - Evidence: `MEMCACHED_LOAD_OK` and `CONTRACTBPF_MEMCACHED_OK`.
- `python3 experiments/runners/collect_guest_logs.py --pattern '*-qemu-memcached.log'`
  - Result: PASS; copied memcached guest logs into
    `experiments/results/raw/`.
- `python3 experiments/analysis/parse_memcached.py`
  - Result: PASS.
  - Output: `experiments/results/processed/memcached_smoke.csv`.

Next action:

Audit and update the NSDI draft so all implementation and evaluation claims
match the current evidence. Keep QEMU-only and memcached-smoke limitations
explicit.

## 2026-05-22 M8 paper integration update

- Updated `paper/nsdi27/contractbpf_ledger_nsdi27.tex` from planned evaluation
  language to current artifact evidence.
- Added Linux 6.12.30 and 2,294-line patch-series implementation details.
- Corrected the baseline table to G1-G9.
- Added controlled QEMU matrix results from
  `experiments/results/processed/matrix_summary.csv`.
- Added the memcached QEMU smoke result from
  `experiments/results/processed/memcached_smoke.csv`.
- Added explicit limitations: QEMU is correctness/reproducibility evidence, the
  paging path is still a conservative prototype, and memcached is a smoke test
  rather than a full real-service G1-G9 evaluation.
- Tightened the sched_ext implementation wording so it matches the current
  dispatch/boost gate instead of claiming every targeted boundary is already
  implemented.

Validation:

- `pdflatex -interaction=nonstopmode -halt-on-error contractbpf_ledger_nsdi27.tex`
  - Result: PASS.
- `bibtex contractbpf_ledger_nsdi27`
  - Result: PASS with two existing bibliography metadata warnings.
- Second and third `pdflatex -interaction=nonstopmode -halt-on-error contractbpf_ledger_nsdi27.tex`
  - Result: PASS.
  - Output: `paper/nsdi27/contractbpf_ledger_nsdi27.pdf`.
  - Remaining issue: LaTeX reports overfull/underfull boxes from long paths,
    equations, and bibliography URLs. These are formatting polish issues, not
    build failures.

Next action:

Expand the memcached path from smoke validation into a full real-service matrix
or a dedicated non-QEMU performance run, then update the paper with that
evidence.

## 2026-05-22 memcached matrix update

- Added a full QEMU memcached companion matrix:
  `qemu/rootfs/memcached-matrix-init.sh`,
  `qemu/rootfs/build-memcached-matrix-rootfs.sh`, and
  `qemu/run/run-memcached-matrix.sh`.
- Added `make qemu-memcached-matrix` and `make memcached-experiments`.
- Added `experiments/runners/run_memcached_matrix.py`, which parses the
  memcached G1-G9 serial log into:
  `experiments/results/raw/memcached_matrix_latest.csv`,
  `experiments/results/processed/memcached_matrix_summary.csv`,
  `memcached_tail_latency_table.csv`, and `memcached_feedback_table.csv`.
- Corrected the synthetic and memcached matrix baseline semantics: G2, G4, and
  G8 now load sched_ext without enabling the ContractBPF scheduler gate; G7 and
  G9 enable the gate because they represent ledger/ContractBPF variants.
- Updated `paper/nsdi27/contractbpf_ledger_nsdi27.tex` to replace the
  memcached smoke-test language with a real-service G1-G9 companion matrix,
  while keeping the QEMU/controlled-effect limitation explicit.

Validation:

- `sh -n qemu/rootfs/matrix-init.sh qemu/rootfs/memcached-matrix-init.sh`
  - Result: PASS.
- `bash -n qemu/rootfs/build-memcached-matrix-rootfs.sh qemu/run/run-memcached-matrix.sh qemu/rootfs/build-experiment-matrix-rootfs.sh qemu/run/run-experiment-matrix.sh`
  - Result: PASS.
- `python3 -m py_compile experiments/runners/run_memcached_matrix.py experiments/runners/matrixlib.py`
  - Result: PASS.
- `make experiments`
  - Result: PASS.
  - Log: `artifacts/logs/20260522T034643Z-qemu-experiment-matrix.log`.
  - Evidence: all G1-G9 markers and `CONTRACTBPF_EXPERIMENT_MATRIX_OK`.
- `make memcached-experiments`
  - Result: PASS.
  - Log: `artifacts/logs/20260522T034702Z-qemu-memcached-matrix.log`.
  - Evidence: all G1-G9 markers and `CONTRACTBPF_MEMCACHED_MATRIX_OK`.
  - Output: `experiments/results/processed/memcached_matrix_summary.csv`.
- `pdflatex -interaction=nonstopmode -halt-on-error contractbpf_ledger_nsdi27.tex`
  - Result: PASS.
  - Output: `paper/nsdi27/contractbpf_ledger_nsdi27.pdf`.

Next action:

Run a fresh patch-series apply audit from a clean Linux 6.12.30 tree and polish
the remaining LaTeX overfull warnings before treating the artifact as
submission-ready.

## 2026-05-22 patch and paper polish update

- Ran a fresh patch-series apply audit from `linux-6.12.30.tar.xz` into
  `build/patch-audit/linux-6.12.30`.
- Confirmed every patch listed in `kernel/patches/series` applies cleanly:
  `0001`, `0002`, `0004`, and `0005`.
- Updated the historical `0003` and `0006` placeholder files to state that
  bounded-degrade and kselftest work was consolidated into the actual series
  patches rather than remaining as unapplied work.
- Polished the NSDI draft to remove LaTeX overfull boxes introduced by the
  memcached matrix table and long artifact paths.

Validation:

- Fresh patch audit command:
  `tar -xf build/downloads/linux-6.12.30.tar.xz ... && patch --dry-run/apply ...`
  - Result: PASS.
  - Log: `artifacts/logs/20260522T034939Z-patch-apply-audit.log`.
  - Evidence: `PATCH_AUDIT_OK`.
- `bibtex contractbpf_ledger_nsdi27 && pdflatex -interaction=nonstopmode -halt-on-error contractbpf_ledger_nsdi27.tex && pdflatex -interaction=nonstopmode -halt-on-error contractbpf_ledger_nsdi27.tex`
  - Result: PASS.
- `pdflatex -interaction=nonstopmode -halt-on-error contractbpf_ledger_nsdi27.tex`
  - Result: PASS after final listing polish.
- `rg -n "Overfull|LaTeX Warning: Citation|undefined references" paper/nsdi27/contractbpf_ledger_nsdi27.log`
  - Result: PASS; no matches.

Next action:

Perform the final requirement-by-requirement audit against
`docs/plan/ContractBPF_Agent_Prompt_and_Repo.md`, current logs, generated
tables, QEMU markers, and paper text before deciding whether the active goal can
be marked complete.

## 2026-05-22 final audit update

- Ran the full fresh validation chain:
  `make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery experiments memcached-experiments`.
- Verified M0-M8 evidence against current files, kernel config, QEMU markers,
  processed tables, generated figures, patch apply logs, and paper build logs.
- Confirmed the final artifact is scoped as a QEMU correctness/reproducibility
  prototype with a QEMU memcached companion matrix, not as production-grade
  performance evidence.

Validation evidence:

- Kernel build: `artifacts/logs/20260522T035229Z-kernel-build.log`.
- kselftest: `artifacts/logs/20260522T035233Z-qemu-contractbpf-kselftest.log`.
- QEMU smoke: `artifacts/logs/20260522T035236Z-qemu-smoke.log`.
- sched_ext baseline: `artifacts/logs/20260522T035241Z-qemu-sched-ext.log`.
- sched gate: `artifacts/logs/20260522T035248Z-qemu-sched-gate.log`.
- MM hook: `artifacts/logs/20260522T035255Z-qemu-mm-hook.log`.
- contractd: `artifacts/logs/20260522T035259Z-qemu-contractd.log`.
- conflict/recovery: `artifacts/logs/20260522T035308Z-qemu-conflict.log` and
  `artifacts/logs/20260522T035308Z-qemu-recovery.log`.
- synthetic matrix: `artifacts/logs/20260522T035314Z-qemu-experiment-matrix.log`.
- memcached matrix: `artifacts/logs/20260522T035330Z-qemu-memcached-matrix.log`.
- patch apply audit: `artifacts/logs/20260522T034939Z-patch-apply-audit.log`.
- paper build: `paper/nsdi27/contractbpf_ledger_nsdi27.log`.
- Final audit script result: `FINAL_AUDIT_CORE_OK`.

Conclusion:

The requested prototype artifact and plan gates are complete under the
documented QEMU evidence scope. Future work for an actual submission would be a
non-QEMU performance campaign on dedicated hardware, but that is outside the
current validated prototype gate and is explicitly not claimed in the paper.
