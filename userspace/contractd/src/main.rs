use std::env;
use std::path::Path;
use std::process::ExitCode;

use libcontract::{
    effect_tokens, install_policy, ledger_from_snapshots, load_debugfs_snapshots,
    parse_manifest_file, resolve_scope, status_json, validate_manifest, ManifestDocument,
};

const CONTRACTBPF_DEBUGFS: &str = "/sys/kernel/debug/contractbpf";
const CGROUP_CONTROLLERS: &str = "/sys/fs/cgroup/cgroup.controllers";

fn require_memory_controller() -> Result<String, String> {
    let controllers = std::fs::read_to_string(CGROUP_CONTROLLERS)
        .map_err(|err| format!("failed to read {CGROUP_CONTROLLERS}: {err}"))?;

    if controllers
        .split_whitespace()
        .any(|controller| controller == "memory")
    {
        Ok(controllers)
    } else {
        Err(format!(
            "memory controller missing from {CGROUP_CONTROLLERS}: {controllers}"
        ))
    }
}

#[derive(Debug, Default)]
struct Options {
    manifests: Vec<String>,
    state_dir: String,
    debugfs_root: String,
    cgroup_root: String,
    device: String,
    once: bool,
}

fn parse_args() -> Result<Options, String> {
    let mut opts = Options {
        state_dir: env::var("CONTRACTBPF_STATE_DIR")
            .unwrap_or_else(|_| "/run/contractbpf".to_string()),
        debugfs_root: env::var("CONTRACTBPF_DEBUGFS")
            .unwrap_or_else(|_| CONTRACTBPF_DEBUGFS.to_string()),
        cgroup_root: env::var("CONTRACTBPF_CGROUP_ROOT")
            .unwrap_or_else(|_| "/sys/fs/cgroup".to_string()),
        device: env::var("CONTRACTBPF_DEVICE").unwrap_or_else(|_| "/dev/contractbpf".to_string()),
        once: true,
        ..Options::default()
    };

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--manifest" => opts
                .manifests
                .push(args.next().ok_or("--manifest needs a path")?),
            "--state-dir" => opts.state_dir = args.next().ok_or("--state-dir needs a path")?,
            "--debugfs-root" => {
                opts.debugfs_root = args.next().ok_or("--debugfs-root needs a path")?
            }
            "--cgroup-root" => {
                opts.cgroup_root = args.next().ok_or("--cgroup-root needs a path")?
            }
            "--device" => opts.device = args.next().ok_or("--device needs a path")?,
            "--follow" => opts.once = false,
            "--once" => opts.once = true,
            "-h" | "--help" => {
                println!(
                    "usage: contractd [--manifest PATH ...] [--state-dir DIR] [--debugfs-root DIR] [--cgroup-root DIR] [--device PATH] [--once|--follow]"
                );
                std::process::exit(0);
            }
            _ => return Err(format!("unknown argument '{arg}'")),
        }
    }

    Ok(opts)
}

fn emit_json(event: &str, value: serde_json::Value) {
    let line = serde_json::json!({
        "component": "contractd",
        "event": event,
        "data": value,
    });
    println!("{}", serde_json::to_string(&line).unwrap());
}

fn main() -> ExitCode {
    let opts = match parse_args() {
        Ok(opts) => opts,
        Err(err) => {
            eprintln!("contractd: {err}");
            return ExitCode::from(2);
        }
    };
    let root = Path::new(&opts.debugfs_root);
    let state_dir = Path::new(&opts.state_dir);
    let cgroup_root = Path::new(&opts.cgroup_root);
    let device = Path::new(&opts.device);

    if root.is_dir() {
        println!("contractd: debugfs={}", root.display());
    } else {
        println!("contractd: debugfs={} unavailable", root.display());
    }

    match require_memory_controller() {
        Ok(controllers) => println!("contractd: cgroup.controllers={}", controllers.trim()),
        Err(err) => println!("contractd: {err}"),
    }

    for manifest_arg in &opts.manifests {
        let manifest_path = Path::new(manifest_arg);
        let doc = match parse_manifest_file(manifest_path).and_then(|doc| {
            validate_manifest(&doc)?;
            Ok(doc)
        }) {
            Ok(doc) => doc,
            Err(err) => {
                eprintln!(
                    "contractd: manifest {} failed: {err}",
                    manifest_path.display()
                );
                return ExitCode::from(1);
            }
        };

        match doc {
            ManifestDocument::Contract(contract) => {
                let resolved = match resolve_scope(&contract.scope, cgroup_root) {
                    Ok(scope) => scope,
                    Err(err) => {
                        eprintln!("contractd: scope resolution failed: {err}");
                        return ExitCode::from(1);
                    }
                };
                let tokens = effect_tokens(&contract);
                let installed = match install_policy(state_dir, manifest_path, contract, resolved) {
                    Ok(installed) => installed,
                    Err(err) => {
                        eprintln!("contractd: failed to persist policy: {err}");
                        return ExitCode::from(1);
                    }
                };
                let kernel_install = if device.exists() {
                    match libcontract::install_manifest_tokens_via_device(
                        device,
                        &installed.manifest,
                        &installed.resolved_scope,
                    ) {
                        Ok(report) => {
                            let gate = match libcontract::set_manifest_gate_via_device(
                                device,
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
                        "device": device,
                        "reason": "device_missing",
                    })
                };
                emit_json(
                    "policy_loaded",
                    serde_json::json!({
                        "policy": installed.manifest.policy,
                        "tokens": tokens,
                        "resolved_scope": installed.resolved_scope,
                        "kernel_install": kernel_install,
                    }),
                );
            }
            ManifestDocument::Composition(composition) => {
                emit_json("composition_validated", serde_json::json!(composition));
            }
        }
    }

    let snapshots = load_debugfs_snapshots(root);
    let ledger = ledger_from_snapshots(&snapshots);
    emit_json("ledger_snapshot", serde_json::json!(ledger));

    if let Ok(status) = status_json(state_dir, root) {
        emit_json("status", status);
    }

    println!("CONTRACTBPF_CONTRACTD_OK");
    ExitCode::SUCCESS
}
