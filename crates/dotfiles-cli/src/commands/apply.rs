use crate::commands::is_effective_root;
use dotfiles_core::support::{
    explain_darwin_targets_error, exit_with_status, flake_ref_for_root, nix_args_with_inputs,
    parse_target_args, repo_root, require_host_argument, resolve_inputs,
    resolve_pinned_darwin_rebuild_bin, resolve_target, run_command_status, sudo_preserve_env_vars,
};
use std::env;
use std::process::Command;

pub(crate) fn command_apply(args: &[String]) -> Result<(), String> {
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
            arg => {
                return Err(format!(
                    "unexpected argument: {} (use -- to pass through to darwin-rebuild)",
                    arg
                ))
            }
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

    let needs_privilege = action == "switch" && !no_sudo && !is_effective_root();

    let mut command = if !needs_privilege {
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
