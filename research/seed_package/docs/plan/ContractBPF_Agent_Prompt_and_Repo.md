# ContractBPF-Ledger Agent Prompt and Repository Blueprint

Version: 2026-05-21  
Target project: **ContractBPF-Ledger: Bounded Resource-Effect Accounting for BPF-Programmable Scheduling and Paging**  
Target venue: **NSDI 2027 Fall cycle**

This file is intended to be fed directly to an autonomous coding/research agent together with the existing `ContractBPF-Ledger_NSDI27_package.zip`.

---

## 1. Minimal prompt for the agent

Copy this block as the main prompt.

```text
You are an autonomous kernel-systems research engineering agent. Your goal is to turn the ContractBPF-Ledger research package into a working, reproducible Linux/QEMU artifact and a submission-grade NSDI-style system prototype.

Core thesis: verifier-accepted BPF policies can still create harmful cross-subsystem resource effects when BPF scheduling and BPF-style paging policies interact. Build ContractBPF-Ledger around effect tokens, per-scope resource ledgers, effect-boundary enforcement, and bounded degradation.

Work autonomously. Do not wait for clarification unless a destructive action is required. Each iteration must: inspect the current repo state, select the highest-priority failing milestone, implement the smallest useful change, run the relevant validation, record exact commands/results in STATUS.md, and update the next task.

Use QEMU for experimental kernel validation. Never boot or load experimental kernel patches on the host kernel. Only start QEMU after the kernel and guest artifacts build successfully. Treat QEMU as correctness/reproducibility validation; do not claim production-grade performance from QEMU-only measurements.

Do not fabricate results. If an experiment fails, write the failure, logs, hypothesis, and next fix. If the paging hook is blocked, implement a clearly marked conservative fallback while preserving the main thesis.

Primary deliverables: kernel patches, BPF policies, user-space contract manager, QEMU boot scripts, tests, workloads, experiment harness, plots, and paper-ready evidence.
```

---

## 2. Project thesis the agent must preserve

The existing research package defines the mechanism as:

```text
effect token + per-scope resource ledger + bounded degrade
```

The agent must not drift into a generic BPF sandbox, helper allowlist, verifier rewrite, or broad kernel-security platform.

### Correct framing

```text
Problem:
  BPF programs can pass the verifier and still compose into harmful resource-effect loops.

Concrete loop:
  BPF sched_ext policy boosts a latency-sensitive service.
  BPF/PageFlex-style paging policy demotes pages from the same service.
  Demotion causes refaults and major faults.
  Faults inflate queue delay and tail latency.
  The scheduler boosts the service even more.
  The system enters a scheduler-paging feedback loop.

Solution:
  Attribute each policy's dynamic resource effects to a service scope.
  Enforce effect budgets only at effect boundaries.
  Degrade the harmful effect, not the whole policy.
```

### Non-goals

```text
Do not replace the eBPF verifier.
Do not build a full transport/network datapath system.
Do not expose writable raw folio/page state to BPF.
Do not claim safety without measured evidence.
Do not submit a paper draft whose key results are placeholders.
```

---

## 3. Mandatory autonomous work loop

The agent should run this loop until the system reaches the submission-ready gate or a hard blocker is documented.

```text
while not SUBMISSION_READY:
    1. Read STATUS.md, docs/agent_logs/latest.md, and the current milestone gate.
    2. Pick the highest-priority failing gate.
    3. Implement the smallest change that advances that gate.
    4. Run the narrowest relevant validation first.
    5. If local validation passes, run the next broader validation.
    6. If the kernel artifact builds, validate in QEMU.
    7. Record exact commands, logs, pass/fail status, and next action.
    8. Commit or stage a logically isolated change.
    9. Continue without asking for permission.
```

### Status file format

Create and maintain `STATUS.md`:

```markdown
# STATUS

## Current milestone
M2: sched_ext baseline and QEMU smoke test

## Last completed action
- Command: `./scripts/qemu/run-smoke.sh`
- Result: PASS
- Log: `artifacts/logs/2026-05-21-qemu-smoke.log`

## Current failure / blocker
None.

## Next action
Implement scheduler boost token accounting in `kernel/patches/0002-contractbpf-sched-gate.patch`.

## Evidence checklist
- [ ] Kernel builds
- [ ] QEMU boots
- [ ] sched_ext baseline loads
- [ ] contractd starts
- [ ] ledger counters update
- [ ] bounded degrade triggers
- [ ] paging hook works
- [ ] cross-subsystem conflict reproduced
- [ ] recovery curve produced
```

