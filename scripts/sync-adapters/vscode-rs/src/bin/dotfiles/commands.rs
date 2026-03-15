use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{self, Command};

use crate::common::{
    bash_command, ensure_dir_mode, ensure_file_mode, ensure_inputs_dirs,
    evaluate_facts_schema, exit_with_status, explain_darwin_targets_error,
    flake_ref_for_root, git_tracked_files, json_escape, list_darwin_targets,
    list_updateable_root_flake_inputs, log, nix_args_with_inputs, parse_target_args,
    render_bootstrap_facts, repo_root, require_host_argument, require_input_directories,
    require_writable_checkout, resolve_inputs, resolve_pinned_darwin_rebuild_bin,
    resolve_target, run_command_output, run_command_status, sudo_preserve_env_vars,
};

#[derive(Clone)]
struct CheckRecord {
    name: String,
    status: String,
    message: String,
}

impl CheckRecord {
    fn new(name: &str, status: &str, message: impl Into<String>) -> Self {
        Self {
            name: name.to_string(),
            status: status.to_string(),
            message: message.into(),
        }
    }
}

pub(crate) fn run(args: Vec<String>) -> Result<(), String> {
    if args.is_empty() {
        print_usage();
        process::exit(1);
    }

    let subcommand = &args[0];
    let tail = &args[1..];
    match subcommand.as_str() {
        "apply" => command_apply(tail),
        "update" => command_update(tail),
        "doctor" => command_doctor(tail),
        "bootstrap" => command_bootstrap(tail),
        "export-clean" => command_export_clean(tail),
        "list-tools" => command_list_tools(tail),
        "matrix-tools" => command_matrix_tools(tail),
        "sync" => command_sync(tail),
        "help" | "-h" | "--help" => {
            print_usage();
            Ok(())
        }
        _ => Err(format!("unknown subcommand: {}", subcommand)),
    }
}

fn print_usage() {
    println!(
        "Usage: nix run .#dotfiles -- <subcommand> [args...]

Subcommands:
  apply
  update
  doctor
  bootstrap
  export-clean
  list-tools
  matrix-tools
  sync"
    );
}

