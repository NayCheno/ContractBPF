#![allow(dead_code)]

use std::fs;
use std::path::Path;
use std::process::ExitCode;

use libcontract::{EffectToken, EffectType, ScopeId};

mod degrade;
mod event;
mod ledger;
mod manifest;
mod scope;
mod token;

const CONTRACTBPF_DEBUGFS: &str = "/sys/kernel/debug/contractbpf";
const CGROUP_CONTROLLERS: &str = "/sys/fs/cgroup/cgroup.controllers";

fn service_a_tokens() -> Vec<EffectToken> {
    let scope = ScopeId {
        scope_type: "service".to_string(),
        primary_id: "service-A".to_string(),
        secondary_id: None,
    };

    vec![
        EffectToken {
            policy: "latency_sched_A".to_string(),
            effect: EffectType::SchedBoost,
            scope: scope.clone(),
        },
        EffectToken {
            policy: "phase_paging_A".to_string(),
            effect: EffectType::MmDemotePage,
            scope: scope.clone(),
        },
        EffectToken {
            policy: "phase_paging_A".to_string(),
            effect: EffectType::MmReclaimHint,
            scope,
        },
    ]
}

fn read_optional_debugfs(name: &str) -> Option<String> {
    let path = Path::new(CONTRACTBPF_DEBUGFS).join(name);
    fs::read_to_string(path).ok()
}

fn require_memory_controller() -> Result<String, String> {
    let controllers = fs::read_to_string(CGROUP_CONTROLLERS)
        .map_err(|err| format!("failed to read {CGROUP_CONTROLLERS}: {err}"))?;

    if controllers.split_whitespace().any(|controller| controller == "memory") {
        Ok(controllers)
    } else {
        Err(format!("memory controller missing from {CGROUP_CONTROLLERS}: {controllers}"))
    }
}

fn main() -> ExitCode {
    let root = Path::new(CONTRACTBPF_DEBUGFS);

    if !root.is_dir() {
        eprintln!("contractd: ContractBPF debugfs not found at {CONTRACTBPF_DEBUGFS}");
        return ExitCode::from(1);
    }

    println!("contractd: debugfs={CONTRACTBPF_DEBUGFS}");
    match require_memory_controller() {
        Ok(controllers) => println!("contractd: cgroup.controllers={}", controllers.trim()),
        Err(err) => {
            eprintln!("contractd: {err}");
            return ExitCode::from(1);
        }
    }

    for token in service_a_tokens() {
        println!(
            "contractd: token policy={} effect={:?} scope={}:{}",
            token.policy, token.effect, token.scope.scope_type, token.scope.primary_id
        );
    }

    for entry in ["selftest", "sched_snapshot", "mm_snapshot"] {
        match read_optional_debugfs(entry) {
            Some(contents) => {
                let first_line = contents.lines().next().unwrap_or("");
                println!("contractd: {entry}: {first_line}");
            }
            None => println!("contractd: {entry}: unavailable"),
        }
    }

    println!("CONTRACTBPF_CONTRACTD_OK");
    ExitCode::SUCCESS
}