---

## 4. Repository structure

Use this repository layout. Avoid committing the full Linux source tree, generated rootfs images, QEMU disk images, large benchmark outputs, or compiled binaries. Linux kernel source tarballs are available from https://www.kernel.org/pub/linux/kernel/v6.x/ and https://www.kernel.org/pub/linux/kernel/v7.x/; download a suitable kernel version for the experiment.

```text
contractbpf-ledger/
  README.md
  STATUS.md
  AGENT.md
  Makefile
  .gitignore

  research/
    seed_package/
      README.md
      paper/
      docs/
      metadata/
    notes/
      thesis.md
      design-decisions.md
      related-work.md
      reviewer-attacks.md

  kernel/
    README.md
    versions/
      pinned-kernel.txt
      toolchain.txt
    configs/
      qemu-x86_64-contractbpf.config
      qemu-x86_64-minimal.config
    patches/
      series
      0001-contractbpf-core-types-and-ledger.patch
      0002-contractbpf-sched-ext-effect-gate.patch
      0003-contractbpf-bounded-degrade-controller.patch
      0004-contractbpf-mm-decision-hook.patch
      0005-contractbpf-cross-subsystem-ledger.patch
      0006-contractbpf-kselftests.patch
    selftests/
      contractbpf/
        Makefile
        test_tokens.c
        test_ledger.c
        test_degrade.sh
        test_sched_ext_gate.sh
        test_mm_hook.sh
    scripts/
      fetch-linux.sh
      apply-patches.sh
      configure-kernel.sh
      build-kernel.sh
      build-selftests.sh
      clean-kernel.sh

  bpf/
    README.md
    include/
      contract_common.bpf.h
      contract_maps.bpf.h
      contract_sched.bpf.h
      contract_mm.bpf.h
    sched_ext/
      scx_contract_latency.bpf.c
      scx_contract_latency.c
      scx_bad_boost.bpf.c
    mm/
      phase_paging.bpf.c
      bad_demote.bpf.c
      conservative_noop_paging.bpf.c
    contracts/
      service_a_sched.yaml
      service_a_paging.yaml
      service_a_composition.yaml
      bad_missing_fallback.yaml
    Makefile

  userspace/
    README.md
    contractd/
      Cargo.toml
      src/
        main.rs
        manifest.rs
        scope.rs
        token.rs
        ledger.rs
        event.rs
        degrade.rs
    contractctl/
      Cargo.toml
      src/main.rs
    libcontract/
      Cargo.toml
      src/lib.rs
    scripts/
      install-contracts.sh
      collect-events.sh
      dump-ledger.sh

  qemu/
    README.md
    rootfs/
      Dockerfile
      build-rootfs.sh
      init
      guest-init.sh
      guest-smoke.sh
      guest-run-workload.sh
    run/
      run-smoke.sh
      run-sched-ext.sh
      run-contractd.sh
      run-conflict.sh
      run-recovery.sh
      run-kselftest.sh
    expect/
      boot.expect
      smoke.expect
    images/
      .gitkeep

  workloads/
    README.md
    memcached/
      run-server.sh
      run-load.sh
      config.yaml
    redis/
      run-server.sh
      run-load.sh
      config.yaml
    synthetic_phase_service/
      src/main.c
      Makefile
      run.sh
    memory_pressure/
      pressure.c
      Makefile
      run-pressure.sh
    cpu_interferer/
      burn.c
      Makefile
      run.sh

  experiments/
    README.md
    configs/
      g1_default.yaml
      g2_sched_only.yaml
      g3_paging_only.yaml
      g4_combined_no_ledger.yaml
      g5_cgroup_memcg.yaml
      g6_static_checker_only.yaml
      g7_per_subsystem_ledger.yaml
      g8_whole_policy_fallback.yaml
      g9_full_contractbpf.yaml
    runners/
      run_group.py
      run_matrix.py
      collect_guest_logs.py
      summarize.py
    analysis/
      parse_latency.py
      parse_faults.py
      parse_sched.py
      plot_feedback_timeline.py
      plot_tail_latency.py
      plot_recovery.py
      plot_overhead.py
    results/
      README.md
      raw/.gitkeep
      processed/.gitkeep
      figures/.gitkeep

  docs/
    design/
      00-overview.md
      01-effect-token.md
      02-ledger.md
      03-sched-ext-gate.md
      04-mm-decision-hook.md
      05-bounded-degrade.md
      06-cross-subsystem-rule.md
    implementation/
      kernel-patch-notes.md
      qemu-validation.md
      debugging.md
    evaluation/
      experiment-plan.md
      metrics.md
      artifact-checklist.md
    agent_logs/
      latest.md
      archive/.gitkeep

  paper/
    nsdi27/
      contractbpf_ledger_nsdi27.tex
      references.bib
      figures/
      tables/
      notes/

  artifacts/
    logs/.gitkeep
    builds/.gitkeep
    traces/.gitkeep
    qemu/.gitkeep
```