fn command_apply(args: &[String]) -> Result<(), String> {
    let parsed = parse_target_args(args, &["--action"])?;
    let mut action = "switch".to_string();
    let mut no_sudo = false;

    let mut index = 0usize;
    while index < parsed.args.len() {
        match parsed.args[index].as_str() {
            "--action" => {
                action = parsed
                    .args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --action".to_string())?
                    .clone();
                index += 2;
            }
            "--no-sudo" => {
                no_sudo = true;
                index += 1;
            }
            "-h" | "--help" => {
                println!("Usage: nix run .#apply -- [--host <host>] [--rice <rice>] [--action switch|build] [--no-sudo] [--] [darwin-rebuild args...]");
                return Ok(());
            }
            arg if arg.starts_with("--") => return Err(format!("unknown option: {}", arg)),
            arg => return Err(format!("unexpected argument: {} (use -- to pass through to darwin-rebuild)", arg)),
        }
    }

    if action != "switch" && action != "build" {
        return Err(format!(
            "invalid --action: {} (expected switch or build)",
            action
        ));
    }

    let host_env = env::var("HOST").ok();
    let host = require_host_argument(parsed.host.as_deref().or(host_env.as_deref()), "apply")?;
    let rice = parsed.rice.or_else(|| env::var("RICE").ok());
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let target = resolve_target(&root, &inputs, &host, rice.as_deref())
        .map_err(|err| explain_darwin_targets_error(&inputs, &err))?;
    let flake_ref = flake_ref_for_root(&root);
    let darwin_rebuild_bin = resolve_pinned_darwin_rebuild_bin(&flake_ref)?;

    let mut command = if is_effective_root() || no_sudo {
        Command::new(&darwin_rebuild_bin)
    } else {
        let mut sudo = Command::new("sudo");
        sudo.arg(format!("--preserve-env={}", sudo_preserve_env_vars()));
        sudo.arg(&darwin_rebuild_bin);
        sudo
    };

    command.arg(action);
    command.arg("--flake");
    command.arg(format!("{}#{}", flake_ref, target));
    command.args(nix_args_with_inputs(&inputs));
    command.args(&parsed.passthrough);

    let status = run_command_status(&mut command)?;
    if status.success() {
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn command_update(args: &[String]) -> Result<(), String> {
    let parsed = parse_target_args(args, &[])?;
    if parsed.has_passthrough {
        return Err("unexpected -- (no passthrough supported)".to_string());
    }
    for arg in &parsed.args {
        match arg.as_str() {
            "-h" | "--help" => {
                println!("Usage: nix run .#update -- [--host <host>] [--rice <rice>]");
                return Ok(());
            }
            option if option.starts_with("--") => return Err(format!("unknown option: {}", option)),
            other => return Err(format!("unexpected argument: {}", other)),
        }
    }

    let host = parsed.host.or_else(|| env::var("HOST").ok());
    let rice = parsed.rice.or_else(|| env::var("RICE").ok());
    let run_build = env::var("UPDATE_SKIP_BUILD").unwrap_or_default() != "1";
    if run_build {
        require_host_argument(host.as_deref(), "update")?;
    }
    let start_dir = env::current_dir().map_err(|err| format!("failed to resolve cwd: {}", err))?;
    let inputs = resolve_inputs()?;
    let root = repo_root()?;
    let writable_root = require_writable_checkout(&root, &start_dir)?;
    let flake_ref = flake_ref_for_root(&writable_root);

    let update_inputs = list_updateable_root_flake_inputs(&writable_root)?;
    if update_inputs.is_empty() {
        return Err(format!(
            "unable to determine updateable flake inputs from {}/flake.lock",
            writable_root.display()
        ));
    }

    let mut update = Command::new("nix");
    update.current_dir(&writable_root);
    update.arg("flake");
    update.arg("update");
    if env::var("UPDATE_ALL").unwrap_or_default() != "1" {
        for input in update_inputs {
            update.arg("--update-input");
            update.arg(input);
        }
    }
    let status = run_command_status(&mut update)?;
    if !status.success() {
        exit_with_status(status);
    }

    if env::var("UPDATE_FORMAT").unwrap_or_default() == "1" {
        let mut format_command = Command::new("nix");
        format_command.current_dir(&writable_root);
        format_command.arg("run");
        format_command.arg(format!("{}#format", flake_ref));
        let status = run_command_status(&mut format_command)?;
        if !status.success() {
            exit_with_status(status);
        }
    }

    let run_checks = if env::var("UPDATE_CHECKS").unwrap_or_default() == "1" {
        true
    } else {
        env::var("UPDATE_SKIP_CHECK").unwrap_or_default() != "1"
    };
    if run_checks {
        let mut check = Command::new("nix");
        check.current_dir(&writable_root);
        check.arg("flake");
        check.arg("check");
        check.args(nix_args_with_inputs(&inputs));
        let status = run_command_status(&mut check)?;
        if !status.success() {
            exit_with_status(status);
        }
    }

    if run_build {
        let target = resolve_target(
            &writable_root,
            &inputs,
            host.as_deref().expect("host"),
            rice.as_deref(),
        )
        .map_err(|err| explain_darwin_targets_error(&inputs, &err))?;
        let darwin_rebuild_bin = resolve_pinned_darwin_rebuild_bin(&flake_ref)?;
        let mut build = Command::new(darwin_rebuild_bin);
        build.arg("build");
        build.arg("--flake");
        build.arg(format!("{}#{}", flake_ref, target));
        build.args(nix_args_with_inputs(&inputs));
        let status = run_command_status(&mut build)?;
        if !status.success() {
            exit_with_status(status);
        }
    }

    if env::var("UPDATE_COMMIT").unwrap_or_default() == "1" {
        let mut diff = Command::new("git");
        diff.current_dir(&writable_root);
        diff.arg("diff");
        diff.arg("--quiet");
        diff.arg("--");
        diff.arg("flake.lock");
        let status = run_command_status(&mut diff)?;
        let mut cached = Command::new("git");
        cached.current_dir(&writable_root);
        cached.arg("diff");
        cached.arg("--cached");
        cached.arg("--quiet");
        cached.arg("--");
        cached.arg("flake.lock");
        let cached_status = run_command_status(&mut cached)?;
        if status.success() && cached_status.success() {
            println!("update: no flake.lock changes to commit");
        } else {
            let mut add = Command::new("git");
            add.current_dir(&writable_root);
            add.arg("add");
            add.arg("--");
            add.arg("flake.lock");
            let status = run_command_status(&mut add)?;
            if !status.success() {
                exit_with_status(status);
            }
            let mut commit = Command::new("git");
            commit.current_dir(&writable_root);
            commit.arg("commit");
            commit.arg("--only");
            commit.arg("flake.lock");
            commit.arg("-m");
            commit.arg("chore(update): flake inputs");
            let status = run_command_status(&mut commit)?;
            if !status.success() {
                exit_with_status(status);
            }
        }
    }

    Ok(())
}

fn command_doctor(args: &[String]) -> Result<(), String> {
    let parsed = parse_target_args(args, &[])?;
    if parsed.has_passthrough {
        return Err("unexpected -- (no passthrough supported)".to_string());
    }

    let mut strict = false;
    let mut json = false;
    for arg in &parsed.args {
        match arg.as_str() {
            "--strict" => strict = true,
            "--json" => json = true,
            "-h" | "--help" => {
                println!("Usage: nix run .#doctor -- [--host <host>] [--rice <rice>] [--strict] [--json]");
                return Ok(());
            }
            option if option.starts_with("--") => return Err(format!("unknown option: {}", option)),
            other => return Err(format!("unexpected argument: {}", other)),
        }
    }

    let host = parsed.host.or_else(|| env::var("HOST").ok());
    let rice = parsed.rice.or_else(|| env::var("RICE").ok());
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let (facts_dir, secrets_dir) = require_input_directories(&inputs, "doctor")?;
    let flake_ref = flake_ref_for_root(&root);

    let mut checks = Vec::<CheckRecord>::new();
    record_facts_checks(&root, &facts_dir, &mut checks);
    record_basic_system_checks(&secrets_dir, &mut checks);
    let resolved_target = record_target_checks(&root, &flake_ref, &inputs, host.as_deref(), rice.as_deref(), json, &mut checks);

    if strict {
        let mut check = Command::new("nix");
        check.arg("flake");
        check.arg("check");
        check.arg(&flake_ref);
        check.args(nix_args_with_inputs(&inputs));
        match run_command_status(&mut check)? {
            status if status.success() => checks.push(CheckRecord::new("flake.check", "ok", "nix flake check passed")),
            _ => checks.push(CheckRecord::new("flake.check", "fail", "nix flake check failed")),
        }

        if cfg!(target_os = "macos") {
            record_strict_sync_checks(&root, resolved_target.as_deref(), &mut checks)?;
        } else {
            checks.push(CheckRecord::new("shell.sync", "ok", "skipped on non-Darwin host"));
            checks.push(CheckRecord::new(
                "shell.zsh.rootCompat",
                "ok",
                "skipped on non-Darwin host",
            ));
        }
    }

    let failures = checks.iter().filter(|check| check.status == "fail").count();
    let warnings = checks.iter().filter(|check| check.status == "warn").count();
    let infos = checks.iter().filter(|check| check.status == "info").count();

    if json {
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
        checks.push(CheckRecord::new("facts.exists", "ok", facts_file.display().to_string()));
        match evaluate_facts_schema(root, &facts_file) {
            Ok(text) => {
                for line in text.lines() {
                    let parts: Vec<&str> = line.splitn(3, '|').collect();
                    if parts.len() == 3 {
                        checks.push(CheckRecord::new(parts[0], parts[1], parts[2]));
                    }
                }
            }
            Err(_) => checks.push(CheckRecord::new("facts.eval", "fail", "unable to evaluate facts schema")),
        }
    } else {
        checks.push(CheckRecord::new(
            "facts.exists",
            "fail",
            format!("{} missing", facts_file.display()),
        ));
    }

    if facts_dir.join("STUB").is_file() {
        checks.push(CheckRecord::new(
            "facts.stub",
            "fail",
            format!("STUB present in {}", facts_dir.display()),
        ));
    } else {
        checks.push(CheckRecord::new("facts.stub", "ok", format!("no STUB in {}", facts_dir.display())));
    }
}

fn record_basic_system_checks(secrets_dir: &Path, checks: &mut Vec<CheckRecord>) {
    let secrets_file = secrets_dir.join("secrets.nix");
    if secrets_file.is_file() {
        checks.push(CheckRecord::new("secrets.exists", "ok", secrets_file.display().to_string()));
    } else {
        checks.push(CheckRecord::new(
            "secrets.exists",
            "info",
            format!("{} missing (optional)", secrets_file.display()),
        ));
    }

    let age_key = env::var("SOPS_AGE_KEY_FILE")
        .ok()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var("HOME").unwrap_or_default()).join(".config/sops/age/keys.txt"));
    if age_key.is_file() {
        checks.push(CheckRecord::new("sops.ageKey", "ok", age_key.display().to_string()));
    } else {
        checks.push(CheckRecord::new(
            "sops.ageKey",
            "warn",
            format!("{} missing", age_key.display()),
        ));
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
                "fail",
                "Command Line Tools not configured",
            )),
        }

        if env::consts::ARCH == "aarch64" {
            let mut rosetta_command = Command::new("arch");
            rosetta_command.arg("-x86_64");
            rosetta_command.arg("/usr/bin/true");
            let rosetta = run_command_status(&mut rosetta_command);
            match rosetta {
                Ok(status) if status.success() => checks.push(CheckRecord::new("darwin.rosetta", "ok", "Rosetta available")),
                _ => checks.push(CheckRecord::new("darwin.rosetta", "warn", "Rosetta not available")),
            }
        } else {
            checks.push(CheckRecord::new(
                "darwin.rosetta",
                "ok",
                format!("Not required on {}", env::consts::ARCH),
            ));
        }
    } else {
        checks.push(CheckRecord::new("darwin.xcodeSelect", "ok", "skipped on non-Darwin host"));
        checks.push(CheckRecord::new("darwin.rosetta", "ok", "skipped on non-Darwin host"));
    }
}

