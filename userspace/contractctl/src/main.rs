use libcontract::{
    charge_effect_via_device, effect_tokens, install_policy, ledger_from_snapshots,
    load_debugfs_snapshots, load_state, parse_manifest_file, read_ledger_via_device,
    record_manual_degrade, reset_device_for_tests, resolve_scope, save_state,
    set_manifest_gate_via_device, status_json, unload_policy, validate_manifest, EffectType,
    LedgerSnapshot, ManifestDocument, ScopeSpec,
};
use std::env;
use std::path::PathBuf;
use std::process::ExitCode;
use std::thread;
use std::time::Duration;

#[derive(Debug)]
struct GlobalOptions {
    state_dir: PathBuf,
    debugfs_root: PathBuf,
    cgroup_root: PathBuf,
    device: PathBuf,
}

impl Default for GlobalOptions {
    fn default() -> Self {
        Self {
            state_dir: env::var("CONTRACTBPF_STATE_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from("/run/contractbpf")),
            debugfs_root: env::var("CONTRACTBPF_DEBUGFS")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from("/sys/kernel/debug/contractbpf")),
            cgroup_root: env::var("CONTRACTBPF_CGROUP_ROOT")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from("/sys/fs/cgroup")),
            device: env::var("CONTRACTBPF_DEVICE")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from("/dev/contractbpf")),
        }
    }
}

fn print_usage() {
    println!(
        "usage: contractctl [--state-dir DIR] [--debugfs-root DIR] [--cgroup-root DIR] [--device PATH] <command>\n\
         commands:\n\
           load POLICY.yaml|json [--dry-run]\n\
           gate POLICY.yaml|json --enable 0|1\n\
           unload POLICY\n\
           status\n\
           ledger [--scope NAME] [--format json|lines]\n\
           events [--follow]\n\
           charge --policy P --effect E --scope S [--primary N] [--secondary N]\n\
           degrade --policy P --effect E --scope S\n\
           resolve-scope --scope S [--type service|cgroup|memcg] [--cgroup PATH] [--memcg PATH]\n\
           reset --test-only"
    );
}

