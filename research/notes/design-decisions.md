# Design Decisions

- Enforce at effect boundaries, not every BPF instruction.
- Start with `sched_ext` before MM hooks.
- Use conservative, kernel-validated paging decisions.
- Use invariant-based cross-subsystem rules before weighted scoring.
- Treat QEMU results as correctness/reproducibility evidence unless validated elsewhere.