fn record_target_checks(
    root: &Path,
    flake_ref: &str,
    inputs: &crate::common::InputRefs,
    host: Option<&str>,
    rice: Option<&str>,
    suppress_logs: bool,
    checks: &mut Vec<CheckRecord>,
) -> Option<String> {
    let targets = match list_darwin_targets(root, inputs) {
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
        let target = match resolve_target(root, inputs, host_name, rice) {
            Ok(target) => target,
            Err(_) => {
                checks.push(CheckRecord::new("flake.target", "fail", "target resolution failed"));
                return None;
            }
        };
        let mut eval = Command::new("nix");
        eval.arg("eval");
        eval.arg("--raw");
        eval.arg(format!("{}#darwinConfigurations.{}.system.drvPath", flake_ref, target));
        eval.args(nix_args_with_inputs(inputs));
        match run_command_status(&mut eval) {
            Ok(status) if status.success() => checks.push(CheckRecord::new("flake.target", "ok", target.clone())),
            _ => checks.push(CheckRecord::new(
                "flake.target",
                "fail",
                format!("unable to evaluate darwinConfigurations.{}.system", target),
            )),
        }
        Some(target)
    } else {
        if !suppress_logs {
            checks.push(CheckRecord::new(
                "flake.targets",
                "ok",
                format!("darwinConfigurations available ({} targets)", targets.len()),
            ));
        } else {
            checks.push(CheckRecord::new(
                "flake.targets",
                "ok",
                format!("darwinConfigurations available ({} targets)", targets.len()),
            ));
        }
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
            "shell.zsh.rootCompat",
            "warn",
            "strict root compat check skipped (pass --host to resolve target)",
        ));
        checks.push(CheckRecord::new(
            "vscode.sync",
            "warn",
            "strict VS Code sync check skipped (pass --host to resolve target)",
        ));
        return Ok(());
    };

    let inputs = resolve_inputs()?;
    let flake_ref = flake_ref_for_root(root);
    let shell_enabled = eval_target_bool(&flake_ref, &inputs, target, "myconfig.tools.shell.enable")?;
    let zsh_enabled = eval_target_bool(&flake_ref, &inputs, target, "myconfig.tools.shell.zsh.enable")?;
    let root_compat = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.shell.zsh.rootZshrcCompat.enable",
    )?;
    let vscode_enabled = eval_target_bool(&flake_ref, &inputs, target, "myconfig.tools.editor.vscode.enable")?;
    let vscode_sync = eval_target_bool(
        &flake_ref,
        &inputs,
        target,
        "myconfig.tools.editor.vscode.sync.enable",
    )?;

    let sync_script = root.join("scripts/sync-adapters/shell.sh");
    if shell_enabled == Some(true) && sync_script.is_file() {
        let mut shell_sync = bash_command(&sync_script, &["--check".to_string(), "--details".to_string()]);
        let status = run_command_status(&mut shell_sync)?;
        if status.success() {
            checks.push(CheckRecord::new("shell.sync", "ok", "shell sync check passed"));
        } else {
            checks.push(CheckRecord::new(
                "shell.sync",
                "fail",
                "shell sync check failed (inspect: nix run .#dotfiles -- sync shell --check --details --diff)",
            ));
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
            format!("unable to resolve shell enablement for target {}; skipped", target),
        ));
    }

    let compat_script = root.join("scripts/zshrc-compat.sh");
    if zsh_enabled == Some(true) && root_compat == Some(true) && compat_script.is_file() {
        let mut compat = Command::new("bash");
        compat.arg(&compat_script);
        compat.arg("--check");
        let status = run_command_status(&mut compat)?;
        if status.success() {
            checks.push(CheckRecord::new(
                "shell.zsh.rootCompat",
                "ok",
                "zsh root compat check passed",
            ));
        } else {
            checks.push(CheckRecord::new(
                "shell.zsh.rootCompat",
                "fail",
                "zsh root compat check failed (inspect: bash scripts/zshrc-compat.sh --check)",
            ));
        }
    } else if zsh_enabled == Some(false) || root_compat == Some(false) {
        checks.push(CheckRecord::new(
            "shell.zsh.rootCompat",
            "ok",
            format!("disabled in target {}", target),
        ));
    } else {
        checks.push(CheckRecord::new(
            "shell.zsh.rootCompat",
            "warn",
            format!("unable to resolve zsh root compat enablement for target {}; skipped", target),
        ));
    }

    if vscode_enabled == Some(true) && vscode_sync == Some(true) {
        let exe = env::current_exe().map_err(|err| format!("failed to resolve current executable: {}", err))?;
        let mut sync = Command::new(exe);
        sync.arg("sync");
        sync.arg("vscode");
        sync.arg("--check");
        sync.arg("--details");
        let status = run_command_status(&mut sync)?;
        if status.success() {
            checks.push(CheckRecord::new("vscode.sync", "ok", "VS Code sync check passed"));
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
            format!("unable to resolve VS Code sync enablement for target {}; skipped", target),
        ));
    }

    Ok(())
}

