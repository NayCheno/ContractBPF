# Userspace

The userspace workspace will contain:

- `contractd`: contract manager daemon;
- `contractctl`: CLI;
- `libcontract`: shared manifest, scope, token, ledger, event, and degrade types.

M1 only requires these crates to exist as scaffolding. Kernel control-plane integration starts after ContractBPF core patches exist.

