use crate::commands::sync::resolve_sync_vscode_bin;
use crate::commands::{eval_target_bool, CheckRecord, DoctorArgs};
use dotfiles_core::emacs_sync::{run as run_emacs_sync, EmacsSyncMode, EmacsSyncOptions};
use dotfiles_core::shell_sync::{
    run as run_shell_sync, ShellGroup, ShellSyncMode, ShellSyncOptions,
};
use dotfiles_core::support::{
    evaluate_facts_schema, find_in_path, flake_ref_for_root, home_dir, is_executable_file,
    json_escape, nix_args_with_inputs, repo_root, require_input_directories, resolve_inputs,
    resolve_target, run_command_output, run_command_status,
};
use std::env;
use std::path::{Path, PathBuf};
use std::process::{self, Command};

pub(crate) fn command_doctor(args: &DoctorArgs) -> Result<(), String> {
    let host = args
        .target
        .host_value()
        .map(ToOwned::to_owned)
        .or_else(|| env::var("HOST").ok());
    let profile = args
        .target
        .profile_value()
        .map(ToOwned::to_owned)
        .or_else(|| env::var("PROFILE").ok());
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let (facts_dir, secrets_dir) = require_input_directories(&inputs, "doctor")?;
    let flake_ref = flake_ref_for_root(&root);

    let mut checks = Vec::<CheckRecord>::new();
    record_facts_checks(&root, &facts_dir, &mut checks);
    record_basic_system_checks(&secrets_dir, &mut checks);
    let resolved_target = record_target_checks(
        &root,
        &flake_ref,
        host.as_deref(),
        profile.as_deref(),
        &mut checks,
    );

    if args.strict {
        let mut check = Command::new("nix");
        check.arg("flake");
        check.arg("check");
        check.arg(&flake_ref);
        check.args(nix_args_with_inputs(&inputs));
        match run_command_status(&mut check)? {
            status if status.success() => checks.push(CheckRecord::new(
                "flake.check",
                "ok",
                "nix flake check passed",
            )),
            _ => checks.push(CheckRecord::new(
                "flake.check",
                "fail",
                "nix flake check failed",
            )),
        }

        if cfg!(target_os = "macos") {
            record_strict_sync_checks(&root, resolved_target.as_deref(), &mut checks)?;
        } else {
            checks.push(CheckRecord::new(
                "shell.sync",
                "ok",
                "skipped on non-Darwin host",
            ));
            checks.push(CheckRecord::new(
                "vscode.sync",
                "ok",
                "skipped on non-Darwin host",
            ));
            checks.push(CheckRecord::new(
                "emacs.sync",
                "ok",
                "skipped on non-Darwin host",
            ));
        }
    }

    let failures = checks.iter().filter(|check| check.status == "fail").count();
    let warnings = checks.iter().filter(|check| check.status == "warn").count();
    let infos = checks.iter().filter(|check| check.status == "info").count();

    if args.json {
        print!(
            "{{\"ok\":{},\"failures\":{},\"warnings\":{},\"info\":{},\"checks\":[",
            if failures == 0 { "true" } else { "false" },
            failures,
            warnings,
            infos
        );
        for (index, check) in checks.iter().enumerate() {
            print!(
                "{{\"name\":\"{}\",\"status\":\"{}\",\"message\":\"{}\"}}",
                json_escape(&check.name),
                json_escape(&check.status),
                json_escape(&check.message)
            );
            if index + 1 < checks.len() {
                print!(",");
            }
        }
        println!("]}}");
    } else {
        for check in &checks {
            println!("{:<5} {}: {}", check.status, check.name, check.message);
        }
    }

    if failures == 0 {
        Ok(())
    } else {
        process::exit(1)
    }
}

fn record_facts_checks(root: &Path, facts_dir: &Path, checks: &mut Vec<CheckRecord>) {
    let facts_file = facts_dir.join("facts.nix");
    if facts_file.is_file() {
        checks.push(CheckRecord::new(
            "facts.exists",
            "ok",
            facts_file.display().to_string(),
        ));
        match evaluate_facts_schema(root, &facts_file) {
            Ok(text) => {
                for line in text.lines() {
                    let parts: Vec<&str> = line.splitn(3, '|').collect();
                    if parts.len() == 3 {
                        checks.push(CheckRecord::new(parts[0], parts[1], parts[2]));
                    }
                }
            }
            Err(_) => checks.push(CheckRecord::new(
                "facts.eval",
                "fail",
                "unable to evaluate facts schema",
            )),
        }
    } else {
        checks.push(CheckRecord::new(
            "facts.exists",
            "fail",
            format!("{} missing", facts_file.display()),
        ));
    }
}