fn eval_target_bool(
    flake_ref: &str,
    inputs: &crate::common::InputRefs,
    target: &str,
    option_path: &str,
) -> Result<Option<bool>, String> {
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg("--raw");
    command.arg(format!("{}#darwinConfigurations.{}.config.{}", flake_ref, target, option_path));
    command.arg("--apply");
    command.arg(r#"x: if x then "true" else "false""#);
    command.args(nix_args_with_inputs(inputs));
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        return Ok(None);
    }
    match String::from_utf8_lossy(&output.stdout).trim() {
        "true" => Ok(Some(true)),
        "false" => Ok(Some(false)),
        _ => Ok(None),
    }
}

fn command_bootstrap(args: &[String]) -> Result<(), String> {
    let parsed = parse_target_args(args, &[])?;
    if parsed.has_passthrough {
        return Err("unexpected -- (no passthrough supported)".to_string());
    }

    let mut apply_after = false;
    let mut auto_yes = false;
    let mut no_sudo = false;
    let mut strict = false;
    for arg in &parsed.args {
        match arg.as_str() {
            "--apply" => apply_after = true,
            "--yes" => {
                apply_after = true;
                auto_yes = true;
            }
            "--no-sudo" => no_sudo = true,
            "--strict" => strict = true,
            "-h" | "--help" => {
                println!("Usage: nix run .#bootstrap -- [--host <host>] [--rice <rice>] [--apply] [--yes] [--no-sudo] [--strict]");
                return Ok(());
            }
            option if option.starts_with("--") => return Err(format!("unknown option: {}", option)),
            other => return Err(format!("unexpected argument: {}", other)),
        }
    }

    let host = parsed.host.or_else(|| env::var("HOST").ok());
    let rice = parsed.rice.or_else(|| env::var("RICE").ok());
    if apply_after {
        require_host_argument(host.as_deref(), "bootstrap")?;
    }

    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let (facts_dir, secrets_dir) = require_input_directories(&inputs, "bootstrap")?;
    ensure_inputs_dirs(&facts_dir, &secrets_dir)?;

    let facts_file = facts_dir.join("facts.nix");
    if !facts_file.is_file() {
        let username = env::var("USER")
            .ok()
            .filter(|value| !value.is_empty())
            .or_else(|| {
                let mut id = Command::new("id");
                id.arg("-un");
                run_command_output(&mut id).ok()
                    .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
                    .filter(|value| !value.is_empty())
            })
            .unwrap_or_else(|| "yourname".to_string());
        let rendered = render_bootstrap_facts(&root, &username)?;
        fs::write(&facts_file, rendered)
            .map_err(|err| format!("failed to write {}: {}", facts_file.display(), err))?;
        log(&format!("generated {}", facts_file.display()));
    }
    ensure_file_mode(&facts_file, 0o600)?;

    let secrets_file = secrets_dir.join("secrets.nix");
    if !secrets_file.is_file() {
        fs::write(&secrets_file, "{}\n")
            .map_err(|err| format!("failed to write {}: {}", secrets_file.display(), err))?;
        log(&format!("generated {}", secrets_file.display()));
    }
    ensure_file_mode(&secrets_file, 0o600)?;

    let age_key = env::var("SOPS_AGE_KEY_FILE")
        .ok()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var("HOME").unwrap_or_default()).join(".config/sops/age/keys.txt"));
    if !age_key.is_file() {
        if which("age-keygen").is_some() {
            let parent = age_key
                .parent()
                .ok_or_else(|| format!("invalid age key path: {}", age_key.display()))?;
            ensure_dir_mode(parent, 0o700)?;
            let mut age_keygen = Command::new("age-keygen");
            age_keygen.arg("-o");
            age_keygen.arg(&age_key);
            let status = run_command_status(&mut age_keygen)?;
            if status.success() {
                ensure_file_mode(&age_key, 0o600)?;
                log(&format!("generated sops age key at {}", age_key.display()));
            }
        } else {
            log("age-keygen not found (skipping sops key generation)");
        }
    }
    if age_key.is_file() {
        ensure_file_mode(&age_key, 0o600)?;
    }

    let mut doctor_args = Vec::new();
    if let Some(host_name) = host.as_deref() {
        doctor_args.push("--host".to_string());
        doctor_args.push(host_name.to_string());
        if let Some(rice_name) = rice.as_deref() {
            doctor_args.push("--rice".to_string());
            doctor_args.push(rice_name.to_string());
        }
    }
    if strict {
        doctor_args.push("--strict".to_string());
    }
    command_doctor(&doctor_args)?;

    if apply_after {
        let should_apply = if auto_yes {
            true
        } else if atty_stdin() {
            println!("bootstrap: run apply now? [y/N] ");
            let mut buffer = String::new();
            std::io::stdin()
                .read_line(&mut buffer)
                .map_err(|err| format!("failed to read prompt response: {}", err))?;
            matches!(buffer.trim(), "y" | "Y" | "yes" | "YES")
        } else {
            log("non-interactive shell; skipping apply");
            false
        };

        if should_apply {
            let mut apply_args = Vec::new();
            if let Some(host_name) = host.as_deref() {
                apply_args.push("--host".to_string());
                apply_args.push(host_name.to_string());
            }
            if let Some(rice_name) = rice.as_deref() {
                apply_args.push("--rice".to_string());
                apply_args.push(rice_name.to_string());
            }
            if no_sudo {
                apply_args.push("--no-sudo".to_string());
            }
            command_apply(&apply_args)?;
        } else {
            log("skipping apply");
        }
    }

    Ok(())
}

