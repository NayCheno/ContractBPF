#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DegradeLevel {
    Normal,
    Throttle,
    Revoke,
    Fallback,
    DisablePolicy,
}