fn json_print(value: serde_json::Value) {
    println!("{}", serde_json::to_string_pretty(&value).unwrap());
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("contractctl: {err}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<(), String> {
    let mut opts = GlobalOptions::default();
    let mut args: Vec<String> = env::args().skip(1).collect();

    while args.first().is_some_and(|arg| arg.starts_with("--")) {
        let flag = args.remove(0);
        match flag.as_str() {
            "--state-dir" => opts.state_dir = PathBuf::from(take_arg(&mut args, "--state-dir")?),
            "--debugfs-root" => {
                opts.debugfs_root = PathBuf::from(take_arg(&mut args, "--debugfs-root")?)
            }
            "--cgroup-root" => {
                opts.cgroup_root = PathBuf::from(take_arg(&mut args, "--cgroup-root")?)
            }
            "--device" => opts.device = PathBuf::from(take_arg(&mut args, "--device")?),
            "-h" | "--help" => {
                print_usage();
                return Ok(());
            }
            _ => return Err(format!("unknown global flag '{flag}'")),
        }
    }

    let Some(command) = args.first().cloned() else {
        print_usage();
        return Ok(());
    };
    args.remove(0);

    match command.as_str() {
        "load" => cmd_load(&opts, args),
        "gate" => cmd_gate(&opts, args),
        "unload" => cmd_unload(&opts, args),
        "status" => cmd_status(&opts),
        "ledger" => cmd_ledger(&opts, args),
        "events" => cmd_events(&opts, args),
        "charge" => cmd_charge(&opts, args),
        "degrade" => cmd_degrade(&opts, args),
        "resolve-scope" => cmd_resolve_scope(&opts, args),
        "reset" => cmd_reset(&opts, args),
        "-h" | "--help" => {
            print_usage();
            Ok(())
        }
        _ => Err(format!("unknown command '{command}'")),
    }
}

fn take_arg(args: &mut Vec<String>, flag: &str) -> Result<String, String> {
    if args.is_empty() {
        return Err(format!("{flag} needs a value"));
    }
    Ok(args.remove(0))
}

fn cmd_load(opts: &GlobalOptions, mut args: Vec<String>) -> Result<(), String> {
    let dry_run = remove_flag(&mut args, "--dry-run");
    let manifest_path = PathBuf::from(args.first().ok_or("load needs a manifest path")?);
    let doc = parse_manifest_file(&manifest_path).map_err(|err| err.to_string())?;
    validate_manifest(&doc).map_err(|err| err.to_string())?;

    match doc {
        ManifestDocument::Contract(contract) => {
            let resolved =
                resolve_scope(&contract.scope, &opts.cgroup_root).map_err(|err| err.to_string())?;
            let tokens = effect_tokens(&contract);
            if dry_run {
                json_print(serde_json::json!({
                    "status": "dry_run_ok",
                    "policy": contract.policy,
                    "tokens": tokens,
                    "resolved_scope": resolved,
                    "kernel_install_channel": "pending_contractbpf_device_or_netlink",
                }));
            } else {
                let installed = install_policy(&opts.state_dir, &manifest_path, contract, resolved)
                    .map_err(|err| err.to_string())?;
                let kernel_install = if opts.device.exists() {
                    match libcontract::install_manifest_tokens_via_device(
                        &opts.device,
                        &installed.manifest,
                        &installed.resolved_scope,
                    ) {
                        Ok(report) => {
                            let gate = match set_manifest_gate_via_device(
                                &opts.device,
                                &installed.manifest,
                                true,
                            ) {
                                Ok(report) => serde_json::json!(report),
                                Err(err) => serde_json::json!({
                                    "error": err.to_string(),
                                }),
                            };
                            serde_json::json!({
                                "channel": "ioctl",
                                "report": report,
                                "gate": gate,
                            })
                        }
                        Err(err) => serde_json::json!({
                            "channel": "ioctl",
                            "error": err.to_string(),
                        }),
                    }
                } else {
                    serde_json::json!({
                        "channel": "state_only",
                        "device": opts.device,
                        "reason": "device_missing",
                    })
                };
                json_print(serde_json::json!({
                    "status": "loaded",
                    "policy": installed.manifest.policy,
                    "tokens": tokens,
                    "resolved_scope": installed.resolved_scope,
                    "state_dir": opts.state_dir,
                    "kernel_install": kernel_install,
                }));
            }
        }
        ManifestDocument::Composition(composition) => {
            json_print(serde_json::json!({
                "status": "composition_static_check_ok",
                "composition": composition,
            }));
        }
    }

    Ok(())
}

fn cmd_unload(opts: &GlobalOptions, args: Vec<String>) -> Result<(), String> {
    let policy = args.first().ok_or("unload needs a policy name")?;
    let removed = unload_policy(&opts.state_dir, policy).map_err(|err| err.to_string())?;
    json_print(serde_json::json!({
        "status": if removed { "unloaded" } else { "not_found" },
        "policy": policy,
    }));
    Ok(())
}

fn cmd_gate(opts: &GlobalOptions, mut args: Vec<String>) -> Result<(), String> {
    let enabled = match flag_value(&mut args, "--enable")?.as_str() {
        "1" | "true" | "on" | "yes" => true,
        "0" | "false" | "off" | "no" => false,
        value => return Err(format!("invalid --enable value '{value}'")),
    };
    let manifest_path = PathBuf::from(args.first().ok_or("gate needs a manifest path")?);
    let doc = parse_manifest_file(&manifest_path).map_err(|err| err.to_string())?;
    let ManifestDocument::Contract(contract) = doc else {
        return Err("gate needs a contract manifest, not a composition".to_string());
    };
    validate_manifest(&ManifestDocument::Contract(contract.clone()))
        .map_err(|err| err.to_string())?;
    if !opts.device.exists() {
        return Err(format!("device missing: {}", opts.device.display()));
    }

    let report = set_manifest_gate_via_device(&opts.device, &contract, enabled)
        .map_err(|err| err.to_string())?;
    json_print(serde_json::json!({
        "status": "gate_set",
        "policy": contract.policy,
        "gate": report,
    }));
    Ok(())
}

fn cmd_status(opts: &GlobalOptions) -> Result<(), String> {
    let mut status =
        status_json(&opts.state_dir, &opts.debugfs_root).map_err(|err| err.to_string())?;
    if let Some(object) = status.as_object_mut() {
        object.insert("device".to_string(), serde_json::json!(opts.device));
        object.insert(
            "device_available".to_string(),
            serde_json::json!(opts.device.exists()),
        );
    }
    json_print(status);
    Ok(())
}

fn cmd_ledger(opts: &GlobalOptions, args: Vec<String>) -> Result<(), String> {
    let mut scope = None;
    let mut format = "json".to_string();
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--scope" => scope = iter.next(),
            "--format" => format = iter.next().ok_or("--format needs a value")?,
            _ => return Err(format!("unknown ledger flag '{arg}'")),
        }
    }
    let snapshots = load_debugfs_snapshots(&opts.debugfs_root);
    let state = load_state(&opts.state_dir).map_err(|err| err.to_string())?;
    let device_ledgers: Vec<_> = if opts.device.exists() {
        state
            .policies
            .values()
            .filter(|policy| {
                scope
                    .as_ref()
                    .map(|scope| policy.resolved_scope.label == *scope)
                    .unwrap_or(true)
            })
            .filter_map(|policy| {
                read_ledger_via_device(&opts.device, &policy.resolved_scope)
                    .ok()
                    .map(|ledger| {
                        serde_json::json!({
                            "policy": policy.manifest.policy,
                            "scope": policy.resolved_scope,
                            "ledger": ledger,
                        })
                    })
            })
            .collect()
    } else {
        Vec::new()
    };
    let effect_ledgers: Vec<_> = if opts.device.exists() {
        state
            .policies
            .values()
            .filter(|policy| {
                scope
                    .as_ref()
                    .map(|scope| policy.resolved_scope.label == *scope)
                    .unwrap_or(true)
            })
            .flat_map(|policy| {
                let ledger = read_ledger_via_device(&opts.device, &policy.resolved_scope).ok();
                effect_tokens(&policy.manifest)
                    .into_iter()
                    .filter_map(move |token| {
                        ledger.as_ref().map(|ledger| {
                            serde_json::json!({
                                "policy": token.policy,
                                "effect": token.effect,
                                "scope": policy.resolved_scope,
                                "counters": effect_counters_json(token.effect, ledger),
                            })
                        })
                    })
            })
            .collect()
    } else {
        Vec::new()
    };
    if format == "lines" {
        let mut aggregate = LedgerSnapshot::default();
        if device_ledgers.is_empty() {
            aggregate = ledger_from_snapshots(&snapshots);
        } else {
            for entry in &device_ledgers {
                if let Some(ledger) = entry.get("ledger") {
                    let ledger: LedgerSnapshot =
                        serde_json::from_value(ledger.clone()).map_err(|err| err.to_string())?;
                    merge_ledger_max(&mut aggregate, &ledger);
                }
            }
        }
        print_ledger_lines(&aggregate);
        return Ok(());
    }
    if format != "json" {
        return Err(format!("unsupported ledger format '{format}'"));
    }
    json_print(serde_json::json!({
        "scope": scope,
        "debugfs_root": opts.debugfs_root,
        "device": opts.device,
        "device_available": opts.device.exists(),
        "snapshot_count": snapshots.len(),
        "ledger": ledger_from_snapshots(&snapshots),
        "device_ledgers": device_ledgers,
        "effect_ledgers": effect_ledgers,
        "raw_snapshots": snapshots,
    }));
    Ok(())
}

