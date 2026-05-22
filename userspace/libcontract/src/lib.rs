use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::{self, Display, Formatter};
use std::fs;
use std::fs::OpenOptions;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug)]
pub enum ContractError {
    Io(String),
    Parse(String),
    Validation(String),
    State(String),
}

impl Display for ContractError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            ContractError::Io(msg) => write!(f, "io error: {msg}"),
            ContractError::Parse(msg) => write!(f, "parse error: {msg}"),
            ContractError::Validation(msg) => write!(f, "validation error: {msg}"),
            ContractError::State(msg) => write!(f, "state error: {msg}"),
        }
    }
}

impl Error for ContractError {}

impl From<std::io::Error> for ContractError {
    fn from(err: std::io::Error) -> Self {
        ContractError::Io(err.to_string())
    }
}

pub type ContractResult<T> = Result<T, ContractError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EffectType {
    SchedBoost,
    SchedDispatch,
    SchedPinCpu,
    MmDemotePage,
    MmReclaimHint,
    MmClassifyRegion,
}

impl EffectType {
    pub fn from_manifest_name(name: &str) -> Option<Self> {
        match name {
            "boost_task" | "sched_boost" => Some(Self::SchedBoost),
            "dispatch_task" | "sched_dispatch" => Some(Self::SchedDispatch),
            "pin_cpu" | "sched_pin_cpu" => Some(Self::SchedPinCpu),
            "demote_page" | "mm_demote_page" => Some(Self::MmDemotePage),
            "reclaim_hint" | "mm_reclaim_hint" => Some(Self::MmReclaimHint),
            "classify_region" | "mm_classify_region" => Some(Self::MmClassifyRegion),
            _ => None,
        }
    }

