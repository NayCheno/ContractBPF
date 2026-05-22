#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct LedgerSnapshot {
    pub sched_queue_delay_us: u64,
    pub pages_demoted: u64,
    pub refault_events: u64,
}

