# 04. Evaluation Plan

## Evaluation thesis

The evaluation must prove not only that ContractBPF-Ledger detects policy conflicts, but that it restores useful networked-service behavior with less disruption than whole-policy fallback.

For NSDI, the primary claim must be service-level:

```text
ContractBPF-Ledger protects latency-sensitive networked services from harmful interactions between independently deployed programmable scheduling and paging policies.
```

## Main workload story

**Latency-sensitive networked service under memory pressure**.

Setup:

```text
service-A: latency-sensitive networked workload
background-B: memory pressure generator / competing tenant
BPF scheduler: boosts service-A when queue delay rises
BPF paging policy: demotes pages from service-A based on stale phase/coldness signal
```

Expected behavior:

```text
BPF scheduler alone improves latency.
BPF paging policy alone reduces footprint or improves reclaim.
Combined policies create refault storm and P99/P999 latency spike.
ContractBPF-Ledger detects cross-subsystem debt and revokes demote_page.
```

## Experimental groups

| Group | Configuration | Purpose |
|---|---|---|
| G1 | Linux default scheduler + default paging | baseline |
| G2 | sched_ext policy only | scheduler benefit |
| G3 | BPF paging policy only | paging benefit |
| G4 | sched_ext + BPF paging, no ledger | demonstrate conflict |
| G5 | static checker only | show static checks insufficient |
| G6 | per-subsystem ledger only | show cross-subsystem ledger necessity |
| G7 | kill-whole-policy fallback | compare degradation granularity |
| G8 | ContractBPF-Ledger full system | main result |

## Metrics

| Metric | Why it matters |
|---|---|
| P50/P99/P999 latency | tail-latency protection |
| throughput | no severe service degradation |
| request timeout rate | service-level failure signal |
| major fault rate | paging conflict signal |
| refault ratio | hot-page demotion evidence |
| scheduler queue delay | scheduler-side pressure |
| pages demoted per epoch | effect boundedness |
| boost events per epoch | scheduler effect accounting |
| fallback activation latency | enforcement responsiveness |
| recovery time | bounded recovery |
| steady-state overhead | systems practicality |
| policy throughput | effect-gate capacity |

## Required plots

### Figure 1: Harmful feedback timeline

Time-series plot with:

```text
time on x-axis
lines: demote rate, refault ratio, queue delay, P99 latency, degradation state
```

Expected interpretation:

```text
Without ContractBPF-Ledger, refault and queue-delay debt grow together.
With ContractBPF-Ledger, demote_page is revoked and latency recovers.
```

### Figure 2: Tail latency comparison

Bar chart:

```text
G1 default
G2 scheduler only
G3 paging only
G4 combined without guard
G7 kill-whole fallback
G8 ContractBPF-Ledger
```

Use P99 and P999.

### Figure 3: Recovery time

CDF or bar chart for time to return below latency/refault threshold.

### Figure 4: Overhead

Break down:

```text
sched_ext effect gate overhead
paging effect gate overhead
ledger update overhead
degrade-controller overhead
```

### Figure 5: Ablation

| Variant | Expected result |
|---|---|
| no ledger | misses dynamic conflict |
| per-subsystem ledger only | detects local pressure but misses causal coupling |
| no bounded degrade | detects but does not recover |
| no hysteresis | oscillates |
| full system | stable recovery |

### Figure 6: Multi-tenant isolation sanity check

Show that unrelated memory pressure from tenant B does not revoke effects for tenant A unless the same service scope accumulates debt.

## Workloads

Minimum NSDI-viable set:

1. Tail-latency service: memcached or Redis.
2. Memory-sensitive service: RocksDB read-heavy.
3. Controlled phase-changing workload to validate hot/cold transitions.
4. Memory pressure: stress-ng, controlled mmap/touch workload, or background cache churn.
5. Scheduler stress: mixed CPU-bound and IO-bound cgroups.

Better set for final paper:

| Workload | Purpose |
|---|---|
| memcached/Redis | low-latency service |
| RocksDB | memory-sensitive storage service |
| DeathStarBench microservice | networked microservice credibility |
| synthetic phase-changing workload | controlled hot/cold phase changes |
| background memory churn | pressure generation |
| CPU hog cgroup | scheduler stress |

## Baselines to implement

### Native baselines

- default Linux scheduler and paging;
- sched_ext policy without ContractBPF-Ledger;
- paging policy without ContractBPF-Ledger.

### Control baselines

- static contract checker only;
- cgroup CPU quota / memory limit style protection;
- kill-whole-BPF-policy fallback;
- per-subsystem ledger only.

## Reviewer-proofing questions

| Reviewer question | Evidence needed |
|---|---|
| Why is this NSDI rather than only OS? | Show networked-service tail latency, multi-tenant pressure, and operational resource-management use case. |
| Why not cgroups? | Show cgroups throttle resources, but cannot revoke only `demote_page` while preserving scheduler dispatch. |
| Is the conflict synthetic? | Show each policy is beneficial alone and conflict arises from realistic stale phase/memory-pressure behavior. |
| Why not static checking? | Show dynamic refault/queue-delay coupling depends on runtime workload phase. |
| Does ledger cause overhead? | Provide effect-gate microbenchmark and full workload overhead. |
| Does degrade oscillate? | Show hysteresis and recovery state timeline. |

## Minimum NSDI-ready evidence

For NSDI 2027 Fall, the package is credible only if the paper includes:

1. at least two real networked workloads;
2. one real sched_ext policy;
3. one real or defensible paging decision hook;
4. a combined conflict result;
5. a recovery result;
6. overhead below an acceptable threshold;
7. a cgroup/memcg baseline comparison;
8. an ablation proving that cross-subsystem ledgering is necessary.

Without these, defer to OSDI 2027 rather than submitting a weak NSDI paper.
