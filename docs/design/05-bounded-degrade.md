# Bounded Degradation

ContractBPF-Ledger degrades the smallest harmful effect before disabling a full policy.

| Level | Action | Example |
|---:|---|---|
| 0 | normal | allow boost and demotion |
| 1 | throttle effect | reduce boost or demotion rate |
| 2 | revoke effect | revoke `demote_page` while preserving observation |
| 3 | fallback subsystem | return paging to kernel default reclaim |
| 4 | disable policy | disable `sched_ext` only as a last resort |

Degradation must be observable in audit logs and bounded by epochs to avoid oscillation.

