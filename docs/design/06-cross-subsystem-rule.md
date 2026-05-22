# Cross-Subsystem Rule

The first cross-subsystem rule is an invariant, not a weighted score:

```text
if same_scope(service-A)
and refault_ratio > R
and queue_delay_us > Q
and pages_demoted_per_epoch > D:
    revoke demote_page for service-A
    preserve sched_ext dispatch_task
```

The rule should emit an audit event with the scope, effects, ledger metrics, selected degrade action, and recovery window.

## Current M6 Prototype

The current implementation adds the first kernel-side cross-subsystem rule in
`kernel/bpf/contractbpf_cross.c`:

- `contract_service_scope()` maps scheduler and MM prototype effects to the
  same service-A ledger scope.
- `contract_cross_check()` evaluates the invariant over shared ledger counters:
  refaults, scheduler queue delay, and pages demoted.
- On violation, the rule advances only `CONTRACT_EFFECT_MM_DEMOTE_PAGE` to
  `CONTRACT_DEGRADE_REVOKE`; scheduler boost/dispatch state is preserved.
- `cross_snapshot` exposes the current ledger state and audit reason.
- `cross_selftest` verifies shared-scope charging, demote-page revoke, scheduler
  preservation, and audit-event emission in QEMU kselftest.

`qemu/run/run-conflict.sh` now connects the rule to a controlled QEMU scenario:
it loads the sched_ext boost policy, runs the synthetic phase service, records
an unguarded feedback-loop snapshot, then shows the guarded version revoking
`demote_page` while preserving scheduler state. This is still a controlled
prototype scenario, not the final real-service evaluation.