fn command_export_clean(args: &[String]) -> Result<(), String> {
    let mut format = "dir".to_string();
    let mut output = None::<PathBuf>;
    let mut index = 0usize;
    while index < args.len() {
        match args[index].as_str() {
            "--output" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --output".to_string())?;
                output = Some(PathBuf::from(value));
                index += 2;
            }
            "--format" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --format".to_string())?;
                format = value.clone();
                index += 2;
            }
            "-h" | "--help" => {
                println!("Usage: nix run .#dotfiles -- export-clean --output <path> [--format dir|tar]");
                return Ok(());
            }
            option => return Err(format!("unknown option: {}", option)),
        }
    }

    if format != "dir" && format != "tar" {
        return Err(format!("invalid --format: {} (expected dir or tar)", format));
    }
    let output = output.ok_or_else(|| "--output is required".to_string())?;

    let root = repo_root()?;
    if output.exists() {
        return Err(format!("output already exists: {}", output.display()));
    }
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
    }

    let temp = tempfile::tempdir().map_err(|err| format!("failed to create temp dir: {}", err))?;
    let export_root = temp.path().join("export");
    fs::create_dir_all(&export_root)
        .map_err(|err| format!("failed to create {}: {}", export_root.display(), err))?;

    let mut git_rev_parse = Command::new("git");
    git_rev_parse.current_dir(&root);
    git_rev_parse.arg("rev-parse");
    git_rev_parse.arg("--show-toplevel");
    let git_status = run_command_status(&mut git_rev_parse)?;
    if !git_status.success() {
        return Err("export-clean requires a trusted Git worktree with a working git binary".to_string());
    }

    for relative in git_tracked_files(&root)? {
        let src = root.join(&relative);
        let dest = export_root.join(&relative);
        if !src.exists() && fs::symlink_metadata(&src).is_err() {
            return Err(format!(
                "tracked path is missing from the working tree: {}",
                relative.display()
            ));
        }
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)
                .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
        }
        fs::copy(&src, &dest)
            .map_err(|err| format!("failed to copy {}: {}", relative.display(), err))?;
    }

    if format == "dir" {
        fs::rename(&export_root, &output)
            .map_err(|err| format!("failed to move export dir: {}", err))?;
    } else {
        let mut tar = Command::new("tar");
        tar.env("COPYFILE_DISABLE", "1");
        tar.arg("-C");
        tar.arg(&export_root);
        tar.arg("-cf");
        tar.arg(&output);
        tar.arg(".");
        let status = run_command_status(&mut tar)?;
        if !status.success() {
            exit_with_status(status);
        }
    }

    Ok(())
}

