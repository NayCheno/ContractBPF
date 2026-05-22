use libcontract::{EffectToken, EffectType, ScopeId};

pub fn example_token() -> EffectToken {
    EffectToken {
        policy: "latency_sched_A".to_string(),
        effect: EffectType::SchedBoost,
        scope: ScopeId {
            scope_type: "cgroup".to_string(),
            primary_id: "service-A".to_string(),
            secondary_id: None,
        },
    }
}

