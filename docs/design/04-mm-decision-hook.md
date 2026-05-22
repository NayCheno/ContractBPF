# Conservative MM Decision Hook

The paging front-end must avoid exposing mutable folio or page state directly to BPF.

Preferred pattern:

```text
BPF receives summarized read-only page/region state.
BPF returns keep, demote, reclaim_hint, or no_op.
Kernel validates the decision, token, ledger budget, and page state.
Kernel executes or ignores the effect.
```

Initial effect boundaries:

- page demotion decision;
- reclaim hint;
- region classification;
- page-touch budget.

If the final hook is blocked, use observability-only fault/refault tracing as temporary support and label it as non-enforcement evidence.

## Current M5 Prototype

The current implementation adds a conservative kernel-validated front-end:

- `mm/vmscan.c` calls `contract_mm_demote_allowed()` before submitting folios
  to the kernel demotion path.
- `mm/workingset.c` records refault events into the ContractBPF ledger.
- `mm/memory.c` records major-fault count and coarse fault latency for enabled
  ContractBPF MM validation.
- `kernel/bpf/contractbpf_mm.c` installs demote-page and reclaim-hint tokens,
  exposes debugfs controls, and provides `mm_selftest`.

The debugfs bad-demote selftest is explicitly a prototype validation path. It
proves token/degrade behavior without claiming the final PageFlex-style BPF
program loading path is complete.
