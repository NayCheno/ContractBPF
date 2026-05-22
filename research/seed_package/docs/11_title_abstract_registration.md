# 11. NSDI 2027 Fall Title and Abstract Registration Draft

## Proposed title

```text
ContractBPF-Ledger: Bounded Resource-Effect Accounting for BPF-Programmable Scheduling and Paging
```

## Track

```text
Traditional Research Track
```

## Short abstract for registration

Networked services increasingly rely on programmable kernel policies to meet workload-specific latency and efficiency goals. eBPF mechanisms such as sched_ext and BPF-assisted paging make it possible to specialize scheduling and memory decisions, but existing verifier and isolation mechanisms do not reason about the dynamic resource effects of independently loaded policies. A BPF scheduler and a BPF paging policy can both pass verification and improve their own objectives in isolation, yet their composition can create refault storms, queue-delay amplification, and tail-latency collapse.

This paper presents ContractBPF-Ledger, a resource-effect accounting system for BPF-programmable scheduling and paging. ContractBPF-Ledger grants effect tokens to policies, records scheduling and paging effects in per-scope ledgers, and enforces budgets at effect boundaries rather than at every BPF instruction. When a policy exceeds its budget or triggers a cross-subsystem feedback loop, ContractBPF-Ledger performs bounded degradation, such as throttling or revoking page demotion while preserving unrelated safe scheduler functionality.

We implement ContractBPF-Ledger on Linux using sched_ext and a PageFlex-style paging decision hook. We evaluate it on latency-sensitive networked services under memory pressure and show that it prevents verifier-accepted scheduler and paging policies from forming harmful resource-effect conflicts while preserving low steady-state overhead.

## Keywords

```text
eBPF; sched_ext; paging; resource management; multi-tenant systems; tail latency; runtime enforcement; cloud services
```

## Introduction prescreening reminder

NSDI prescreens the first section after the abstract. The Introduction must fit within three pages and must include:

1. a networked-service motivation;
2. a concrete scheduler-paging failure timeline;
3. the resource-effect safety problem;
4. why verifier/static checking/cgroups are insufficient;
5. the three mechanisms: effect tokens, per-scope ledgers, bounded degrade;
6. a preview of measured evidence.
