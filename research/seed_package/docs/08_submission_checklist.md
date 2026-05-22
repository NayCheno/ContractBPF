# 08. NSDI 2027 Fall Submission Checklist

## Venue-critical facts

- NSDI 2027 is the 24th USENIX Symposium on Networked Systems Design and Implementation.
- Fall title/abstract deadline: **2026-09-10, 11:59 pm US EDT**.
- Fall full-paper deadline: **2026-09-17, 11:59 pm US EDT**.
- Conference dates: **2027-05-11 to 2027-05-13**.
- Recommended track: **Traditional Research Track**.
- Reviewing is double blind.
- Submissions and final papers must be no longer than **12 pages**, including footnotes, figures, and tables; references and appendices may use additional pages.
- Submissions must be two-column, 10-point Times-Roman or similar font, 12-point leading, letter paper.
- The Introduction is prescreened and should have no more than three pages after the abstract.
- Authors must provide a generative-AI statement during submission; do not submit AI-written sections.

## Paper files in this package

- `paper/contractbpf_ledger_nsdi27.tex`
- `paper/references.bib`
- `docs/11_title_abstract_registration.md`

## Anonymity checklist

- [ ] Replace author names with paper ID.
- [ ] Remove institution-specific paths from artifact scripts.
- [ ] Avoid self-identifying repository names.
- [ ] Use anonymized project name if the system has appeared online.
- [ ] Cite own prior work in third person.
- [ ] Remove acknowledgments for submission.
- [ ] Do not include identifiable URLs in the PDF.

## Formatting checklist

- [ ] Use a USENIX-compatible two-column 10-point format.
- [ ] Enable page numbers.
- [ ] Full paper within 12 pages including figures, tables, and footnotes.
- [ ] References and appendices separated from main 12-page body.
- [ ] Introduction no more than 3 pages after the abstract.
- [ ] Figures readable in grayscale.
- [ ] No formatting rule violations.

## Content checklist

### Introduction

- [ ] Clearly state the networked-service resource-effect safety problem.
- [ ] Explain why verifier acceptance is insufficient.
- [ ] Give scheduler-paging conflict example.
- [ ] Explain why this affects multi-tenant services and tail latency.
- [ ] List contributions without overclaiming.
- [ ] Include at least one preview of real evaluation evidence.

### Design

- [ ] Define effect tokens.
- [ ] Define scope.
- [ ] Define per-scope ledger.
- [ ] Define budget/invariant.
- [ ] Define bounded degradation.
- [ ] Explain why enforcement is only at effect boundaries.

### Implementation

- [ ] Kernel version pinned.
- [ ] sched_ext integration described.
- [ ] paging hook described.
- [ ] user-space manager described.
- [ ] overhead-control mechanisms described.

### Evaluation

- [ ] At least two workloads described.
- [ ] Baselines complete.
- [ ] Conflict result shown.
- [ ] Recovery result shown.
- [ ] Overhead measured.
- [ ] Ablation shown.
- [ ] Multi-tenant false-positive sanity check shown.

### Related work

- [ ] Linux verifier.
- [ ] sched_ext.
- [ ] PageFlex / BPF paging.
- [ ] KRAKENGUARD.
- [ ] cache_ext / page-cache policy work.
- [ ] Rex / safe kernel extensions.
- [ ] cgroups/resource quotas.
- [ ] NSDI-adjacent cloud/multi-tenant resource-management work.

## Submission no-go triggers

Do not submit to NSDI 2027 Fall if any of the following are true by 2026-09-01:

- [ ] no actual system implementation;
- [ ] no real conflict result;
- [ ] no recovery timeline;
- [ ] only simulated numbers;
- [ ] no overhead result;
- [ ] no response to cgroup/KRAKENGUARD criticism;
- [ ] introduction does not clearly fit NSDI scope.

## Fallback

If no-go triggers remain by 2026-09-01, switch to:

```text
OSDI 2027, once its CFP/deadline is available.
```

This gives time for implementation, workload breadth, artifact maturity, and a more OS-centric narrative.
