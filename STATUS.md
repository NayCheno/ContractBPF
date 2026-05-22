# STATUS

## Current milestone
Submission-ready prototype gate

## Last completed action
- Command: `make kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery experiments memcached-experiments && final audit`
- Result: PASS
- Log: `artifacts/logs/20260522T035233Z-qemu-contractbpf-kselftest.log`, `artifacts/logs/20260522T035236Z-qemu-smoke.log`, `artifacts/logs/20260522T035241Z-qemu-sched-ext.log`, `artifacts/logs/20260522T035248Z-qemu-sched-gate.log`, `artifacts/logs/20260522T035255Z-qemu-mm-hook.log`, `artifacts/logs/20260522T035259Z-qemu-contractd.log`, `artifacts/logs/20260522T035308Z-qemu-conflict.log`, `artifacts/logs/20260522T035308Z-qemu-recovery.log`, `artifacts/logs/20260522T035314Z-qemu-experiment-matrix.log`, `artifacts/logs/20260522T035330Z-qemu-memcached-matrix.log`, `artifacts/logs/20260522T034939Z-patch-apply-audit.log`, `artifacts/logs/20260522T035643Z-final-audit.log`, `paper/nsdi27/contractbpf_ledger_nsdi27.log`

## Current failure / blocker
None. Historical note: `ContractBPF-Ledger_NSDI27_package.zip` was not present under `/home/nya`; the current unpacked package at repository root was preserved under `research/seed_package/` instead.

M5 note: the MM hook is a conservative kernel-validated prototype. It gates the
kernel demotion effect boundary and records refault/major-fault/fault-latency
evidence, but it is not yet the final PageFlex-style BPF program loading path.

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
None for the requested prototype gate. The artifact remains explicitly scoped
as QEMU correctness/reproducibility evidence plus a QEMU memcached companion
matrix, not production-grade performance evidence.

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
- [x] Final requirement-by-requirement completion audit completed
