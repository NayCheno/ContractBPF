# Artifact Checklist

- [ ] Kernel patch series applies cleanly to pinned kernel.
- [ ] QEMU smoke boot is reproducible from scripts.
- [ ] `sched_ext` baseline loads and unloads.
- [ ] ContractBPF token and ledger selftests pass.
- [ ] Scheduler effect gate triggers and recovers.
- [ ] Paging decision hook triggers and recovers.
- [ ] Cross-subsystem conflict is reproduced.
- [ ] Full ContractBPF-Ledger recovers faster or less disruptively than coarse baselines.
- [ ] At least one real service workload is evaluated.
- [ ] At least one controlled synthetic workload is evaluated.
- [ ] Raw logs and scripts can regenerate all plots.
- [ ] Paper claims are updated to match measured evidence.