fn cmd_events(opts: &GlobalOptions, args: Vec<String>) -> Result<(), String> {
    let follow = args.iter().any(|arg| arg == "--follow");
    loop {
        let snapshots = load_debugfs_snapshots(&opts.debugfs_root);
        json_print(serde_json::json!({
            "event": "snapshot",
            "debugfs_root": opts.debugfs_root,
            "ledger": ledger_from_snapshots(&snapshots),
            "raw_snapshots": snapshots,
        }));
        if !follow {
            break;
        }
        thread::sleep(Duration::from_secs(1));
    }
    Ok(())
}

fn cmd_charge(opts: &GlobalOptions, mut args: Vec<String>) -> Result<(), String> {
    let policy = flag_value(&mut args, "--policy")?;
    let effect = flag_value(&mut args, "--effect")?;
    let scope = flag_value(&mut args, "--scope")?;
    let cost_primary = flag_value_optional(&mut args, "--primary")
        .unwrap_or_else(|| "1".to_string())
        .parse::<u64>()
        .map_err(|err| format!("invalid --primary: {err}"))?;
    let cost_secondary = flag_value_optional(&mut args, "--secondary")
        .unwrap_or_else(|| "0".to_string())
        .parse::<u64>()
        .map_err(|err| format!("invalid --secondary: {err}"))?;

    if !opts.device.exists() {
        return Err(format!("device missing: {}", opts.device.display()));
    }

    let state = load_state(&opts.state_dir).map_err(|err| err.to_string())?;
    let installed = state
        .policies
        .get(&policy)
        .ok_or_else(|| format!("policy not loaded: {policy}"))?;
    if installed.resolved_scope.label != scope {
        return Err(format!(
            "policy '{}' is loaded for scope '{}', not '{}'",
            policy, installed.resolved_scope.label, scope
        ));
    }

    let report = charge_effect_via_device(
        &opts.device,
        &policy,
        &effect,
        &installed.resolved_scope,
        cost_primary,
        cost_secondary,
    )
    .map_err(|err| err.to_string())?;

    json_print(serde_json::json!({
        "status": "charged",
        "charge": report,
    }));
    Ok(())
}

