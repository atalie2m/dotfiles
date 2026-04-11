use crate::commands::{
    atty_stdin, ApplyAction, ApplyArgs, BootstrapArgs, DoctorArgs, TargetSelector,
};
use dotfiles_core::support::{
    ensure_dir_mode, ensure_file_mode, ensure_inputs_dirs, find_in_path, log,
    render_bootstrap_facts, repo_root, require_host_argument, require_input_directories,
    resolve_inputs, run_command_output, run_command_status,
};
use std::env;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::process::Command;

pub(crate) fn command_bootstrap(args: &BootstrapArgs) -> Result<(), String> {
    let apply_after = args.apply || args.yes;
    let auto_yes = args.yes;

    let host = args
        .target
        .host_value()
        .map(ToOwned::to_owned)
        .or_else(|| env::var("HOST").ok());
    let rice = args
        .target
        .rice_value()
        .map(ToOwned::to_owned)
        .or_else(|| env::var("RICE").ok());
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
        .unwrap_or_else(|| {
            PathBuf::from(env::var("HOME").unwrap_or_default()).join(".config/sops/age/keys.txt")
        });
    if !age_key.is_file() {
        if find_in_path("age-keygen").is_some() {
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

    if apply_after || args.strict {
        super::doctor::command_doctor(&DoctorArgs {
            target: TargetSelector {
                host: host.clone(),
                rice: rice.clone(),
                host_positional: None,
            },
            strict: args.strict,
            json: false,
        })?;
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
            super::apply::command_apply(&ApplyArgs {
                target: TargetSelector {
                    host,
                    rice,
                    host_positional: None,
                },
                action: ApplyAction::Switch,
                no_sudo: args.no_sudo,
                passthrough: Vec::new(),
            })?;
        } else {
            log("skipping apply");
        }
    }

    Ok(())
}
