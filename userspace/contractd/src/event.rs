#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditEvent {
    pub scope: String,
    pub action: String,
}