fn cmd_degrade(opts: &GlobalOptions, mut args: Vec<String>) -> Result<(), String> {
    let policy = flag_value(&mut args, "--policy")?;
    let effect = flag_value(&mut args, "--effect")?;
    let scope = flag_value(&mut args, "--scope")?;
    let event = record_manual_degrade(&opts.state_dir, policy, effect, scope)
        .map_err(|err| err.to_string())?;
    json_print(serde_json::json!({
        "status": "recorded",
        "manual_degrade": event,
        "kernel_install_channel": "pending_contractbpf_device_or_netlink",
    }));
    Ok(())
}

fn cmd_resolve_scope(opts: &GlobalOptions, mut args: Vec<String>) -> Result<(), String> {
    let id = flag_value(&mut args, "--scope")?;
    let scope_type =
        flag_value_optional(&mut args, "--type").unwrap_or_else(|| "service".to_string());
    let cgroup_path = flag_value_optional(&mut args, "--cgroup").map(PathBuf::from);
    let memcg_path = flag_value_optional(&mut args, "--memcg").map(PathBuf::from);
    let spec = ScopeSpec {
        scope_type,
        id,
        cgroup_path,
        memcg_path,
        numa_node: None,
        service_tag: None,
    };
    let resolved = resolve_scope(&spec, &opts.cgroup_root).map_err(|err| err.to_string())?;
    json_print(serde_json::json!({
        "status": "resolved",
        "scope": resolved,
    }));
    Ok(())
}

fn cmd_reset(opts: &GlobalOptions, args: Vec<String>) -> Result<(), String> {
    if !args.iter().any(|arg| arg == "--test-only") {
        return Err("reset requires --test-only".to_string());
    }
    save_state(&opts.state_dir, &Default::default()).map_err(|err| err.to_string())?;
    let device_reset = if opts.device.exists() {
        reset_device_for_tests(&opts.device)
            .map_err(|err| err.to_string())
            .map(|_| true)?
    } else {
        false
    };
    json_print(serde_json::json!({
        "status": "reset",
        "state_dir": opts.state_dir,
        "debugfs_written": false,
        "device_reset": device_reset,
    }));
    Ok(())
}

