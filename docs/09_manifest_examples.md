# 09. Contract Manifest Examples

## Scheduler policy manifest

```yaml
policy: latency_sched_A
subsystem: sched_ext
scope:
  type: cgroup
  id: service-A

effects:
  - name: boost_task
    budget:
      max_boosts_per_epoch: 20000
      max_queue_delay_us: 5000
    degrade:
      level1: throttle_boost
      level2: revoke_boost
      level3: disable_scheduler

  - name: dispatch_task
    budget:
      max_dispatch_failures_per_epoch: 8
      max_starvation_window_us: 20000
    degrade:
      level1: drain_dsq
      level2: revoke_dispatch_modification
      level3: disable_scheduler
```

## Paging policy manifest

```yaml
policy: phase_paging_A
subsystem: mm
scope:
  type: memcg
  id: service-A

effects:
  - name: demote_page
    budget:
      max_pages_per_epoch: 100000
      max_refault_ratio: 2.0
      max_fault_latency_us: 200
    degrade:
      level1: throttle_demote
      level2: revoke_demote
      level3: kernel_default_reclaim

  - name: reclaim_hint
    budget:
      max_hints_per_epoch: 50000
    degrade:
      level1: ignore_hint
      level2: revoke_reclaim_hint
      level3: kernel_default_reclaim
```

## Cross-subsystem composition rule

```yaml
composition:
  scope: service-A
  coupled_effects:
    - boost_task
    - demote_page
  invariant:
    refault_ratio: "<= 2.0"
    queue_delay_us: "<= 5000"
    demote_rate_pages_per_epoch: "<= 100000"
  violation:
    if:
      refault_ratio: "> 2.0"
      queue_delay_us: "> 5000"
    then:
      revoke: demote_page
      preserve:
        - dispatch_task
        - read_only_paging_observation
      recovery_window_epochs: 3
```

## Minimal static checks

```text
1. Manifest syntax is valid.
2. Effect names are known.
3. Scope resolves to concrete cgroup/memcg/region.
4. Budget values are non-negative and within system limits.
5. Fallback exists for every effect.
6. Known risky effect pairs require a runtime ledger rule.
```

## Example risky pair table

| Effect A | Effect B | Scope relation | Static action |
|---|---|---|---|
| boost_task | demote_page | same cgroup/memcg | require runtime rule |
| pin_cpu | demote_page | same NUMA node | require runtime rule |
| dispatch_task | reclaim_hint | same service | allow with budget |
| boost_task | demote_page | disjoint scopes | allow |

## Violation event format

```json
{
  "time_ns": 1844210444000,
  "scope": "service-A",
  "effects": ["boost_task", "demote_page"],
  "refault_ratio": 2.7,
  "queue_delay_us": 8120,
  "action": "revoke_demote_page",
  "recovery_window_epochs": 3
}
```

## Audit event design principle

The audit log should let the paper reconstruct the causal timeline:

```text
boost rate rises -> demote rate rises -> refault ratio rises -> queue delay rises -> degrade fires -> refault/latency recover
```
