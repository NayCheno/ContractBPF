# BPF Policies

This directory will hold scheduler, paging, and contract manifest examples.

Host loading is forbidden; all experimental BPF policy validation must happen in QEMU after the guest artifact is ready.

The M4 validation uses `scx_contract_boost`, an intentionally over-aggressive
`sched_ext` policy carried in the pinned kernel `tools/sched_ext` patch. The
source mirror in `sched_ext/scx_bad_boost.bpf.c` documents the policy behavior:
it requests a long task slice so ContractBPF can throttle/revoke the boost
effect without killing the scheduler.

The MM policy sources under `mm/` now build as real `SEC("syscall")` BPF
programs. `contract_mm_loader` loads each object in the QEMU guest, writes a
read-only-to-BPF `contract_mm_state` map, and uses `BPF_PROG_RUN` to verify the
decision returned by `phase_paging`, `bad_demote`, and `conservative_noop`.
It also registers the loaded BPF program and state map with `/dev/contractbpf`,
then asks the kernel MM hook entry point to run the registered policy before
ContractBPF validates the returned decision. This is QEMU hook-entry evidence,
not a bare-metal memory-pressure evaluation.
