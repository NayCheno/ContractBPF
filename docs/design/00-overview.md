# ContractBPF-Ledger Overview

ContractBPF-Ledger targets resource-effect safety for verifier-accepted BPF policies. The core mechanism is:

```text
effect token + per-scope resource ledger + bounded degrade
```

## Problem

BPF programs can pass the verifier and still compose into harmful resource-effect loops. The motivating loop is:

1. A BPF `sched_ext` policy boosts a latency-sensitive service.
2. A BPF/PageFlex-style paging policy demotes pages from the same service.
3. Demotion causes refaults and major faults.
4. Faults inflate queue delay and tail latency.
5. The scheduler boosts the service even more.
6. The system enters a scheduler-paging feedback loop.

## Solution

ContractBPF-Ledger attributes each policy's dynamic resource effects to a service scope, enforces effect budgets only at effect boundaries, and degrades the harmful effect instead of the whole policy.

## Enforcement Boundary

The system must not instrument every BPF instruction. It validates proposed decisions where they become resource effects:

- scheduler boost, dispatch, CPU steering, and pinning decisions;
- paging demotion, reclaim hints, and region classification decisions;
- cross-subsystem composition rules over a shared service scope.

## Non-Goals

- Do not replace the eBPF verifier.
- Do not build a full transport/network datapath system.
- Do not expose writable raw folio/page state to BPF.
- Do not claim safety without measured evidence.
- Do not present the paper as NSDI-ready while key results are placeholders.

