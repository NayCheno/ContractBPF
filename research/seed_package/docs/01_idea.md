# 01. Research Idea

## Title

**ContractBPF-Ledger: Bounded Resource-Effect Accounting for BPF-Programmable Scheduling and Paging**

中文题目：**ContractBPF-Ledger：面向 BPF 可编程调度与分页的有界资源效应账本**

## Core thesis

Existing eBPF safety mechanisms mainly protect local correctness: memory safety, pointer safety, bounded control flow, helper-call validity, and limited API usage. They do not directly answer a system-level question:

> When multiple verifier-accepted BPF policies control different kernel resource paths, can their combined resource effects destabilize the system?

ContractBPF-Ledger targets this missing dimension: **resource-effect safety**.

## Concrete problem

A BPF scheduler and a BPF paging policy may both be locally valid:

```text
P_sched passes verifier.
P_page passes verifier.
Both use legal helpers and legal return values.
Each policy improves its own objective in isolation.
```

But the combination can fail:

```text
BPF scheduler boosts a latency-sensitive service.
BPF paging policy demotes pages from the same service based on stale phase signals.
The service runs more often, touches hot pages, refaults aggressively, and suffers tail latency spikes.
The scheduler sees queue delay and boosts more, reinforcing the loop.
```

This is not primarily a memory-safety failure. It is a **verified but harmful policy-composition failure**.

## Main abstraction

```text
Effect token + per-scope resource ledger + bounded degradation
```

### Effect token

A token expresses what resource effect a BPF policy may produce:

```text
Token = <subsystem, effect, scope, budget, fallback>
```

Example:

```text
<mm, demote_page, memcg=service-A, refault_budget=2.0x, fallback=revoke_demote>
<sched_ext, boost_task, cgroup=service-A, queue_delay_budget=5ms, fallback=throttle_boost>
```

The token asks a stronger question than a helper allowlist:

```text
Not: can this program call helper X?
Instead: can this policy create effect E within scope S, under budget B, with recovery action F?
```

### Per-scope resource ledger

The ledger records resource debt at a shared scope such as a cgroup, memcg, CPU set, NUMA node, or memory region:

```text
Ledger(scope) = {
  sched_queue_delay_debt,
  sched_dispatch_fail_debt,
  boost_rate,
  pages_demoted_debt,
  refault_debt,
  major_fault_rate,
  memory_pressure_score,
  cross_subsystem_violation_state
}
```

The crucial point is that scheduler effects and paging effects can be charged to the same service scope.

### Bounded degradation

When the ledger exceeds a resource-effect budget, ContractBPF-Ledger does not immediately kill the whole BPF program. It degrades the smallest harmful effect:

| Level | Action | Example |
|---:|---|---|
| 0 | normal | allow boost and demotion |
| 1 | throttle effect | reduce boost or demotion rate |
| 2 | revoke effect | revoke `demote_page` while preserving read-only observation |
| 3 | fallback subsystem | return paging to kernel default reclaim |
| 4 | disable policy | disable the sched_ext policy only as a last resort |

## Why this is a CCF-A-style problem

The idea is strong only if written as a systems problem, not as another BPF permission checker:

- It identifies a new failure mode in programmable kernel subsystems.
- It introduces a resource-effect abstraction that spans scheduler and paging decisions.
- It implements enforcement only at effect boundaries, preserving low overhead.
- It evaluates recovery rather than only prevention.
- It distinguishes policy-effect safety from memory safety and static compliance.

## Narrow scope

The paper should cover only:

```text
sched_ext + PageFlex-style paging
```

Do not include transport, generic policy synthesis, all BPF hooks, or a replacement verifier.

## One-sentence contribution

ContractBPF-Ledger is a runtime resource-effect accounting system that lets verifier-accepted BPF policies remain programmable while bounding their cross-subsystem scheduling and paging effects.
