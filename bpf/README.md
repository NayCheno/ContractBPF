# BPF Policies

This directory will hold scheduler, paging, and contract manifest examples.

Host loading is forbidden; all experimental BPF policy validation must happen in QEMU after the guest artifact is ready.

The M4 validation uses `scx_contract_boost`, an intentionally over-aggressive
`sched_ext` policy carried in the pinned kernel `tools/sched_ext` patch. The
source mirror in `sched_ext/scx_bad_boost.bpf.c` documents the policy behavior:
it requests a long task slice so ContractBPF can throttle/revoke the boost
effect without killing the scheduler.
