# 07. Strict CCF-A Score and Positioning

## Current score

```text
Current package without implementation: 7.4 / 10
With strong prototype and NSDI-style evaluation: 8.0–8.2 / 10
Best-case polished version: borderline to weak accept
```

## Dimension-level score

| Dimension | Current | With strong results | Notes |
|---|---:|---:|---|
| Problem importance | 8.5 | 9.0 | BPF is entering scheduler and memory-policy paths. |
| Novelty | 7.0 | 8.2 | Must avoid looking like generic quota/fallback. |
| Technical depth | 7.2 | 8.4 | Needs invariant model and recovery argument. |
| Implementation | 7.0 | 8.2 | sched_ext feasible; MM path is the hard part. |
| Evaluation | 6.8 | 8.4 | Needs real conflict, recovery, ablations, overhead. |
| Related-work separation | 7.0 | 8.3 | KRAKENGUARD and paging-policy papers are the main pressure. |
| NSDI fit | 6.8 | 8.1 | Strong only if framed around networked services, cloud tenants, and service-level recovery. |

## Why NSDI 2027 Fall is plausible

NSDI accepts work on networked and distributed systems, including cloud and multi-tenant systems, resource management, reliability, debugging, and operationally relevant systems. ContractBPF-Ledger can fit if the paper is framed around protecting latency-sensitive networked services from unsafe interactions between programmable scheduling and paging policies.

## Why NSDI 2027 Fall is risky

The implementation substrate is OS-kernel machinery. If the paper reads like a kernel mechanism without a networked-service problem, NSDI reviewers may reject it as out of scope. The first three pages must establish:

```text
networked service -> programmable resource policies -> service-level feedback loop -> recovery mechanism
```

Not:

```text
eBPF kernel extension -> contract framework -> generic enforcement
```

## Recommended stance in paper

Do not say:

```text
We build a general contract framework for all BPF programs.
```

Say:

```text
We identify and bound resource-effect conflicts among verifier-accepted BPF policies that control scheduling and paging decisions for networked services.
```

Do not say:

```text
We statically check whether BPF policies conflict.
```

Say:

```text
We use static checks only to reject obvious misconfigurations; the main contribution is runtime effect accounting and bounded recovery.
```

## Strong accept conditions

The paper becomes much stronger if it includes:

1. a clean problem definition: resource-effect safety;
2. a minimal formal model: effect token, scope, ledger, budget, degrade state;
3. a working implementation;
4. at least two real networked workloads;
5. a recovery result no baseline can match;
6. clear overhead analysis;
7. an introduction that survives NSDI prescreening.

## Weak reject conditions

The paper is likely rejected if:

1. the paging hook is simulated without clear justification;
2. thresholds appear arbitrary;
3. only one synthetic conflict is shown;
4. no comparison to cgroups or kill-whole fallback exists;
5. KRAKENGUARD is treated only superficially;
6. the paper claims too broad a contract platform without delivering it;
7. the motivation is kernel-centric rather than networked-service-centric.
