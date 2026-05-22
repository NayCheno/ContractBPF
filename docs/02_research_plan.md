# 02. Research Plan

## Target venue strategy

The primary target is **NSDI 2027 Fall**.

Rationale:

1. ATC 2026 is too close for a credible kernel-system implementation and evaluation.
2. NSDI 2027 Fall gives a full-paper deadline on **2026-09-17**.
3. The paper can fit NSDI if framed as **resource-effect safety for programmable cloud / multi-tenant networked services**, not merely as a Linux kernel extension.
4. OSDI 2027 remains the fallback if the paging hook or artifact maturity requires more engineering time.

## NSDI framing

The NSDI version should not open with "eBPF in the kernel is interesting." It should open with:

```text
Networked services increasingly rely on programmable kernel resource policies to meet tail-latency and efficiency goals. When independent BPF policies control scheduling and paging, verified policies can compose into harmful service-level feedback loops.
```

The paper's evaluative unit should be a service scope:

```text
service / cgroup / memcg / tenant / workload phase
```

Not just a kernel subsystem.

## Research questions

### RQ1: Existence of service-level resource-effect conflicts

Can two verifier-accepted BPF policies, each useful in isolation, create harmful scheduler-paging feedback for a latency-sensitive networked service?

Expected evidence:

- BPF scheduler alone improves service tail latency.
- BPF paging policy alone improves memory footprint or reclamation efficiency.
- Combined policies trigger refault amplification, queue-delay increase, or P99/P999 latency collapse.

### RQ2: Runtime attribution

Can a per-scope ledger attribute the harmful behavior to specific effects instead of blaming the whole BPF program?

Expected evidence:

- The ledger identifies `demote_page` as harmful under high refault and queue-delay debt.
- It preserves unrelated effects such as dispatch or read-only observation.
- It distinguishes same-scope conflicts from unrelated tenant activity.

### RQ3: Bounded recovery

Can effect-level degradation restore service stability faster and less destructively than whole-program fallback?

Expected evidence:

- Revoke or throttle `demote_page`.
- Preserve scheduler policy where safe.
- Show recovery timeline: refault rate down, queue delay down, P99/P999 latency recovered.

### RQ4: Overhead and deployability

Can enforcement remain low overhead by checking only at effect boundaries?

Expected evidence:

- Low steady-state overhead on real networked services.
- Low overhead for sched_ext gate and paging decision hook separately.
- Acceptable overhead under high event rates with per-CPU counters and epoch aggregation.

## Contribution structure

A strong NSDI paper should claim exactly four contributions:

1. **Problem:** service-level resource-effect conflicts among verifier-accepted BPF policies.
2. **Model:** effect tokens and per-scope ledgers for cross-subsystem resource accounting.
3. **System:** effect-boundary enforcement with bounded degradation.
4. **Evaluation:** scheduler-paging conflict prevention and recovery for latency-sensitive networked services under memory pressure.

## Technical hypothesis

The core hypothesis is:

> A small set of resource-effect invariants is enough to prevent the most damaging scheduler-paging feedback loops in networked services, without instruction-level instrumentation or full static verification of policy semantics.

Candidate invariants:

| Invariant | Informal definition |
|---|---|
| Refault amplification bound | Demoted pages must not refault above threshold R within epoch E. |
| Queue-delay inflation bound | Scheduler-induced effects must not increase service queue delay beyond Q. |
| Demotion-rate bound | A paging policy must not demote more than N pages per service scope per epoch. |
| Recovery bound | After degradation, the violated metric must fall below threshold within K epochs. |
| Minimal-degrade rule | Revoke the smallest effect that can explain the violation before disabling the entire policy. |

## Paper shape

Recommended section order:

1. Introduction
2. Background and motivation
3. Failure model
4. ContractBPF-Ledger design
5. Implementation
6. Evaluation
7. Discussion
8. Related work
9. Conclusion

NSDI prescreening reads the first section after the abstract, so the introduction must be self-contained and no longer than three pages.

## Acceptance-critical evidence

The paper needs the following figures:

1. Architecture diagram.
2. Conflict timeline: boost, demotion, refault, queue delay, P99 latency.
3. Recovery timeline comparing no guard, kill-whole-policy fallback, and effect-level degrade.
4. Overhead bar chart.
5. Ablation table: no ledger, per-subsystem ledger only, no degrade, full system.
6. Multi-tenant sanity test: unrelated tenant activity should not trigger same-scope degrade.

## Hard go/no-go gates

| Date | Gate | Decision |
|---|---|---|
| 2026-06-07 | sched_ext effect gate runs on toy workload | If not, narrow implementation immediately. |
| 2026-06-21 | queue-delay ledger and boost throttle work | If not, drop optional scheduler effects. |
| 2026-07-12 | paging decision hook exports demote/refault metrics | If not, switch to conservative decision-only hook. |
| 2026-07-26 | reproducible scheduler-paging conflict exists | If not, revisit workload and policy design. |
| 2026-08-09 | bounded degrade produces recovery timeline | If not, target OSDI 2027. |
| 2026-08-21 | first complete NSDI-style result set | If not, target OSDI 2027. |
| 2026-09-01 | full draft with all plots and related work | Internal review. |
| 2026-09-10 | title/abstract registration | Submit only if core evidence exists. |
| 2026-09-17 | full-paper submission | Submit only if no major evaluation holes remain. |

## Expected CCF-A posture

Current idea quality without implementation:

```text
7.4 / 10: promising but not submit-ready.
```

With implementation, bounded recovery, and strong NSDI framing:

```text
8.0–8.2 / 10: borderline to weak accept.
```

With weak or synthetic-only evaluation:

```text
weak reject.
```