### `.gitignore` baseline

```gitignore
# Linux source/build trees
linux/
linux-*/
build/
out/
*.o
*.ko
*.a
*.so
*.d
*.cmd
*.mod
*.mod.c
Module.symvers
modules.order
vmlinux
bzImage
System.map

# QEMU and rootfs artifacts
qemu/images/*.img
qemu/images/*.qcow2
qemu/images/*.raw
qemu/images/*.cpio
qemu/images/*.cpio.gz
qemu/images/*.ext4

# Experiment outputs
experiments/results/raw/*
experiments/results/processed/*
experiments/results/figures/*
!experiments/results/raw/.gitkeep
!experiments/results/processed/.gitkeep
!experiments/results/figures/.gitkeep
artifacts/logs/*
artifacts/builds/*
artifacts/traces/*
artifacts/qemu/*
!artifacts/logs/.gitkeep
!artifacts/builds/.gitkeep
!artifacts/traces/.gitkeep
!artifacts/qemu/.gitkeep

# Rust/Python local state
target/
.venv/
__pycache__/
*.pyc
```

---

## 5. Milestones and gates

### M0 — Repository bootstrap

Goal: unpack the research package, create the repo skeleton, pin versions, and write the first `STATUS.md`.

Required actions:

```text
1. Unpack `ContractBPF-Ledger_NSDI27_package.zip` into `research/seed_package/`.
2. Copy the LaTeX draft into `paper/nsdi27/`.
3. Create all top-level directories listed above.
4. Create `kernel/versions/pinned-kernel.txt`.
5. Create `docs/design/00-overview.md` with the thesis and non-goals.
6. Create initial `STATUS.md`.
```

Gate:

```text
PASS if repo skeleton exists, package is preserved, and STATUS.md identifies M1 as next.
```

---

### M1 — Vanilla kernel build and QEMU boot

Goal: prove the repository can build and boot a pinned kernel in QEMU before adding research patches.

Required kernel config features:

```text
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_JIT_ALWAYS_ON=y
CONFIG_BPF_JIT_DEFAULT_ON=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_SCHED_CLASS_EXT=y
```

Required actions:

```text
1. Fetch pinned Linux source outside the git-tracked tree.
2. Generate QEMU x86_64 config.
3. Build `arch/x86/boot/bzImage`.
4. Build a minimal initramfs or rootfs.
5. Boot QEMU using the built kernel.
6. Save console output under `artifacts/logs/`.
```

Reference QEMU command shape:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp 4 \
  -m 8192 \
  -kernel build/linux/arch/x86/boot/bzImage \
  -initrd qemu/images/initramfs.cpio.gz \
  -append "console=ttyS0 panic=-1 nokaslr" \
  -nographic \
  -no-reboot
