# ContractBPF-Ledger NSDI 2027 Fall Submission Package

This package consolidates the research idea, CCF-A positioning, implementation plan, evaluation plan, risk register, and paper draft for:

> **ContractBPF-Ledger: Bounded Resource-Effect Accounting for BPF-Programmable Scheduling and Paging**

## Target

- **Primary target:** NSDI 2027 Fall deadline: 24th USENIX Symposium on Networked Systems Design and Implementation.
- **Abstract/title deadline:** 2026-09-10, 11:59 pm US EDT.
- **Full-paper deadline:** 2026-09-17, 11:59 pm US EDT.
- **Conference:** 2027-05-11 to 2027-05-13, Providence, Rhode Island, USA.
- **Recommended track:** Traditional Research Track.
- **Fallback target:** OSDI 2027, if the project needs substantially more OS-kernel engineering time and the OSDI CFP/deadline becomes available.

## Why NSDI instead of ATC

ATC 2026 is too close for a fresh kernel-system implementation. NSDI 2027 Fall gives roughly three additional months for:

1. a real sched_ext effect gate,
2. a defensible PageFlex-style paging decision hook,
3. multiple latency-sensitive networked-service workloads,
4. a complete recovery timeline,
5. overhead and ablation results,
6. artifact cleanup.

The paper must be reframed for NSDI as a **cloud / multi-tenant networked-systems resource-management paper**, not merely as a kernel mechanism paper. The kernel mechanism remains the implementation substrate, but the evaluative claim should be about protecting networked services from harmful programmable resource-policy interactions.

## Package structure

```text
paper/
  contractbpf_ledger_nsdi27.tex      Main LaTeX paper draft for NSDI 2027 Fall.
  references.bib                     BibTeX references.

docs/
  01_idea.md                         Polished research idea and positioning.
  02_research_plan.md                NSDI-oriented research plan and contribution logic.
  03_implementation_plan.md          Kernel/user-space implementation plan.
  04_evaluation_plan.md              NSDI-oriented workloads, metrics, baselines, ablations.
  05_related_work.md                 Related-work map and novelty defense.
  06_risk_register.md                CCF-A / NSDI risk analysis and mitigation.
  07_review_score_and_positioning.md Strict CCF-A scoring and NSDI positioning.
  08_submission_checklist.md         NSDI 2027 Fall submission checklist.
  09_manifest_examples.md            Contract manifest examples.
  10_weekly_sprint_plan.md           NSDI 2027 Fall execution schedule.
  11_title_abstract_registration.md  Draft title and abstract for the Sep. 10 registration.
  original_uploaded_plan.md          Original uploaded plan preserved for traceability.

metadata/
  target_conference_nsdi2027.md      Conference facts and target rationale.
  conference_decision_log.md         Why NSDI was selected over ATC/OSDI/SOSP.
  source_notes.md                    External sources used while assembling the package.
```

## Docker Ubuntu workflow

The full kernel/QEMU/Rust/BPF artifact can be run in an Ubuntu 24.04 Docker
workspace:

```sh
docker compose build
docker compose run --rm contractbpf make bootstrap kernel qemu-smoke
```

Host-side Make shortcuts are also available:

```sh
make docker-build
make docker-smoke
```

See `docs/implementation/docker.md` for the full prototype-gate command and
optional KVM acceleration notes.

## Current status

This is a **paper-planning and drafting package**, not a completed artifact. The LaTeX paper is written as a serious NSDI-facing draft with placeholders for measured results. The most important missing piece is a real implementation and convincing scheduler-paging conflict experiments on networked services.

## Recommended immediate decision

Proceed toward NSDI 2027 Fall only if the team can produce by **2026-08-21**:

1. a working sched_ext effect gate,
2. a working paging decision hook or a clearly justified PageFlex-style prototype,
3. at least one reproducible conflict on a latency-sensitive networked service,
4. one bounded-degradation recovery result,
5. initial overhead numbers.

If this bar is not met, move the target to OSDI 2027 rather than submitting an under-evaluated NSDI paper.
