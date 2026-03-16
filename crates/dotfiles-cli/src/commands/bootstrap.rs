use crate::commands::atty_stdin;
use dotfiles_core::support::{
    ensure_dir_mode, ensure_file_mode, ensure_inputs_dirs, render_bootstrap_facts, repo_root,
    require_host_argument, require_input_directories, resolve_inputs, run_command_output,
    run_command_status, log, parse_target_args,
};
use std::env;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::process::Command;

pub(crate) fn command_bootstrap(args: &[String]) -> Result<(), String> {
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
                run_command_output(&mut id)
                    .ok()
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
        if dotfiles_core::support::find_in_path("age-keygen").is_some() {
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

    if apply_after || strict {
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
        super::doctor::command_doctor(&doctor_args)?;
    }

    if apply_after {
        let should_apply = if auto_yes {
            true
        } else if atty_stdin() {
            println!("bootstrap: run apply now? [y/N] ");
            let mut buffer = String::new();
            io::stdin()
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
            super::apply::command_apply(&apply_args)?;
        } else {
            log("skipping apply");
        }
    }

    Ok(())
}