    pub fn kernel_name(self) -> &'static str {
        match self {
            Self::SchedBoost => "sched_boost",
            Self::SchedDispatch => "sched_dispatch",
            Self::SchedPinCpu => "sched_pin_cpu",
            Self::MmDemotePage => "mm_demote_page",
            Self::MmReclaimHint => "mm_reclaim_hint",
            Self::MmClassifyRegion => "mm_classify_region",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScopeId {
    pub scope_type: String,
    pub primary_id: String,
    pub secondary_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EffectToken {
    pub policy: String,
    pub effect: EffectType,
    pub scope: ScopeId,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContractManifest {
    pub policy: String,
    pub subsystem: String,
    pub scope: ScopeSpec,
    #[serde(default)]
    pub effects: Vec<EffectSpec>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScopeSpec {
    #[serde(rename = "type")]
    pub scope_type: String,
    pub id: String,
    #[serde(default)]
    pub cgroup_path: Option<PathBuf>,
    #[serde(default)]
    pub memcg_path: Option<PathBuf>,
    #[serde(default)]
    pub numa_node: Option<u32>,
    #[serde(default)]
    pub service_tag: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EffectSpec {
    pub name: String,
    #[serde(default)]
    pub budget: BTreeMap<String, serde_yaml::Value>,
    #[serde(default)]
    pub degrade: Option<DegradeSpec>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DegradeSpec {
    #[serde(default)]
    pub level1: Option<String>,
    #[serde(default)]
    pub level2: Option<String>,
    #[serde(default)]
    pub level3: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CompositionManifest {
    pub composition: CompositionSpec,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CompositionSpec {
    pub scope: String,
    #[serde(default)]
    pub coupled_effects: Vec<String>,
    #[serde(default)]
    pub invariant: BTreeMap<String, serde_yaml::Value>,
    #[serde(default)]
    pub violation: Option<ViolationSpec>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ViolationSpec {
    #[serde(default)]
    pub r#if: BTreeMap<String, serde_yaml::Value>,
    #[serde(default)]
    pub then: BTreeMap<String, serde_yaml::Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ManifestDocument {
    Contract(ContractManifest),
    Composition(CompositionManifest),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedScope {
    pub label: String,
    pub scope_type: String,
    pub cgroup_path: Option<PathBuf>,
    pub cgroup_id: Option<u64>,
    pub memcg_path: Option<PathBuf>,
    pub memcg_id: Option<u64>,
    pub numa_node: Option<u32>,
    pub service_tag: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InstalledPolicy {
    pub manifest_path: PathBuf,
    pub manifest: ContractManifest,
    pub resolved_scope: ResolvedScope,
    pub loaded_at_unix: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct StateStore {
    #[serde(default)]
    pub policies: BTreeMap<String, InstalledPolicy>,
    #[serde(default)]
    pub manual_degrades: Vec<ManualDegrade>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManualDegrade {
    pub policy: String,
    pub effect: String,
    pub scope: String,
    pub recorded_at_unix: u64,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LedgerSnapshot {
    pub sched_dispatch_events: u64,
    pub sched_boost_events: u64,
    pub sched_queue_delay_us: u64,
    pub pages_demoted: u64,
    pub reclaim_hints: u64,
    pub refault_events: u64,
    pub major_fault_events: u64,
    pub fault_latency_us: u64,
    pub violations: u64,
    pub sched_degrade_state: u64,
    pub demote_degrade_state: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelInstallReport {
    pub device: PathBuf,
    pub policy_id: u64,
    pub installed_tokens: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelChargeReport {
    pub device: PathBuf,
    pub policy: String,
    pub policy_id: u64,
    pub effect: EffectType,
    pub scope: ResolvedScope,
    pub cost_primary: u64,
    pub cost_secondary: u64,
    pub result: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelGateReport {
    pub device: PathBuf,
    pub subsystem: String,
    pub enabled: bool,
}

pub fn parse_manifest_file(path: &Path) -> ContractResult<ManifestDocument> {
    let text = fs::read_to_string(path)?;
    parse_manifest_str(&text, path.extension().and_then(|ext| ext.to_str()))
}

pub fn parse_manifest_str(text: &str, extension: Option<&str>) -> ContractResult<ManifestDocument> {
    if matches!(extension, Some("json")) {
        serde_json::from_str(text).map_err(|err| ContractError::Parse(err.to_string()))
    } else {
        serde_yaml::from_str(text).map_err(|err| ContractError::Parse(err.to_string()))
    }
}

pub fn validate_manifest(doc: &ManifestDocument) -> ContractResult<()> {
    match doc {
        ManifestDocument::Contract(manifest) => validate_contract_manifest(manifest),
        ManifestDocument::Composition(manifest) => validate_composition_manifest(manifest),
    }
}

pub fn validate_contract_manifest(manifest: &ContractManifest) -> ContractResult<()> {
    if manifest.policy.trim().is_empty() {
        return Err(ContractError::Validation(
            "policy name is empty".to_string(),
        ));
    }
    if manifest.subsystem.trim().is_empty() {
        return Err(ContractError::Validation("subsystem is empty".to_string()));
    }
    if manifest.scope.id.trim().is_empty() {
        return Err(ContractError::Validation("scope id is empty".to_string()));
    }
    if manifest.effects.is_empty() {
        return Err(ContractError::Validation(
            "manifest has no effects".to_string(),
        ));
    }

    for effect in &manifest.effects {
        if EffectType::from_manifest_name(&effect.name).is_none() {
            return Err(ContractError::Validation(format!(
                "unsupported effect '{}'",
                effect.name
            )));
        }
        if effect.budget.is_empty() {
            return Err(ContractError::Validation(format!(
                "effect '{}' has no budget",
                effect.name
            )));
        }
        let degrade = effect.degrade.as_ref().ok_or_else(|| {
            ContractError::Validation(format!("effect '{}' has no degrade/fallback", effect.name))
        })?;
        validate_degrade(effect, degrade)?;
    }

    Ok(())
}

fn validate_degrade(effect: &EffectSpec, degrade: &DegradeSpec) -> ContractResult<()> {
    let known = known_degrade_actions();
    let levels = [
        degrade.level1.as_deref(),
        degrade.level2.as_deref(),
        degrade.level3.as_deref(),
    ];

    if levels.iter().all(|level| level.is_none()) {
        return Err(ContractError::Validation(format!(
            "effect '{}' has empty degrade/fallback actions",
            effect.name
        )));
    }

    for action in levels.into_iter().flatten() {
        if !known.contains(action) {
            return Err(ContractError::Validation(format!(
                "effect '{}' uses unknown degrade/fallback action '{}'",
                effect.name, action
            )));
        }
    }

    Ok(())
}

pub fn validate_composition_manifest(manifest: &CompositionManifest) -> ContractResult<()> {
    let composition = &manifest.composition;
    if composition.scope.trim().is_empty() {
        return Err(ContractError::Validation(
            "composition scope is empty".to_string(),
        ));
    }
    if composition.coupled_effects.len() < 2 {
        return Err(ContractError::Validation(
            "composition needs at least two coupled effects".to_string(),
        ));
    }
    for effect in &composition.coupled_effects {
        if EffectType::from_manifest_name(effect).is_none() {
            return Err(ContractError::Validation(format!(
                "composition uses unsupported effect '{}'",
                effect
            )));
        }
    }
    if composition.invariant.is_empty() && composition.violation.is_none() {
        return Err(ContractError::Validation(
            "composition has no invariant or violation rule".to_string(),
        ));
    }
    Ok(())
}

pub fn known_degrade_actions() -> BTreeSet<&'static str> {
    BTreeSet::from([
        "throttle_boost",
        "revoke_boost",
        "disable_scheduler",
        "drain_dsq",
        "revoke_dispatch_modification",
        "throttle_demote",
        "revoke_demote",
        "kernel_default_reclaim",
        "ignore_hint",
        "revoke_reclaim_hint",
        "disable_policy",
        "fallback",
        "no_op",
    ])
}

pub fn effect_tokens(manifest: &ContractManifest) -> Vec<EffectToken> {
    let scope = ScopeId {
        scope_type: manifest.scope.scope_type.clone(),
        primary_id: manifest.scope.id.clone(),
        secondary_id: manifest
            .scope
            .memcg_path
            .as_ref()
            .map(|p| p.display().to_string()),
    };

    manifest
        .effects
        .iter()
        .filter_map(|effect| {
            EffectType::from_manifest_name(&effect.name).map(|effect_type| EffectToken {
                policy: manifest.policy.clone(),
                effect: effect_type,
                scope: scope.clone(),
            })
        })
        .collect()
}

pub fn resolve_scope(spec: &ScopeSpec, cgroup_root: &Path) -> ContractResult<ResolvedScope> {
    let label = spec.id.clone();
    let default_path = cgroup_root.join(&spec.id);
    let cgroup_path = match spec.scope_type.as_str() {
        "cgroup" | "service" => Some(
            spec.cgroup_path
                .clone()
                .unwrap_or_else(|| default_path.clone()),
        ),
        _ => spec.cgroup_path.clone(),
    };
    let memcg_path = match spec.scope_type.as_str() {
        "memcg" | "service" => Some(spec.memcg_path.clone().unwrap_or(default_path)),
        _ => spec.memcg_path.clone(),
    };

    let cgroup_id = optional_inode(cgroup_path.as_deref())?;
    let memcg_id = optional_inode(memcg_path.as_deref())?;

    Ok(ResolvedScope {
        label,
        scope_type: spec.scope_type.clone(),
        cgroup_path,
        cgroup_id,
        memcg_path,
        memcg_id,
        numa_node: spec.numa_node,
        service_tag: spec.service_tag,
    })
}

fn optional_inode(path: Option<&Path>) -> ContractResult<Option<u64>> {
    match path {
        Some(path) if path.exists() => Ok(Some(path_identity(path)?)),
        Some(_) | None => Ok(None),
    }
}

#[cfg(unix)]
fn path_identity(path: &Path) -> ContractResult<u64> {
    use std::os::unix::fs::MetadataExt;
    Ok(fs::metadata(path)?.ino())
}

#[cfg(not(unix))]
fn path_identity(path: &Path) -> ContractResult<u64> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    path.display().to_string().hash(&mut hasher);
    Ok(hasher.finish())
}

pub fn state_file(state_dir: &Path) -> PathBuf {
    state_dir.join("state.json")
}

pub fn load_state(state_dir: &Path) -> ContractResult<StateStore> {
    let path = state_file(state_dir);
    if !path.exists() {
        return Ok(StateStore::default());
    }
    let text = fs::read_to_string(&path)?;
    serde_json::from_str(&text).map_err(|err| ContractError::State(err.to_string()))
}

pub fn save_state(state_dir: &Path, state: &StateStore) -> ContractResult<()> {
    fs::create_dir_all(state_dir)?;
    let path = state_file(state_dir);
    let text =
        serde_json::to_string_pretty(state).map_err(|err| ContractError::State(err.to_string()))?;
    fs::write(path, text)?;
    Ok(())
}

pub fn install_policy(
    state_dir: &Path,
    manifest_path: &Path,
    manifest: ContractManifest,
    resolved_scope: ResolvedScope,
) -> ContractResult<InstalledPolicy> {
    let mut state = load_state(state_dir)?;
    let installed = InstalledPolicy {
        manifest_path: manifest_path.to_path_buf(),
        loaded_at_unix: now_unix(),
        resolved_scope,
        manifest,
    };
    state
        .policies
        .insert(installed.manifest.policy.clone(), installed.clone());
    save_state(state_dir, &state)?;
    Ok(installed)
}

pub fn unload_policy(state_dir: &Path, policy: &str) -> ContractResult<bool> {
    let mut state = load_state(state_dir)?;
    let removed = state.policies.remove(policy).is_some();
    save_state(state_dir, &state)?;
    Ok(removed)
}

pub fn record_manual_degrade(
    state_dir: &Path,
    policy: String,
    effect: String,
    scope: String,
) -> ContractResult<ManualDegrade> {
    if EffectType::from_manifest_name(&effect).is_none() {
        return Err(ContractError::Validation(format!(
            "unsupported effect '{}'",
            effect
        )));
    }
    let mut state = load_state(state_dir)?;
    let event = ManualDegrade {
        policy,
        effect,
        scope,
        recorded_at_unix: now_unix(),
    };
    state.manual_degrades.push(event.clone());
    save_state(state_dir, &state)?;
    Ok(event)
}

pub fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn parse_key_value_snapshot(text: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for line in text.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        out.insert(key.trim().to_string(), value.trim().to_string());
    }
    out
}

pub fn ledger_from_snapshots(snapshots: &[BTreeMap<String, String>]) -> LedgerSnapshot {
    let mut ledger = LedgerSnapshot::default();
    for snapshot in snapshots {
        ledger.sched_dispatch_events += snapshot_u64(snapshot, "sched_dispatch_events");
        ledger.sched_boost_events += snapshot_u64(snapshot, "sched_boost_events");
        ledger.sched_queue_delay_us += snapshot_u64(snapshot, "sched_queue_delay_us");
        ledger.pages_demoted += snapshot_u64(snapshot, "pages_demoted");
        ledger.reclaim_hints += snapshot_u64(snapshot, "reclaim_hints");
        ledger.refault_events += snapshot_u64(snapshot, "refault_events");
        ledger.major_fault_events += snapshot_u64(snapshot, "major_fault_events");
        ledger.fault_latency_us += snapshot_u64(snapshot, "fault_latency_us");
        ledger.violations += snapshot_u64(snapshot, "violations");
        ledger.sched_degrade_state = ledger.sched_degrade_state.max(
            snapshot_u64(snapshot, "sched_degrade_state")
                .max(snapshot_u64(snapshot, "boost_degrade_state")),
        );
        ledger.demote_degrade_state = ledger
            .demote_degrade_state
            .max(snapshot_u64(snapshot, "demote_degrade_state"));
    }
    ledger
}

fn snapshot_u64(snapshot: &BTreeMap<String, String>, key: &str) -> u64 {
    snapshot
        .get(key)
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or_default()
}

pub fn load_debugfs_snapshots(debugfs_root: &Path) -> Vec<BTreeMap<String, String>> {
    ["sched_snapshot", "mm_snapshot", "cross_snapshot"]
        .iter()
        .filter_map(|name| fs::read_to_string(debugfs_root.join(name)).ok())
        .map(|text| parse_key_value_snapshot(&text))
        .collect()
}

pub fn status_json(state_dir: &Path, debugfs_root: &Path) -> ContractResult<serde_json::Value> {
    let state = load_state(state_dir)?;
    let snapshots = load_debugfs_snapshots(debugfs_root);
    Ok(json!({
        "state_dir": state_dir,
        "debugfs_root": debugfs_root,
        "debugfs_available": debugfs_root.is_dir(),
        "installed_policy_count": state.policies.len(),
        "policies": state.policies,
        "manual_degrades": state.manual_degrades,
        "ledger": ledger_from_snapshots(&snapshots),
    }))
}

pub fn stable_nonzero_id(input: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in input.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    if hash == 0 {
        1
    } else {
        hash
    }
}

#[cfg(target_os = "linux")]
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
struct KernelIoctlScope {
    scope_type: u32,
    reserved: u32,
    primary_id: u64,
    secondary_id: u64,
}

#[cfg(target_os = "linux")]
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
struct KernelIoctlToken {
    prog_id: u64,
    effect: u32,
    reserved: u32,
    scope: KernelIoctlScope,
    budget_primary: u64,
    budget_secondary: u64,
    epoch_ns: u64,
    degrade_state: u32,
    reserved2: u32,
}

#[cfg(target_os = "linux")]
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
struct KernelIoctlCharge {
    prog_id: u64,
    effect: u32,
    reserved: u32,
    scope: KernelIoctlScope,
    cost_primary: u64,
    cost_secondary: u64,
    result: i32,
    reserved2: u32,
}

#[cfg(target_os = "linux")]
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
struct KernelIoctlGate {
    subsystem: u32,
    enabled: u32,
    reserved: u32,
    reserved2: u32,
}

#[cfg(target_os = "linux")]
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
struct KernelIoctlSnapshot {
    scope: KernelIoctlScope,
    sched_queue_delay_us: u64,
    sched_dispatch_events: u64,
    sched_dispatch_failures: u64,
    sched_boost_events: u64,
    pages_demoted: u64,
    reclaim_hints: u64,
    refault_events: u64,
    major_fault_events: u64,
    fault_latency_us: u64,
    violations: u64,
    degrade_state: [u32; 6],
}

#[cfg(target_os = "linux")]
const IOC_NRBITS: u64 = 8;
#[cfg(target_os = "linux")]
const IOC_TYPEBITS: u64 = 8;
#[cfg(target_os = "linux")]
const IOC_SIZEBITS: u64 = 14;
#[cfg(target_os = "linux")]
const IOC_NRSHIFT: u64 = 0;
#[cfg(target_os = "linux")]
const IOC_TYPESHIFT: u64 = IOC_NRSHIFT + IOC_NRBITS;
#[cfg(target_os = "linux")]
const IOC_SIZESHIFT: u64 = IOC_TYPESHIFT + IOC_TYPEBITS;
#[cfg(target_os = "linux")]
const IOC_DIRSHIFT: u64 = IOC_SIZESHIFT + IOC_SIZEBITS;
#[cfg(target_os = "linux")]
const IOC_WRITE: u64 = 1;
#[cfg(target_os = "linux")]
const IOC_READ: u64 = 2;
#[cfg(target_os = "linux")]
const CONTRACTBPF_IOC_MAGIC: u64 = 0xcb;

#[cfg(target_os = "linux")]
const fn ioc(dir: u64, type_: u64, nr: u64, size: u64) -> libc::c_ulong {
    ((dir << IOC_DIRSHIFT)
        | (type_ << IOC_TYPESHIFT)
        | (nr << IOC_NRSHIFT)
        | (size << IOC_SIZESHIFT)) as libc::c_ulong
}

#[cfg(target_os = "linux")]
const CONTRACTBPF_IOC_INSTALL_TOKEN: libc::c_ulong = ioc(
    IOC_WRITE,
    CONTRACTBPF_IOC_MAGIC,
    1,
    std::mem::size_of::<KernelIoctlToken>() as u64,
);

#[cfg(target_os = "linux")]
const CONTRACTBPF_IOC_GET_LEDGER: libc::c_ulong = ioc(
    IOC_READ | IOC_WRITE,
    CONTRACTBPF_IOC_MAGIC,
    2,
    std::mem::size_of::<KernelIoctlSnapshot>() as u64,
);

#[cfg(target_os = "linux")]
const CONTRACTBPF_IOC_RESET_TEST: libc::c_ulong = ioc(0, CONTRACTBPF_IOC_MAGIC, 3, 0);

#[cfg(target_os = "linux")]
const CONTRACTBPF_IOC_CHARGE_EFFECT: libc::c_ulong = ioc(
    IOC_READ | IOC_WRITE,
    CONTRACTBPF_IOC_MAGIC,
    4,
    std::mem::size_of::<KernelIoctlCharge>() as u64,
);

#[cfg(target_os = "linux")]
const CONTRACTBPF_IOC_SET_GATE: libc::c_ulong = ioc(
    IOC_WRITE,
    CONTRACTBPF_IOC_MAGIC,
    5,
    std::mem::size_of::<KernelIoctlGate>() as u64,
);

#[cfg(target_os = "linux")]
pub fn install_manifest_tokens_via_device(
    device: &Path,
    manifest: &ContractManifest,
    resolved_scope: &ResolvedScope,
) -> ContractResult<KernelInstallReport> {
    use std::os::fd::AsRawFd;

    let file = OpenOptions::new().read(true).write(true).open(device)?;
    let fd = file.as_raw_fd();
    let policy_id = stable_nonzero_id(&manifest.policy);
    let scope = ioctl_scope(resolved_scope);
    let mut installed_tokens = 0usize;

    for effect in &manifest.effects {
        let effect_type = EffectType::from_manifest_name(&effect.name).ok_or_else(|| {
            ContractError::Validation(format!("unsupported effect '{}'", effect.name))
        })?;
        let mut token = KernelIoctlToken {
            prog_id: policy_id,
            effect: effect_type.ioctl_value(),
            scope,
            budget_primary: primary_budget(effect_type, effect),
            budget_secondary: secondary_budget(effect_type, effect),
            epoch_ns: 1_000_000_000,
            degrade_state: effect
                .degrade
                .as_ref()
                .and_then(|degrade| degrade.level1.as_deref())
                .map(degrade_action_value)
                .unwrap_or_default(),
            ..KernelIoctlToken::default()
        };

        let ret = unsafe {
            libc::ioctl(
                fd,
                CONTRACTBPF_IOC_INSTALL_TOKEN,
                &mut token as *mut KernelIoctlToken,
            )
        };
        if ret < 0 {
            return Err(ContractError::Io(
                std::io::Error::last_os_error().to_string(),
            ));
        }
        installed_tokens += 1;
    }

    Ok(KernelInstallReport {
        device: device.to_path_buf(),
        policy_id,
        installed_tokens,
    })
}

#[cfg(target_os = "linux")]
pub fn set_manifest_gate_via_device(
    device: &Path,
    manifest: &ContractManifest,
    enabled: bool,
) -> ContractResult<Option<KernelGateReport>> {
    use std::os::fd::AsRawFd;

    let (subsystem, subsystem_id) = match manifest.subsystem.as_str() {
        "sched" | "sched_ext" => ("sched_ext", 1),
        "mm" | "paging" => ("mm", 2),
        _ => return Ok(None),
    };
    let file = OpenOptions::new().read(true).write(true).open(device)?;
    let fd = file.as_raw_fd();
    let mut gate = KernelIoctlGate {
        subsystem: subsystem_id,
        enabled: if enabled { 1 } else { 0 },
        ..KernelIoctlGate::default()
    };

    let ret = unsafe {
        libc::ioctl(
            fd,
            CONTRACTBPF_IOC_SET_GATE,
            &mut gate as *mut KernelIoctlGate,
        )
    };
    if ret < 0 {
        return Err(ContractError::Io(
            std::io::Error::last_os_error().to_string(),
        ));
    }

    Ok(Some(KernelGateReport {
        device: device.to_path_buf(),
        subsystem: subsystem.to_string(),
        enabled,
    }))
}

#[cfg(not(target_os = "linux"))]
pub fn set_manifest_gate_via_device(
    _device: &Path,
    _manifest: &ContractManifest,
    _enabled: bool,
) -> ContractResult<Option<KernelGateReport>> {
    Err(ContractError::Io(
        "contractbpf ioctl device is only supported on Linux".to_string(),
    ))
}

#[cfg(not(target_os = "linux"))]
pub fn install_manifest_tokens_via_device(
    _device: &Path,
    _manifest: &ContractManifest,
    _resolved_scope: &ResolvedScope,
) -> ContractResult<KernelInstallReport> {
    Err(ContractError::Io(
        "contractbpf ioctl device is only supported on Linux".to_string(),
    ))
}

#[cfg(target_os = "linux")]
pub fn reset_device_for_tests(device: &Path) -> ContractResult<()> {
    use std::os::fd::AsRawFd;

    let file = OpenOptions::new().read(true).write(true).open(device)?;
    let ret = unsafe { libc::ioctl(file.as_raw_fd(), CONTRACTBPF_IOC_RESET_TEST) };
    if ret < 0 {
        return Err(ContractError::Io(
            std::io::Error::last_os_error().to_string(),
        ));
    }
    Ok(())
}

#[cfg(not(target_os = "linux"))]
pub fn reset_device_for_tests(_device: &Path) -> ContractResult<()> {
    Err(ContractError::Io(
        "contractbpf ioctl device is only supported on Linux".to_string(),
    ))
}

#[cfg(target_os = "linux")]
pub fn charge_effect_via_device(
    device: &Path,
    policy: &str,
    effect_name: &str,
    resolved_scope: &ResolvedScope,
    cost_primary: u64,
    cost_secondary: u64,
) -> ContractResult<KernelChargeReport> {
    use std::os::fd::AsRawFd;

    let effect = EffectType::from_manifest_name(effect_name).ok_or_else(|| {
        ContractError::Validation(format!("unsupported effect '{}'", effect_name))
    })?;
    let file = OpenOptions::new().read(true).write(true).open(device)?;
    let fd = file.as_raw_fd();
    let policy_id = stable_nonzero_id(policy);
    let mut charge = KernelIoctlCharge {
        prog_id: policy_id,
        effect: effect.ioctl_value(),
        scope: ioctl_scope(resolved_scope),
        cost_primary,
        cost_secondary,
        ..KernelIoctlCharge::default()
    };

    let ret = unsafe {
        libc::ioctl(
            fd,
            CONTRACTBPF_IOC_CHARGE_EFFECT,
            &mut charge as *mut KernelIoctlCharge,
        )
    };
    if ret < 0 {
        return Err(ContractError::Io(
            std::io::Error::last_os_error().to_string(),
        ));
    }

    Ok(KernelChargeReport {
        device: device.to_path_buf(),
        policy: policy.to_string(),
        policy_id,
        effect,
        scope: resolved_scope.clone(),
        cost_primary,
        cost_secondary,
        result: charge.result,
    })
}

#[cfg(not(target_os = "linux"))]
pub fn charge_effect_via_device(
    _device: &Path,
    _policy: &str,
    _effect_name: &str,
    _resolved_scope: &ResolvedScope,
    _cost_primary: u64,
    _cost_secondary: u64,
) -> ContractResult<KernelChargeReport> {
    Err(ContractError::Io(
        "contractbpf ioctl device is only supported on Linux".to_string(),
    ))
}

#[cfg(target_os = "linux")]
pub fn read_ledger_via_device(
    device: &Path,
    resolved_scope: &ResolvedScope,
) -> ContractResult<LedgerSnapshot> {
    use std::os::fd::AsRawFd;

    let file = OpenOptions::new().read(true).write(true).open(device)?;
    let fd = file.as_raw_fd();
    let mut snap = KernelIoctlSnapshot {
        scope: ioctl_scope(resolved_scope),
        ..KernelIoctlSnapshot::default()
    };
    let ret = unsafe {
        libc::ioctl(
            fd,
            CONTRACTBPF_IOC_GET_LEDGER,
            &mut snap as *mut KernelIoctlSnapshot,
        )
    };
    if ret < 0 {
        return Err(ContractError::Io(
            std::io::Error::last_os_error().to_string(),
        ));
    }

    Ok(LedgerSnapshot {
        sched_dispatch_events: snap.sched_dispatch_events,
        sched_boost_events: snap.sched_boost_events,
        sched_queue_delay_us: snap.sched_queue_delay_us,
        pages_demoted: snap.pages_demoted,
        reclaim_hints: snap.reclaim_hints,
        refault_events: snap.refault_events,
        major_fault_events: snap.major_fault_events,
        fault_latency_us: snap.fault_latency_us,
        violations: snap.violations,
        sched_degrade_state: u64::from(
            snap.degrade_state[EffectType::SchedBoost.ioctl_value() as usize],
        ),
        demote_degrade_state: u64::from(
            snap.degrade_state[EffectType::MmDemotePage.ioctl_value() as usize],
        ),
    })
}

#[cfg(not(target_os = "linux"))]
pub fn read_ledger_via_device(
    _device: &Path,
    _resolved_scope: &ResolvedScope,
) -> ContractResult<LedgerSnapshot> {
    Err(ContractError::Io(
        "contractbpf ioctl device is only supported on Linux".to_string(),
    ))
}

impl EffectType {
    fn ioctl_value(self) -> u32 {
        match self {
            Self::SchedBoost => 0,
            Self::SchedDispatch => 1,
            Self::SchedPinCpu => 2,
            Self::MmDemotePage => 3,
            Self::MmReclaimHint => 4,
            Self::MmClassifyRegion => 5,
        }
    }
}

#[cfg(target_os = "linux")]
fn ioctl_scope(resolved: &ResolvedScope) -> KernelIoctlScope {
    let scope_type = match resolved.scope_type.as_str() {
        "service" | "cgroup" | "memcg" => 1,
        _ => 0,
    };
    let primary_id = resolved
        .cgroup_id
        .or(resolved.memcg_id)
        .or(resolved.service_tag)
        .unwrap_or_else(|| stable_nonzero_id(&resolved.label));
    let secondary_id = match (resolved.cgroup_id, resolved.memcg_id) {
        (Some(cgroup_id), Some(memcg_id)) if cgroup_id != memcg_id => memcg_id,
        _ => 0,
    };

    KernelIoctlScope {
        scope_type,
        reserved: 0,
        primary_id,
        secondary_id,
    }
}

fn primary_budget(effect_type: EffectType, effect: &EffectSpec) -> u64 {
    match effect_type {
        EffectType::SchedBoost => budget_u64(effect, "max_boosts_per_epoch"),
        EffectType::SchedDispatch => budget_u64(effect, "max_dispatch_failures_per_epoch"),
        EffectType::MmDemotePage => budget_u64(effect, "max_pages_per_epoch"),
        EffectType::MmReclaimHint => budget_u64(effect, "max_hints_per_epoch"),
        EffectType::SchedPinCpu | EffectType::MmClassifyRegion => 0,
    }
}

fn secondary_budget(effect_type: EffectType, effect: &EffectSpec) -> u64 {
    match effect_type {
        EffectType::SchedBoost => budget_u64(effect, "max_queue_delay_us"),
        EffectType::SchedDispatch => budget_u64(effect, "max_starvation_window_us"),
        EffectType::MmDemotePage => budget_u64(effect, "max_fault_latency_us"),
        EffectType::MmReclaimHint | EffectType::SchedPinCpu | EffectType::MmClassifyRegion => 0,
    }
}

fn budget_u64(effect: &EffectSpec, key: &str) -> u64 {
    effect
        .budget
        .get(key)
        .and_then(|value| match value {
            serde_yaml::Value::Number(number) => number.as_u64().or_else(|| {
                number
                    .as_f64()
                    .filter(|value| *value >= 0.0)
                    .map(|value| value as u64)
            }),
            serde_yaml::Value::String(text) => text.parse::<u64>().ok(),
            _ => None,
        })
        .unwrap_or_default()
}

fn degrade_action_value(action: &str) -> u32 {
    match action {
        "throttle_boost" | "throttle_demote" | "ignore_hint" | "drain_dsq" => 1,
        "revoke_boost"
        | "revoke_demote"
        | "revoke_reclaim_hint"
        | "revoke_dispatch_modification" => 2,
        "kernel_default_reclaim" | "fallback" => 3,
        "disable_scheduler" | "disable_policy" => 4,
        _ => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_good_manifest() {
        let doc = parse_manifest_str(
            r#"
policy: latency_sched_A
subsystem: sched_ext
scope:
  type: cgroup
  id: service-A
effects:
  - name: boost_task
    budget:
      max_boosts_per_epoch: 1
    degrade:
      level1: throttle_boost
"#,
            Some("yaml"),
        )
        .unwrap();
        validate_manifest(&doc).unwrap();
    }

    #[test]
    fn rejects_missing_degrade() {
        let doc = parse_manifest_str(
            r#"
policy: bad
subsystem: mm
scope:
  type: memcg
  id: service-A
effects:
  - name: demote_page
    budget:
      max_pages_per_epoch: 1
"#,
            Some("yaml"),
        )
        .unwrap();
        assert!(validate_manifest(&doc).is_err());
    }
}