fn command_list_tools(args: &[String]) -> Result<(), String> {
    let parsed = parse_target_args(args, &["--format"])?;
    if parsed.has_passthrough {
        return Err("unexpected -- (no passthrough supported)".to_string());
    }
    let mut format = env::var("FORMAT").unwrap_or_else(|_| "text".to_string());
    let mut index = 0usize;
    while index < parsed.args.len() {
        match parsed.args[index].as_str() {
            "--format" => {
                format = parsed
                    .args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --format".to_string())?
                    .clone();
                index += 2;
            }
            "-h" | "--help" => {
                println!("Usage: nix run .#list-tools -- [--host <host>] [--rice <rice>] [--format json|text]");
                return Ok(());
            }
            option if option.starts_with("--") => return Err(format!("unknown option: {}", option)),
            other => return Err(format!("unexpected argument: {}", other)),
        }
    }
    if format != "json" && format != "text" {
        return Err(format!("invalid --format: {} (expected json or text)", format));
    }
    let host_env = env::var("HOST").ok();
    let host = require_host_argument(parsed.host.as_deref().or(host_env.as_deref()), "list-tools")?;
    let rice = parsed.rice.or_else(|| env::var("RICE").ok());
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let target = resolve_target(&root, &inputs, &host, rice.as_deref())
        .map_err(|err| explain_darwin_targets_error(&inputs, &err))?;
    let attr = format!("{}#darwinConfigurations.{}.config", flake_ref_for_root(&root), target);
    let tools_expr = root.join("nix/scripts/list-tools.nix");
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg(if format == "json" { "--json" } else { "--raw" });
    command.arg(attr);
    command.arg("--impure");
    command.arg("--apply");
    if format == "json" {
        command.arg(format!(
            "cfg: (import {} {{ }}).select cfg",
            tools_expr.display()
        ));
    } else {
        command.arg(format!(
            "cfg: (import {} {{ }}).text cfg",
            tools_expr.display()
        ));
    }
    command.args(nix_args_with_inputs(&inputs));
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        exit_with_status(output.status);
    }
    print!("{}", String::from_utf8_lossy(&output.stdout));
    if format == "json" {
        println!();
    }
    Ok(())
}

