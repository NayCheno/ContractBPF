# 10. NSDI 2027 Fall Execution Plan

Current date assumed by this package: **2026-05-21**.

NSDI 2027 Fall deadlines:

```text
Title/abstract: 2026-09-10, 11:59 pm US EDT
Full paper:     2026-09-17, 11:59 pm US EDT
```

## Sprint objective

Produce enough concrete evidence to justify an NSDI submission:

```text
working prototype + at least two workloads + one convincing conflict + one recovery timeline + overhead + ablations
```

## Milestone plan

| Date | Task | Output |
|---|---|---|
| 2026-05-24 | Freeze NSDI framing | service-level problem statement, no transport |
| 2026-05-31 | Manifest parser and token table stub | user-space contract manager skeleton |
| 2026-06-07 | sched_ext boost/dispatch gate | sched effect gate runs |
| 2026-06-14 | queue-delay and boost ledger | scheduler metrics exported |
| 2026-06-21 | scheduler degradation | throttle/revoke boost works |
| 2026-06-28 | paging decision hook design | decision-only path selected |
| 2026-07-05 | demote/reclaim_hint gate | paging effect gate runs |
| 2026-07-12 | refault ledger | refault metrics exported |
| 2026-07-19 | first conflict workload | no-guard conflict reproduced on one service |
| 2026-07-26 | cross-subsystem rule | revoke demote_page from same scope |
| 2026-08-02 | recovery experiment | recovery timeline generated |
| 2026-08-09 | baselines G1-G8 | default/scheduler/paging/combined/static/per-subsystem/kill/full results |
| 2026-08-16 | second workload | Redis/RocksDB/DeathStarBench additional result |
| 2026-08-21 | NSDI readiness gate | decide submit vs OSDI fallback |
| 2026-08-28 | overhead microbenchmarks and ablations | effect gate, ledger, no ledger, no degrade |
| 2026-09-01 | complete paper draft | all core plots in paper |
| 2026-09-04 | internal review pass | intro, related work, claims fixed |
| 2026-09-07 | final result cleanup | graphs, captions, reproducibility notes |
| 2026-09-10 | title/abstract registration | submit registration |
| 2026-09-14 | final writing pass | prescreen-safe introduction |
| 2026-09-16 | formatting/anonymity | final check |
| 2026-09-17 | full-paper submission | submit only if evidence complete |

## Mandatory no-go check on 2026-08-21

Abort NSDI submission and move to OSDI 2027 if any item is missing:

- reproducible conflict;
- ContractBPF-Ledger recovery result;
- overhead measurement plan with initial numbers;
- comparison to whole-policy fallback;
- clear KRAKENGUARD/cgroup distinction;
- at least one real networked-service workload.

## Final no-go check on 2026-09-01

Do not submit if any item is still missing:

- actual implementation;
- at least two workload results or one workload plus a strong controlled study;
- measured recovery timeline;
- measured overhead;
- ablation proving cross-subsystem ledger is necessary;
- NSDI-scope introduction.

## OSDI fallback path

If NSDI 2027 Fall is not viable:

```text
Target: OSDI 2027
Condition: wait for official CFP/deadline and move the narrative back toward OS mechanism depth.
```

Use the extra time for:

1. a more robust paging hook;
2. additional kernel versions;
3. better formalization of resource-effect invariants;
4. artifact packaging;
5. reviewer-style internal reading.
