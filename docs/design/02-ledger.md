# Per-Scope Ledger

The ledger records resource debt for a service scope such as a cgroup, memcg, CPU set, NUMA node, or memory region.

Initial ledger fields:

```text
sched_queue_delay_us
sched_dispatch_failures
sched_boost_events
pages_demoted
refault_events
major_fault_events
fault_latency_us
violations
degrade_state[effect]
```

Counters should be per-CPU where possible and aggregated at epoch boundaries. Scheduler and paging effects for the same service must be charged into the same logical scope before cross-subsystem rules are evaluated.