fn record_basic_system_checks(secrets_dir: &Path, checks: &mut Vec<CheckRecord>) {
    let secrets_file = secrets_dir.join("secrets.nix");
    if secrets_file.is_file() {
        checks.push(CheckRecord::new(
            "secrets.exists",
            "ok",
            secrets_file.display().to_string(),
        ));
    } else {
        checks.push(CheckRecord::new(
            "secrets.exists",
            "info",
            format!("{} missing (optional)", secrets_file.display()),
        ));
    }

    match env::var("SOPS_AGE_KEY_FILE")
        .ok()
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .map(Ok)
        .unwrap_or_else(|| home_dir().map(|home| home.join(".config/sops/age/keys.txt")))
    {
        Ok(age_key) if age_key.is_file() => checks.push(CheckRecord::new(
            "sops.ageKey",
            "ok",
            age_key.display().to_string(),
        )),
        Ok(age_key) => checks.push(CheckRecord::new(
            "sops.ageKey",
            "warn",
            format!("{} missing", age_key.display()),
        )),
        Err(err) => checks.push(CheckRecord::new("sops.ageKey", "warn", err)),
    }

    if cfg!(target_os = "macos") {
        let mut xcode_select = Command::new("xcode-select");
        xcode_select.arg("-p");
        let xcode = run_command_output(&mut xcode_select);
        match xcode {
            Ok(output) if output.status.success() => checks.push(CheckRecord::new(
                "darwin.xcodeSelect",
                "ok",
                String::from_utf8_lossy(&output.stdout).trim().to_string(),
            )),
            _ => checks.push(CheckRecord::new(
                "darwin.xcodeSelect",
                "warn",
                "Command Line Tools not configured",
            )),
        }

        if env::consts::ARCH == "aarch64" {
            let mut rosetta_command = Command::new("arch");
            rosetta_command.arg("-x86_64");
            rosetta_command.arg("/usr/bin/true");
            let rosetta = run_command_status(&mut rosetta_command);
            match rosetta {
                Ok(status) if status.success() => checks.push(CheckRecord::new(
                    "darwin.rosetta",
                    "ok",
                    "Rosetta available",
                )),
                _ => checks.push(CheckRecord::new(
                    "darwin.rosetta",
                    "warn",
                    "Rosetta not available",
                )),
            }
        } else {
            checks.push(CheckRecord::new(
                "darwin.rosetta",
                "ok",
                format!("Not required on {}", env::consts::ARCH),
            ));
        }
    } else {
        checks.push(CheckRecord::new(
            "darwin.xcodeSelect",
            "ok",
            "skipped on non-Darwin host",
        ));
        checks.push(CheckRecord::new(
            "darwin.rosetta",
            "ok",
            "skipped on non-Darwin host",
        ));
    }
}

fn record_target_checks(
    root: &Path,
    flake_ref: &str,
    host: Option<&str>,
    profile: Option<&str>,
    checks: &mut Vec<CheckRecord>,
) -> Option<String> {
    let inputs = match resolve_inputs() {
        Ok(inputs) => inputs,
        Err(_) => {
            checks.push(CheckRecord::new(
                "flake.targets",
                "fail",
                "unable to resolve local/secrets inputs",
            ));
            return None;
        }
    };

    let targets = match dotfiles_core::support::list_darwin_targets(root, &inputs) {
        Ok(targets) => targets,
        Err(_) => {
            checks.push(CheckRecord::new(
                "flake.targets",
                "fail",
                "unable to evaluate darwinConfigurations",
            ));
            return None;
        }
    };

    if targets.is_empty() {
        checks.push(CheckRecord::new(
            "flake.targets",
            "fail",
            "no darwinConfigurations found",
        ));
        return None;
    }

    if let Some(host_name) = host {
        let target = match resolve_target(root, &inputs, host_name, profile) {
            Ok(target) => target,
            Err(_) => {
                checks.push(CheckRecord::new(
                    "flake.target",
                    "fail",
                    "target resolution failed",
                ));
                return None;
            }
        };
        let mut eval = Command::new("nix");
        eval.arg("eval");
        eval.arg("--raw");
        eval.arg(format!(
            "{}#darwinConfigurations.{}.system.drvPath",
            flake_ref, target
        ));
        eval.args(nix_args_with_inputs(&inputs));
        match run_command_status(&mut eval) {
            Ok(status) if status.success() => {
                checks.push(CheckRecord::new("flake.target", "ok", target.clone()))
            }
            _ => checks.push(CheckRecord::new(
                "flake.target",
                "fail",
                format!("unable to evaluate darwinConfigurations.{}.system", target),
            )),
        }
        Some(target)
    } else {
        checks.push(CheckRecord::new(
            "flake.targets",
            "ok",
            format!("darwinConfigurations available ({} targets)", targets.len()),
        ));
        None
    }
}

