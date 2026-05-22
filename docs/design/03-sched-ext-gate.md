# sched_ext Effect Gate

The scheduler front-end gates resource effects at selected `sched_ext` boundaries:

- `select_cpu`
- enqueue
- dispatch
- task boost or priority adjustment
- CPU steering or pinning
- DSQ drain and dispatch-failure recovery

Initial measured metrics:

- runnable-to-dispatch delay;
- queue delay per service scope;
- boost rate;
- failed dispatches;
- starvation window;
- runnable-but-idle time.

Initial degrade actions:

| Trigger | L1 | L2 | L3 |
|---|---|---|---|
| queue delay high | throttle boost | revoke boost | disable sched_ext policy |
| dispatch failures | drain DSQ | revoke dispatch modification | disable scheduler |
| starvation risk | force dispatch | fallback scheduler | disable scheduler |

