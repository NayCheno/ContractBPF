# 06. Risk Register

## Overall risk

ContractBPF-Ledger is a high-upside systems idea but not a low-risk NSDI submission. The core risk is that reviewers may reduce it to:

```text
quota counters + fallback
```

The paper must prevent that reading by emphasizing:

```text
resource-effect semantics + cross-subsystem debt attribution + bounded recovery for networked services
```

## Risk table

| Risk | Severity | Why it matters | Mitigation |
|---|---:|---|---|
| Novelty collapses into quota/fallback | High | CCF-A reviewers will reject shallow enforcement papers | Frame as runtime resource-effect safety, not permission checking |
| NSDI scope challenge | High | Kernel-only work may be judged out of scope | Center evaluation on cloud / multi-tenant networked services and tail latency |
| MM hook implementation too hard | High | Paging path is invasive and time-limited | Use decision-only hook; kernel validates and executes effects |
| Conflict looks synthetic | High | One contrived workload is not enough | Show each policy is useful alone and failure arises from runtime phase changes |
| KRAKENGUARD overlap | High | Static eBPF policy work is close | Stress runtime, resource debt, and cross-subsystem feedback |
| Overhead too high | Medium | Runtime ledgers can be expensive | Effect-boundary checks, per-CPU counters, epochs, sampling |
| Degrade oscillation | Medium | Recovery without stability is weak | Hysteresis, minimum revoke window, gradual restoration |
| Attribution ambiguity | Medium | Hard to prove demotion caused refault/latency spike | Use controlled scope, temporal windows, ablations |
| September deadline still tight | Medium | Three months is useful but not generous | Strict go/no-go by 2026-08-21 |

## CCF-A reviewer objections and responses

### Objection 1: Why is this an NSDI paper?

Response:

```text
The core problem is service-level stability for networked systems under programmable resource management. The implementation is in Linux, but the measured outcome is tail latency, throughput, and recovery for multi-tenant networked services.
```

### Objection 2: Why not just use cgroups?

Response:

```text
cgroups bound resource usage at coarse granularity. ContractBPF-Ledger attributes debt to policy effects and revokes only the harmful effect. This preserves safe policy functionality.
```

### Objection 3: Why cannot the verifier handle this?

Response:

```text
The verifier checks program-level safety. The conflict depends on runtime workload phase, memory pressure, refault behavior, and scheduler queue delay. These are dynamic resource effects rather than static memory-safety properties.
```

### Objection 4: Is this only a synthetic example?

Response:

```text
The evaluation must show that both policies improve their target metric alone, and only fail when combined. It should include real latency-sensitive workloads plus controlled memory pressure.
```

### Objection 5: Why is bounded degradation better than disabling BPF?

Response:

```text
Disabling the whole policy loses all benefits. ContractBPF-Ledger revokes only the harmful effect and preserves safe effects such as dispatch or read-only policy observation.
```

### Objection 6: How do you choose thresholds?

Response:

```text
The paper should avoid arbitrary weighted scores as the main mechanism. It should use a small set of clear invariants: refault amplification bound, queue-delay inflation bound, demotion-rate bound, and recovery bound.
```

## NSDI 2027 Fall readiness check

Submit to NSDI 2027 Fall only if the following are true:

- [ ] the implementation exists;
- [ ] at least two real workloads run end-to-end;
- [ ] a conflict is reproducible;
- [ ] bounded degradation improves recovery over kill-whole fallback;
- [ ] overhead is measured;
- [ ] the paper clearly distinguishes from KRAKENGUARD, PageFlex, cache_ext, and cgroups;
- [ ] the introduction explicitly connects the contribution to networked systems and multi-tenant service management.

If any major item fails by **2026-08-21**, do not submit a weak NSDI paper. Move to OSDI 2027.