fn record_strict_sync_checks(
    root: &Path,
    resolved_target: Option<&str>,
    checks: &mut Vec<CheckRecord>,
) -> Result<(), String> {
    let Some(target) = resolved_target else {
        checks.push(CheckRecord::new(
            "shell.sync",
            "warn",
            "strict sync check skipped (pass --host to resolve target)",
        ));
        checks.push(CheckRecord::new(
            "vscode.sync",
            "warn",
            "strict VS Code sync check skipped (pass --host to resolve target)",
        ));
        checks.push(CheckRecord::new(
            "emacs.sync",
            "warn",
            "strict Emacs sync check skipped (pass --host to resolve target)",
        ));
        return Ok(());
    };

    let inputs = resolve_inputs()?;
    let flake_ref = flake_ref_for_root(root);
    let shell_enabled =
        eval_target_bool(&flake_ref, &inputs, target, "myconfig.tools.shell.enable")?;
    let zsh_enabled = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.shell.zsh.enable",
    )?;
    let bash_enabled = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.shell.bash.enable",
    )?;
    let vscode_enabled = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.editor.vscode.enable",
    )?;
    let vscode_sync = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.editor.vscode.sync.enable",
    )?;
    let emacs_enabled = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.editor.emacs.enable",
    )?;
    let emacs_sync = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.editor.emacs.sync.enable",
    )?;

    if shell_enabled == Some(true) {
        let mut groups = Vec::new();
        if zsh_enabled == Some(true) {
            groups.push(ShellGroup::Zsh);
        }
        if bash_enabled == Some(true) {
            groups.push(ShellGroup::Bash);
        }

        if groups.is_empty() {
            checks.push(CheckRecord::new(
                "shell.sync",
                "ok",
                "shell sync enabled but no shell targets are enabled; skipped",
            ));
        } else {
            let result = run_shell_sync(ShellSyncOptions {
                managed_dir: Some(root.join("surfaces/shell/desired")),
                mode: ShellSyncMode::Check,
                details: false,
                diff_output: false,
                group_filters: groups,
                item_filter: None,
            })?;
            if result.exit_code(ShellSyncMode::Check) == 0 {
                checks.push(CheckRecord::new(
                    "shell.sync",
                    "ok",
                    "shell sync check passed",
                ));
            } else {
                checks.push(CheckRecord::new(
                    "shell.sync",
                    "fail",
                    "shell sync check failed (inspect: nix run .#dotfiles -- sync shell --check --details --diff)",
                ));
            }
        }
    } else if shell_enabled == Some(false) {
        checks.push(CheckRecord::new(
            "shell.sync",
            "ok",
            format!("disabled in target {}; skipped", target),
        ));
    } else {
        checks.push(CheckRecord::new(
            "shell.sync",
            "warn",
            format!(
                "unable to resolve shell enablement for target {}; skipped",
                target
            ),
        ));
    }

    if emacs_enabled == Some(true) && emacs_sync == Some(true) {
        let result = run_emacs_sync(EmacsSyncOptions {
            managed_dir: Some(root.join("apps/emacs/doom")),
            doom_dir: None,
            mode: EmacsSyncMode::Check,
            details: false,
            diff_output: false,
            item_filter: None,
        })?;
        if result.exit_code(EmacsSyncMode::Check) == 0 {
            checks.push(CheckRecord::new(
                "emacs.sync",
                "ok",
                "Emacs sync check passed",
            ));
        } else {
            checks.push(CheckRecord::new(
                "emacs.sync",
                "fail",
                "Emacs sync check failed (inspect: nix run .#dotfiles -- sync emacs --check --details --diff)",
            ));
        }
    } else if emacs_enabled == Some(false) || emacs_sync == Some(false) {
        checks.push(CheckRecord::new(
            "emacs.sync",
            "ok",
            format!("disabled in target {}; skipped", target),
        ));
    } else {
        checks.push(CheckRecord::new(
            "emacs.sync",
            "warn",
            format!(
                "unable to resolve Emacs sync enablement for target {}; skipped",
                target
            ),
        ));
    }

    if vscode_enabled == Some(true) && vscode_sync == Some(true) {
        if vscode_cli_missing() {
            checks.push(CheckRecord::new(
                "vscode.sync",
                "ok",
                "VS Code CLI not found; skipped",
            ));
            return Ok(());
        }

        let mut sync = Command::new(resolve_sync_vscode_bin()?);
        sync.arg("--check");
        sync.arg("--details");
        let status = run_command_status(&mut sync)?;
        if status.success() {
            checks.push(CheckRecord::new(
                "vscode.sync",
                "ok",
                "VS Code sync check passed",
            ));
        } else {
            checks.push(CheckRecord::new(
                "vscode.sync",
                "fail",
                "VS Code sync check failed (inspect: nix run .#dotfiles -- sync vscode --check --details --diff)",
            ));
        }
    } else if vscode_enabled == Some(false) || vscode_sync == Some(false) {
        checks.push(CheckRecord::new(
            "vscode.sync",
            "ok",
            format!("disabled in target {}; skipped", target),
        ));
    } else {
        checks.push(CheckRecord::new(
            "vscode.sync",
            "warn",
            format!(
                "unable to resolve VS Code sync enablement for target {}; skipped",
                target
            ),
        ));
    }

    Ok(())
}

fn vscode_cli_missing() -> bool {
    if let Ok(bin) = env::var("VSCODE_CODE_BIN") {
        if !bin.is_empty() {
            return !is_executable_file(&PathBuf::from(bin));
        }
    }

    if find_in_path("code").is_some() {
        return false;
    }

    if let Ok(home) = home_dir() {
        let candidate =
            home.join("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code");
        if is_executable_file(&candidate) {
            return false;
        }
    }

    !is_executable_file(&PathBuf::from(
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
    ))
}