fn merge_ledger_max(dst: &mut LedgerSnapshot, src: &LedgerSnapshot) {
    dst.sched_dispatch_events = dst.sched_dispatch_events.max(src.sched_dispatch_events);
    dst.sched_boost_events = dst.sched_boost_events.max(src.sched_boost_events);
    dst.sched_queue_delay_us = dst.sched_queue_delay_us.max(src.sched_queue_delay_us);
    dst.pages_demoted = dst.pages_demoted.max(src.pages_demoted);
    dst.reclaim_hints = dst.reclaim_hints.max(src.reclaim_hints);
    dst.refault_events = dst.refault_events.max(src.refault_events);
    dst.major_fault_events = dst.major_fault_events.max(src.major_fault_events);
    dst.fault_latency_us = dst.fault_latency_us.max(src.fault_latency_us);
    dst.violations = dst.violations.max(src.violations);
    dst.sched_degrade_state = dst.sched_degrade_state.max(src.sched_degrade_state);
    dst.demote_degrade_state = dst.demote_degrade_state.max(src.demote_degrade_state);
}

fn print_ledger_lines(ledger: &LedgerSnapshot) {
    println!("sched_dispatch_events={}", ledger.sched_dispatch_events);
    println!("sched_boost_events={}", ledger.sched_boost_events);
    println!("sched_queue_delay_us={}", ledger.sched_queue_delay_us);
    println!("pages_demoted={}", ledger.pages_demoted);
    println!("reclaim_hints={}", ledger.reclaim_hints);
    println!("refault_events={}", ledger.refault_events);
    println!("major_fault_events={}", ledger.major_fault_events);
    println!("fault_latency_us={}", ledger.fault_latency_us);
    println!("violations={}", ledger.violations);
    println!("sched_degrade_state={}", ledger.sched_degrade_state);
    println!("demote_degrade_state={}", ledger.demote_degrade_state);
}

fn effect_counters_json(effect: EffectType, ledger: &LedgerSnapshot) -> serde_json::Value {
    match effect {
        EffectType::SchedBoost => serde_json::json!({
            "primary": ledger.sched_boost_events,
            "secondary": ledger.sched_queue_delay_us,
            "degrade_state": ledger.sched_degrade_state,
            "primary_name": "sched_boost_events",
            "secondary_name": "sched_queue_delay_us",
        }),
        EffectType::SchedDispatch => serde_json::json!({
            "primary": ledger.sched_dispatch_events,
            "secondary": 0,
            "degrade_state": 0,
            "primary_name": "sched_dispatch_events",
        }),
        EffectType::MmDemotePage => serde_json::json!({
            "primary": ledger.pages_demoted,
            "secondary": ledger.refault_events,
            "degrade_state": ledger.demote_degrade_state,
            "primary_name": "pages_demoted",
            "secondary_name": "refault_events",
        }),
        EffectType::MmReclaimHint => serde_json::json!({
            "primary": ledger.reclaim_hints,
            "secondary": 0,
            "degrade_state": 0,
            "primary_name": "reclaim_hints",
        }),
        EffectType::SchedPinCpu | EffectType::MmClassifyRegion => serde_json::json!({
            "primary": 0,
            "secondary": 0,
            "degrade_state": 0,
        }),
    }
}

fn remove_flag(args: &mut Vec<String>, flag: &str) -> bool {
    if let Some(pos) = args.iter().position(|arg| arg == flag) {
        args.remove(pos);
        true
    } else {
        false
    }
}

fn flag_value(args: &mut Vec<String>, flag: &str) -> Result<String, String> {
    flag_value_optional(args, flag).ok_or_else(|| format!("{flag} is required"))
}

fn flag_value_optional(args: &mut Vec<String>, flag: &str) -> Option<String> {
    let pos = args.iter().position(|arg| arg == flag)?;
    args.remove(pos);
    if pos >= args.len() {
        return None;
    }
    Some(args.remove(pos))
}
