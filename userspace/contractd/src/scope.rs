#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedScope {
    pub cgroup: Option<String>,
    pub memcg: Option<String>,
}