```

Gate:

```text
PASS if QEMU boots, guest init prints `CONTRACTBPF_BOOT_OK`, and the log is saved.
```

---

### M2 — sched_ext baseline

Goal: load a baseline sched_ext scheduler in QEMU and verify sched_ext state.

Required actions:

```text
1. Build the kernel's `tools/sched_ext` examples or an equivalent minimal scx scheduler.
2. Copy the scheduler binary and dependencies into the guest rootfs.
3. Run it inside QEMU.
4. Confirm `/sys/kernel/sched_ext/state` becomes enabled.
5. Confirm fallback/unload works.
```

Gate:

```text
PASS if a minimal BPF scheduler loads in QEMU and can be stopped without panic.
```

---

### M3 — ContractBPF core: token and ledger

Goal: implement the smallest kernel-side ContractBPF core.

Suggested kernel-side files after patch application:

```text
include/linux/contractbpf.h
kernel/bpf/contractbpf_core.c
kernel/bpf/contractbpf_ledger.c
kernel/bpf/contractbpf_degrade.c
```

Minimum data types:

```c
enum contract_effect_type {
    CONTRACT_EFFECT_SCHED_BOOST,
    CONTRACT_EFFECT_SCHED_DISPATCH,
    CONTRACT_EFFECT_SCHED_PIN_CPU,
    CONTRACT_EFFECT_MM_DEMOTE_PAGE,
    CONTRACT_EFFECT_MM_RECLAIM_HINT,
    CONTRACT_EFFECT_MM_CLASSIFY_REGION,
};

struct contract_scope_id {
    u32 type;
    u64 primary_id;
    u64 secondary_id;
};

struct contract_effect_token {
    u64 prog_id;
    struct contract_scope_id scope;
    enum contract_effect_type effect;
    u64 budget_primary;
    u64 budget_secondary;
    u64 epoch_ns;
    u32 degrade_state;
};
```

Minimum API shape:

```c
int contract_effect_gate(u64 prog_id,
                         enum contract_effect_type effect,
                         struct contract_scope_id scope,
                         u64 cost_primary,
                         u64 cost_secondary);

void contract_ledger_charge(struct contract_scope_id scope,
                            enum contract_effect_type effect,
                            u64 cost_primary,
                            u64 cost_secondary);

void contract_trigger_degrade(u64 prog_id,
                              enum contract_effect_type effect,
                              struct contract_scope_id scope,
                              const char *reason);
```

Gate:

```text
PASS if kernel builds with ContractBPF core and kselftests can exercise token lookup, ledger charge, and basic degrade state transitions.
```

---

### M4 — sched_ext effect gate and scheduler ledger

Goal: enforce scheduler-side effects at effect boundaries.

Required actions:

```text
1. Add gate calls around selected sched_ext effect boundaries.
2. Implement a BPF scheduler that boosts service-A.
3. Account for boost events, queue delay, dispatch failures, and runnable-but-idle time.
4. Implement throttle_boost and revoke_boost degrade states.
5. Demonstrate effect-level degradation without killing the whole scheduler.
```

Minimum effect-boundary targets:

```text
select_cpu
priority/boost decision
enqueue
dispatch
CPU steering / pinning
```

Gate:

```text
PASS if an intentionally over-aggressive scheduler triggers throttle or revoke, while the guest remains alive and sched_ext fallback still works.
```

---

### M5 — Conservative paging decision hook

Goal: implement a safe PageFlex-style paging decision front-end without exposing writable raw folio/page state to BPF.

Required design rule:

```text
BPF receives summarized read-only page/region state.
BPF returns keep / demote / reclaim_hint / no_op.
Kernel validates the decision, checks the effect token and ledger, then executes or ignores the effect.
```

Required actions:

```text
1. Implement a conservative decision hook in the MM path or a clearly marked prototype path.
2. Add demote_page and reclaim_hint effect tokens.
3. Account for pages_demoted, refaults, major faults, and fault latency.
4. Implement throttle_demote and revoke_demote degrade states.
```

Gate:

```text
PASS if a bad demotion policy increases refaults and ContractBPF can revoke demote_page while preserving other policy behavior.
```

Fallback if blocked:

```text
Implement an observability-only tracing prototype to collect refault/demotion evidence, but mark it as NOT the final enforcement mechanism. Continue implementing the final hook in parallel.
```

---

### M6 — Cross-subsystem ledger and conflict rule

Goal: link scheduler and paging effects under a unified service scope.

Start with this invariant, not a weighted score:

```text
if scope == service-A
and refault_ratio > R
and queue_delay_us > Q
and pages_demoted_per_epoch > D:
    revoke demote_page for service-A
    preserve sched_ext dispatch_task
