#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EffectType {
    SchedBoost,
    SchedDispatch,
    SchedPinCpu,
    MmDemotePage,
    MmReclaimHint,
    MmClassifyRegion,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScopeId {
    pub scope_type: String,
    pub primary_id: String,
    pub secondary_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EffectToken {
    pub policy: String,
    pub effect: EffectType,
    pub scope: ScopeId,
}

