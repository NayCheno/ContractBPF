# 03. Implementation Plan

## Implementation principle

Do not instrument every BPF instruction. Enforce only at **effect boundaries**.

```text
BPF policy proposes a resource decision.
Kernel ContractBPF-Ledger layer validates the corresponding effect token and ledger budget.
Kernel either executes, throttles, revokes, or falls back.
```

## System components

```text
User-space Contract Manager
  ├── parses contract manifests
  ├── resolves scopes to cgroup/memcg/region IDs
  ├── installs effect-token tables
  └── exports violation/audit events

Kernel ContractBPF-Ledger Layer
  ├── effect-token table
  ├── per-scope resource ledger
  ├── effect gate
  ├── degrade controller
  └── event ring buffer

Subsystem front-ends
  ├── sched_ext front-end
  └── paging decision front-end
```

## Scope representation

```c
struct contract_scope_id {
    enum scope_type type;      // CGROUP, MEMCG, CPUSET, NUMA_NODE, REGION
    u64 primary_id;
    u64 secondary_id;
};
```

A service-level scope should resolve cgroup and memcg together:

```text
service-A => cgroup-A + memcg-A + optional CPU/NUMA scope
```

## Effect token representation

```c
enum contract_effect_type {
    CONTRACT_EFFECT_SCHED_BOOST,
    CONTRACT_EFFECT_SCHED_DISPATCH,
    CONTRACT_EFFECT_SCHED_PIN_CPU,
    CONTRACT_EFFECT_MM_DEMOTE_PAGE,
    CONTRACT_EFFECT_MM_RECLAIM_HINT,
    CONTRACT_EFFECT_MM_CLASSIFY_REGION,
};

struct contract_effect_token {
    u64 prog_id;
    struct contract_scope_id scope;
    enum contract_effect_type effect;
    struct contract_budget budget;
    enum contract_degrade_action degrade_l1;
    enum contract_degrade_action degrade_l2;
    enum contract_degrade_action degrade_l3;
    u64 epoch_ns;
};
```

## Ledger representation

Use per-CPU counters where possible and aggregate at epoch boundaries.

```c
struct contract_ledger {
    struct contract_scope_id scope;
    atomic64_t sched_queue_delay_us;
    atomic64_t sched_dispatch_failures;
    atomic64_t sched_boost_events;
    atomic64_t pages_demoted;
    atomic64_t refault_events;
    atomic64_t major_fault_events;
    atomic64_t fault_latency_us;
    atomic64_t violations;
    u64 current_epoch;
    u32 degrade_state[CONTRACT_EFFECT_MAX];
};
```

## Core effect gate

```c
int contract_effect_gate(struct bpf_prog *prog,
                         enum contract_effect_type effect,
                         struct contract_scope_id scope,
                         struct contract_effect_cost cost)
{
    struct contract_effect_token *tok;
    struct contract_ledger *ledger;

    tok = contract_lookup_token(prog->aux->id, effect, scope);
    if (!tok)
        return CONTRACT_DENY;

    ledger = contract_lookup_ledger(scope);
    if (!ledger)
        return CONTRACT_DENY;

    if (contract_would_exceed(ledger, tok, cost)) {
        contract_trigger_degrade(prog, effect, scope, ledger, tok);
        return CONTRACT_DEGRADED;
    }

    contract_charge(ledger, effect, cost);
    return CONTRACT_ALLOW;
}
```

## sched_ext front-end

### Effect boundaries

- `select_cpu`
- `enqueue`
- `dispatch`
- task boost / priority adjustment
- CPU pinning
- DSQ drain or dispatch-failure recovery

### Measured metrics

```text
runnable-to-dispatch delay
queue delay per service scope
boost rate
failed dispatches
starvation window
runnable-but-idle time
```

### Degradation actions

| Trigger | L1 | L2 | L3 |
|---|---|---|---|
| queue delay high | throttle boost | revoke boost | disable sched_ext policy |
| dispatch failures | drain DSQ | revoke dispatch modification | disable scheduler |
| starvation risk | force dispatch | fallback scheduler | disable scheduler |

## Paging front-end

### Conservative design

Avoid exposing mutable folio objects directly to BPF.

```text
BPF receives summarized read-only state.
BPF returns keep / demote / reclaim_hint / no_op.
Kernel validates budget and page state.
Kernel executes or ignores the effect.
```

### Effect boundaries

- page demotion decision
- reclaim hint
- region classification
- page-touch budget

### Measured metrics

```text
pages_demoted
refault_ratio
major_fault_rate
fault_latency_us
memory_pressure_score
pages_touched_per_epoch
```

### Degradation actions

| Trigger | L1 | L2 | L3 |
|---|---|---|---|
| high refault ratio | throttle demotion | revoke demote_page | kernel default reclaim |
| high fault latency | disable demotion for hot region | revoke demote_page | kernel default reclaim |
| high pages touched | sampling | ignore hints | revoke paging policy |

## Cross-subsystem rule

Minimum viable rule:

```text
if same_scope(service-A) and
   refault_ratio > R and
   queue_delay_us > Q and
   demote_rate > D:
       revoke demote_page for service-A for K epochs
       preserve sched_ext dispatch effect
```

## User-space manager

Responsibilities:

1. parse YAML contract manifests;
2. validate scope overlap and budget syntax;
3. load BPF programs normally;
4. install tokens through a BPF map or kernel control interface;
5. expose violation logs and time-series metrics;
6. emit artifact-friendly CSV traces.

## Implementation milestones

| Milestone | Deliverable |
|---|---|
| M1 | contract manifest parser and token table |
| M2 | sched_ext boost/dispatch gate |
| M3 | queue-delay ledger and scheduler degradation |
| M4 | paging decision hook and demotion gate |
| M5 | refault ledger and paging degradation |
| M6 | unified cgroup/memcg scope mapping |
| M7 | cross-subsystem recovery rule |
| M8 | artifact scripts and benchmark harness |

## Engineering risks

| Risk | Mitigation |
|---|---|
| MM hook too invasive | Use decision-only hook; kernel executes effects. |
| overhead too high | Per-CPU counters, epoch accounting, sampling. |
| attribution ambiguous | Use same service scope and demotion/refault temporal windows. |
| degradation oscillates | Add hysteresis and minimum revoke duration K epochs. |
| sched_ext API churn | Pin kernel version and document exact commit. |