```

Required actions:

```text
1. Resolve service-A to cgroup + memcg + optional CPU/NUMA scope.
2. Charge scheduler and paging effects into the same per-scope ledger.
3. Trigger cross-subsystem degrade when the invariant fails.
4. Emit an audit event showing the reason and affected effect.
```

Gate:

```text
PASS if the unguarded scheduler+paging combination produces a harmful feedback loop and the guarded version recovers by revoking only the harmful paging effect.
```

---

### M7 — Evaluation harness

Goal: generate paper-ready evidence.

Required groups:

```text
G1: Linux default scheduler + default paging
G2: sched_ext policy only
G3: BPF/PageFlex-style paging policy only
G4: sched_ext + paging, no ledger
G5: cgroup/memcg quota-style controls
G6: static checker only
G7: per-subsystem ledger only
G8: kill-whole-policy fallback
G9: full ContractBPF-Ledger
```

Required metrics:

```text
P50/P99/P999 latency
throughput
major fault rate
refault ratio
scheduler queue delay
pages demoted per epoch
boost events per epoch
fallback activation latency
recovery time
steady-state overhead
unaffected-tenant latency
```

Gate:

```text
PASS if the result set contains raw logs, processed tables, and at least these figures:
1. harmful feedback timeline;
2. tail-latency comparison;
3. recovery timeline;
4. ablation;
5. overhead.
```

---

### M8 — Paper integration

Goal: replace placeholders in the LaTeX draft with measured evidence.

Required actions:

```text
1. Add implementation section with exact kernel version, patch size, and components.
2. Add evaluation section with real groups and metrics.
3. Add limitation section that distinguishes QEMU correctness from non-QEMU performance.
4. Update threat model and non-goals.
5. Update related work.
6. Ensure claims match measured data.
```

Gate:

```text
PASS if every major claim in the paper has a corresponding artifact log, plot, or code path.
```

---

## 6. Validation policy

### Never do this

```text
Never boot the experimental kernel on the host.
Never load experimental BPF policies against the host kernel.
Never run destructive memory-pressure experiments outside QEMU or an explicitly dedicated test host.
Never claim success from a script that did not check exit codes.
Never hide kernel panics, verifier failures, or missing logs.
```

### Pre-QEMU gate

Before QEMU boot, the agent must verify:

```text
1. Kernel config exists.
2. Kernel image exists.
3. Rootfs/initramfs exists.
4. The boot command is logged.
5. The run script has a timeout.
6. Console output is captured.
7. Failure preserves logs.
```

### QEMU smoke success criteria

The guest must print these markers:

```text
CONTRACTBPF_BOOT_OK
CONTRACTBPF_SCHED_EXT_OK
CONTRACTBPF_CONTRACTD_OK
CONTRACTBPF_LEDGER_OK
CONTRACTBPF_DEGRADE_OK
```

Not all markers are expected in early milestones. Each run script should define which markers are mandatory.

---

## 7. Suggested scripts

### Top-level Makefile targets

```makefile
bootstrap:
	./kernel/scripts/fetch-linux.sh
	./kernel/scripts/configure-kernel.sh
	./qemu/rootfs/build-rootfs.sh

kernel:
	./kernel/scripts/apply-patches.sh
	./kernel/scripts/build-kernel.sh

bpf:
	$(MAKE) -C bpf

userspace:
	cargo build --manifest-path userspace/contractd/Cargo.toml
	cargo build --manifest-path userspace/contractctl/Cargo.toml

qemu-smoke:
	./qemu/run/run-smoke.sh

qemu-sched:
	./qemu/run/run-sched-ext.sh

qemu-conflict:
	./qemu/run/run-conflict.sh

qemu-recovery:
	./qemu/run/run-recovery.sh

experiments:
	python3 experiments/runners/run_matrix.py --config experiments/configs

figures:
	python3 experiments/analysis/plot_feedback_timeline.py
	python3 experiments/analysis/plot_tail_latency.py
	python3 experiments/analysis/plot_recovery.py
	python3 experiments/analysis/plot_overhead.py
