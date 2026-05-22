# QEMU Validation

All experimental kernel validation must run in QEMU, never on the host kernel.

Pre-QEMU checks:

1. kernel config exists;
2. kernel image exists;
3. initramfs exists;
4. boot command is logged;
5. run script has a timeout;
6. serial console output is captured;
7. failures preserve logs.

M1 smoke success requires `CONTRACTBPF_BOOT_OK` in the serial log.

M5 MM-hook prototype success requires:

```text
CONTRACTBPF_BOOT_OK
CONTRACTBPF_MM_HOOK_OK
CONTRACTBPF_DEGRADE_OK
```

The corresponding run script is `qemu/run/run-mm-hook.sh`; it validates the
kernel debugfs `mm_selftest` path and stores serial output under
`artifacts/logs/`.

Contract manager guest startup success requires:

```text
CONTRACTBPF_BOOT_OK
CONTRACTBPF_CONTRACTD_OK
```

The corresponding run script is `qemu/run/run-contractd.sh`; it boots the
patched kernel, mounts debugfs, starts `/usr/local/bin/contractd`, and checks
that the daemon can discover the ContractBPF debugfs interface.

M6 cross-subsystem rule selftest evidence is currently produced by
`make kselftest`. The guest must print:

```text
PASS cross_scope_shared revoke_demote preserve_sched_dispatch audit_event
```

This is a rule-path validation, not the final workload conflict reproduction.

Controlled conflict validation is available through `make qemu-conflict`. It
boots QEMU, loads `scx_contract_boost`, runs the synthetic phase service, records
an unguarded feedback-loop ledger snapshot, then reruns the same ledger scenario
with the cross rule enabled. Required markers:

```text
CONTRACTBPF_CONFLICT_REPRODUCED
CONTRACTBPF_RECOVERY_OK
CONTRACTBPF_SCHED_EXT_UNLOAD_OK
```

Recovery-curve generation is available through `make qemu-recovery`. It reruns
the controlled conflict scenario, parses the QEMU serial log, writes raw CSV
under `artifacts/traces/`, writes a processed CSV under
`experiments/results/processed/`, and writes an SVG under
`experiments/results/figures/`. Required marker:

```text
CONTRACTBPF_RECOVERY_CURVE_OK
```
