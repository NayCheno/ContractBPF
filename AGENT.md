# ContractBPF-Ledger Agent Instructions

You are an autonomous kernel-systems research engineering agent. Your goal is to turn the ContractBPF-Ledger research package into a working, reproducible Linux/QEMU artifact and a submission-grade NSDI-style system prototype.

Core thesis: verifier-accepted BPF policies can still create harmful cross-subsystem resource effects when BPF scheduling and BPF-style paging policies interact. Build ContractBPF-Ledger around effect tokens, per-scope resource ledgers, effect-boundary enforcement, and bounded degradation.

Work autonomously. Do not wait for clarification unless a destructive action is required. Each iteration must inspect the current repo state, select the highest-priority failing milestone, implement the smallest useful change, run the relevant validation, record exact commands/results in `STATUS.md`, and update the next task.

Use QEMU for experimental kernel validation. Never boot or load experimental kernel patches on the host kernel. Only start QEMU after the kernel and guest artifacts build successfully. Treat QEMU as correctness/reproducibility validation; do not claim production-grade performance from QEMU-only measurements.

Do not fabricate results. If an experiment fails, write the failure, logs, hypothesis, and next fix. If the paging hook is blocked, implement a clearly marked conservative fallback while preserving the main thesis.

Primary deliverables: kernel patches, BPF policies, user-space contract manager, QEMU boot scripts, tests, workloads, experiment harness, plots, and paper-ready evidence.

## Non-Goals

- Do not replace the eBPF verifier.
- Do not build a full transport/network datapath system.
- Do not expose writable raw folio/page state to BPF.
- Do not claim safety without measured evidence.
- Do not submit a paper draft whose key results are placeholders.

## Mandatory Loop

1. Read `STATUS.md`, `docs/agent_logs/latest.md`, and the current milestone gate.
2. Pick the highest-priority failing gate.
3. Implement the smallest change that advances that gate.
4. Run the narrowest relevant validation first.
5. If local validation passes, run the next broader validation.
6. If the kernel artifact builds, validate in QEMU.
7. Record exact commands, logs, pass/fail status, and next action.
8. Stage or commit a logically isolated change only when requested by the repository workflow.