fn command_matrix_tools(args: &[String]) -> Result<(), String> {
    let mut format = env::var("FORMAT").unwrap_or_else(|_| "text".to_string());
    let mut full = false;
    let mut index = 0usize;
    while index < args.len() {
        match args[index].as_str() {
            "--format" => {
                format = args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --format".to_string())?
                    .clone();
                index += 2;
            }
            "--full" => {
                full = true;
                index += 1;
            }
            "-h" | "--help" => {
                println!("Usage: nix run .#matrix-tools -- [--format json|text] [--full]");
                return Ok(());
            }
            option => return Err(format!("unknown option: {}", option)),
        }
    }
    if format != "json" && format != "text" {
        return Err(format!("invalid --format: {} (expected json or text)", format));
    }
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let tools_expr = root.join("nix/scripts/matrix-tools.nix");
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg(if format == "json" { "--json" } else { "--raw" });
    command.arg(format!("{}#darwinConfigurations", flake_ref_for_root(&root)));
    command.arg("--impure");
    command.arg("--apply");
    command.arg(format!(
        "targets: (import {} {{ full = {}; }}).{} targets",
        tools_expr.display(),
        if full { "true" } else { "false" },
        if format == "json" { "json" } else { "text" }
    ));
    command.args(nix_args_with_inputs(&inputs));
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        exit_with_status(output.status);
    }
    print!("{}", String::from_utf8_lossy(&output.stdout));
    if format == "json" {
        println!();
    }
    Ok(())
}

