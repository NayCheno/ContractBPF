# Kernel Patch Notes

Active ContractBPF kernel patches:

1. `0001-contractbpf-core-types-and-ledger.patch`
2. `0002-contractbpf-sched-ext-effect-gate.patch`
3. `0004-contractbpf-mm-decision-hook.patch`
4. `0005-contractbpf-cross-subsystem-ledger.patch`

M1 and M2 have passed on the pinned kernel. M3 token/ledger and M4 scheduler
gate both have QEMU evidence under `artifacts/logs/`. M5 adds a conservative
MM effect-boundary hook at the kernel demotion path plus a clearly marked
debugfs prototype selftest for bad-demote/refault/revoke behavior. It is not
yet the final PageFlex-style BPF loading path. M6 adds a shared service-A scope
for scheduler and MM effects plus a debugfs cross-subsystem invariant selftest
that revokes `demote_page` while preserving scheduler dispatch.

Planned patch order:

1. core types and ledger;
2. `sched_ext` effect gate;
3. bounded degrade controller;
4. conservative MM decision hook;
5. cross-subsystem ledger;
6. kselftests.
