# Evaluation Plan

Required groups:

- G1: Linux default scheduler + default paging
- G2: `sched_ext` policy only
- G3: BPF/PageFlex-style paging policy only
- G4: `sched_ext` + paging, no ledger
- G5: cgroup/memcg quota-style controls
- G6: static checker only
- G7: per-subsystem ledger only
- G8: kill-whole-policy fallback
- G9: full ContractBPF-Ledger

The initial M1 work produces no performance claims. QEMU smoke logs are correctness and reproducibility evidence only.