fn command_sync(args: &[String]) -> Result<(), String> {
    if args.is_empty() {
        print_sync_usage();
        process::exit(1);
    }
    let surface = &args[0];
    let root = repo_root()?;
    let adapter = match surface.as_str() {
        "shell" => root.join("scripts/sync-adapters/shell.sh"),
        "vscode" => root.join("scripts/sync-adapters/vscode.sh"),
        "help" | "-h" | "--help" => {
            print_sync_usage();
            return Ok(());
        }
        _ => return Err(format!("unknown sync surface: {} (expected: shell or vscode)", surface)),
    };
    if !adapter.is_file() {
        return Err(format!("sync adapter script not found: {}", adapter.display()));
    }
    let mut command = Command::new("bash");
    command.arg(adapter);
    command.args(&args[1..]);
    let status = run_command_status(&mut command)?;
    if status.success() {
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn print_sync_usage() {
    println!(
        "Usage:
  nix run .#dotfiles -- sync shell [options]
  nix run .#dotfiles -- sync vscode [options]"
    );
}

fn which(name: &str) -> Option<PathBuf> {
    let path_var = env::var_os("PATH")?;
    for dir in env::split_paths(&path_var) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn atty_stdin() -> bool {
    use std::io::IsTerminal;
    std::io::stdin().is_terminal()
}

fn is_effective_root() -> bool {
    let mut id = Command::new("id");
    id.arg("-u");
    run_command_output(&mut id)
        .ok()
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .as_deref()
        == Some("0")
}