```

### Smoke script behavior

`qemu/run/run-smoke.sh` should:

```text
1. check that bzImage exists;
2. check that initramfs exists;
3. start QEMU with a timeout;
4. capture serial console;
5. search for required markers;
6. return non-zero if a marker is missing;
7. store logs in artifacts/logs/;
8. update STATUS.md or print an exact next action.
```

---

## 8. Implementation priorities

### Priority 1: correctness before novelty

The first valuable artifact is not the full system. It is:

```text
vanilla kernel + sched_ext + QEMU + reproducible logs
```

Without this, later measurements are not credible.

### Priority 2: scheduler-side MVP before MM-side MVP

`sched_ext` is the lower-risk first subsystem. Build confidence there before touching MM paths.

### Priority 3: conservative MM hook

The paging side should be decision-only and kernel-validated.

Preferred pattern:

```text
BPF proposes: DEMOTE / KEEP / RECLAIM_HINT / NO_OP
Kernel checks: token, budget, page state, safety constraints
Kernel executes: demote or ignore
```

Rejected pattern:

```text
BPF receives writable folio pointer and mutates MM state directly
```

### Priority 4: cross-subsystem invariant, not weighted scoring

Use a simple invariant first:

```text
refault_ratio high + queue_delay high + demotion high => revoke demote_page
```

Weighted scores can appear later as an optional policy, not the core contribution.

---

## 9. Agent decision rules for blockers

### If sched_ext does not build

```text
1. Check kernel version and CONFIG_SCHED_CLASS_EXT.
2. Build tools/sched_ext examples.
3. If examples fail, record compiler/toolchain versions.
4. Try a newer pinned kernel only after documenting the failure.
5. Do not switch the research thesis.
```

### If QEMU does not boot

```text
1. Save full serial log.
2. Check console=ttyS0 and init path.
3. Check initramfs permissions and static binaries.
4. Boot vanilla kernel before patched kernel.
5. Reduce kernel config only if needed.
```

### If paging hook is blocked

```text
1. Implement observability-only refault/fault tracing as temporary support.
2. Keep working on a conservative kernel-validated decision hook.
3. Label all observability-only results as non-enforcement evidence.
4. Do not claim ContractBPF enforces paging until the gate passes.
```

### If conflict is not reproducible

```text
1. Use a controlled synthetic phase-changing service.
2. Increase memory pressure gradually.
3. Verify scheduler-only and paging-only benefits independently.
4. Log demotion, refaults, queue delay, and latency on the same timeline.
5. Only then return to real services such as memcached, Redis, or RocksDB.
```

---

## 10. Paper-readiness checklist

The system is not paper-ready until all of the following are true:

```text
[ ] Kernel patch series applies cleanly to pinned kernel.
[ ] QEMU smoke boot is reproducible from scripts.
[ ] sched_ext baseline loads and unloads.
[ ] ContractBPF token and ledger selftests pass.
[ ] Scheduler effect gate triggers and recovers.
[ ] Paging decision hook triggers and recovers.
[ ] Cross-subsystem conflict is reproduced.
[ ] Full ContractBPF-Ledger recovers faster or less disruptively than coarse baselines.
[ ] At least one real service workload is evaluated.
[ ] At least one controlled synthetic workload is evaluated.
[ ] Raw logs and scripts can regenerate all plots.
[ ] Paper claims are updated to match measured evidence.
```

Hard rule:

```text
If this checklist is not complete, do not present the paper as NSDI-ready. Present it as an in-progress artifact.
```

---

## 11. External references the agent may consult

Use these as implementation anchors. Prefer official documentation when resolving conflicts.

```text
Linux sched_ext documentation:
https://docs.kernel.org/scheduler/sched-ext.html

QEMU direct Linux boot documentation:
https://qemu-project.gitlab.io/qemu/system/linuxboot.html

Linux kernel build/admin guide:
https://docs.kernel.org/admin-guide/README.html

Linux kselftest documentation:
https://docs.kernel.org/dev-tools/kselftest.html

Linux eBPF verifier documentation:
https://docs.kernel.org/bpf/verifier.html

Linux eBPF userspace API documentation:
https://docs.kernel.org/userspace-api/ebpf/index.html

PageFlex ATC 2025 page:
https://www.usenix.org/conference/atc25/presentation/yelam

NSDI 2027 CFP:
https://www.usenix.org/conference/nsdi27/call-for-papers

sched_ext/scx tools and examples:
https://github.com/sched-ext/scx
```

---

## 12. First instruction to the agent after feeding this file

Use this as the first task after the agent reads the file:

```text
Create the repository skeleton exactly as specified. Unpack the research package into research/seed_package/. Create STATUS.md. Then implement M1: build a pinned sched_ext-capable Linux kernel and boot it in QEMU with a minimal initramfs that prints CONTRACTBPF_BOOT_OK. Record all commands and logs. Do not start ContractBPF kernel patches until M1 passes.
```
