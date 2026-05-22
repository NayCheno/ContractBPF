# Target Conference: NSDI 2027 Fall

## Selected target

**NSDI 2027 Fall deadline: 24th USENIX Symposium on Networked Systems Design and Implementation.**

Reason:

- NSDI is listed as **A** in the 2026 CCF recommended conference directory under computer networks.
- NSDI 2027 has an official Fall deadline: title/abstract on **2026-09-10**, full paper on **2026-09-17**.
- The venue scope includes cloud and multi-tenant systems, resource management for networked systems, reliability, testing/debugging, and practical evaluation.
- The extra time after ATC 2026 is enough to produce a real implementation and evaluation if the team executes tightly.

## Key dates

| Item | Date |
|---|---|
| Fall title/abstract deadline | 2026-09-10, 11:59 pm US EDT |
| Fall full-paper deadline | 2026-09-17, 11:59 pm US EDT |
| Fall notification | 2026-12-08 |
| Final paper files due | 2027-03-04 |
| Conference | 2027-05-11 to 2027-05-13 |
| Location | Providence, Rhode Island, USA |

## Submission format

- Double-blind review.
- Maximum 12 pages including footnotes, figures, and tables.
- References and appendices may use additional pages.
- Two-column format, 10-point Times-Roman or similar font, 12-point leading.
- The Introduction is prescreened and should not exceed three pages after the abstract.
- Three tracks are available: Traditional Research, Frontiers, and Operational Systems.

## Recommended track

```text
Traditional Research Track
```

Reason:

- The idea is implementable and should be evaluated thoroughly.
- Frontiers Track is for bold ideas that are not expected to be fully evaluated; this project should not be submitted as incomplete early-stage work.
- Operational Systems Track requires real deployment/operational lessons, which this package does not currently have.

## Why NSDI is a good fit

ContractBPF-Ledger can be positioned as a resource-management system for networked services:

```text
multi-tenant services + programmable kernel policies + tail-latency stability + runtime recovery
```

This fits NSDI better than an idea-only workshop because the work can be evaluated on service latency, throughput, recovery, and overhead.

## Why NSDI is dangerous

The kernel substrate may make the paper look like a pure OS paper. To fit NSDI, the paper must emphasize:

1. cloud / multi-tenant networked services;
2. service-level latency and recovery;
3. resource-management interactions visible to operators;
4. practical evaluation, not only kernel microbenchmarks.

## Fallback venue

**OSDI 2027** is the preferred fallback if implementation and evaluation require more time or if the NSDI framing remains weak. Use OSDI only after confirming its official CFP/deadline.
