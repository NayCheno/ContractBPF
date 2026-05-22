# 05. Related Work and Novelty Defense

## Positioning summary

ContractBPF-Ledger is not a verifier, not a sandbox, and not a safe-language replacement for eBPF. It addresses a different problem:

> verifier-accepted BPF policies that are locally legal but jointly harmful through resource effects.

## Linux eBPF verifier

The Linux verifier checks properties such as control-flow validity, bounded execution, pointer safety, stack/register state, helper arguments, and memory access safety. This is necessary but not sufficient for resource-effect safety.

Novelty claim:

```text
The verifier answers whether a program can safely execute.
ContractBPF-Ledger asks whether the policy's resource effects remain bounded at runtime.
```

## sched_ext

sched_ext enables scheduler behavior to be defined by BPF programs. This makes scheduler policy programmable enough to create new resource interactions, especially in multi-tenant and latency-sensitive settings.

Novelty claim:

```text
sched_ext provides programmability.
ContractBPF-Ledger provides runtime effect accounting and bounded degradation for that programmability.
```

## PageFlex and BPF-assisted paging

PageFlex shows that paging policies can be delegated or made programmable through eBPF-style mechanisms. This motivates the paging half of the scheduler-paging conflict.

Novelty claim:

```text
PageFlex is about flexible paging policy delegation.
ContractBPF-Ledger is about bounding the resource effects when paging policies interact with other programmable kernel policies.
```

## KRAKENGUARD

KRAKENGUARD is the closest related work because it enforces fine-grained eBPF policy constraints and reasons about cross-program interference at load time.

Critical distinction:

| Dimension | KRAKENGUARD | ContractBPF-Ledger |
|---|---|---|
| Time | load time | runtime |
| Main object | bytecode compliance | resource-effect debt |
| Mechanism | symbolic execution and policy checks | effect tokens, ledgers, bounded degrade |
| Effects covered | helper usage, memory access, return values | scheduler boost, dispatch, page demotion, refaults |
| Interference | static cross-program co-location | dynamic cross-subsystem feedback |
| Response | allow/reject loading | throttle/revoke/fallback effect |

Do not present ContractBPF-Ledger as a static checker. That would be weaker and easier to reject.

## cache_ext and page-cache customization

cache_ext-like systems customize page cache behavior with eBPF. They are important because reviewers may argue that paging-policy isolation has been studied.

Defense:

```text
ContractBPF-Ledger is not primarily page-cache isolation.
Its core example is cross-subsystem feedback between scheduling and paging.
```

## Rex and safe kernel extensions

Rex-style work reduces the gap between language-level safety and kernel-extension usability.

Defense:

```text
Safe language and verifier improvements reduce memory-safety risk.
They do not eliminate resource-effect conflicts among legal policies.
```

## cgroups, memcg, and resource quotas

Traditional resource controls bound CPU, memory, or IO usage, but they do not attribute debt to a specific BPF policy effect.

Defense:

```text
A cgroup quota can throttle service-A.
It cannot say: revoke only demote_page for service-A while preserving sched_ext dispatch and read-only observations.
```

## Summary novelty statement

Use this paragraph in the paper:

```text
Prior BPF safety systems focus on whether a BPF program can be loaded or safely executed. ContractBPF-Ledger instead focuses on the dynamic resource effects of already accepted BPF policies. Its key distinction is effect-level attribution and bounded degradation across scheduler and paging scopes.
```
