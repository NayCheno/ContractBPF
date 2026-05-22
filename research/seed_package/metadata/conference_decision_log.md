# Conference Decision Log

## Decision

Switch primary target from **ATC 2026** to **NSDI 2027 Fall**.

## Why not ATC 2026

ATC 2026 is too close for this project unless a substantial implementation already exists. A credible paper requires:

1. sched_ext enforcement;
2. paging decision hook;
3. cross-subsystem ledger;
4. reproducible conflict;
5. bounded recovery;
6. overhead and ablations.

Submitting without these would likely produce a weak reject.

## Why NSDI 2027 Fall

NSDI 2027 Fall gives an official September 2026 deadline and enough time for a real system prototype. The paper can fit if it is framed around networked-service resource management:

```text
programmable kernel policies -> multi-tenant service feedback loops -> tail-latency recovery
```

## Why not OSDI 2027 now

OSDI is an excellent conceptual fit, but the currently reliable public information only confirms the 2027 event dates, not the full CFP/deadline. It should be the fallback once its official CFP becomes available.

## Why not SOSP 2026

SOSP 2026 has already passed its 2026 submission deadline.

## Why not FAST 2027

FAST 2027 Fall is close in time to NSDI 2027 Fall, but the idea is broader than storage/file systems. FAST would require reframing around page-cache / memory hierarchy and storage workloads, which is weaker than the NSDI multi-tenant service framing.
