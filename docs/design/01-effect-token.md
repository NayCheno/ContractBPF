# Effect Token

An effect token authorizes a BPF policy to produce one bounded resource effect within one scope.

```text
Token = <subsystem, effect, scope, budget, fallback>
```

Examples:

```text
<sched_ext, boost_task, cgroup=service-A, queue_delay_budget=5ms, fallback=throttle_boost>
<mm, demote_page, memcg=service-A, refault_budget=2.0x, fallback=revoke_demote>
```

Tokens ask whether a policy may create effect `E` within scope `S`, under budget `B`, with recovery action `F`. They are not helper allowlists and they do not replace verifier checks.

