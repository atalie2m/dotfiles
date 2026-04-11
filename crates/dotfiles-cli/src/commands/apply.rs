use crate::commands::{eval_target_bool, is_effective_root, ApplyAction, ApplyArgs};
use dotfiles_core::support::{
    exit_with_status, explain_darwin_targets_error, find_in_path, flake_ref_for_root, log,
    nix_args_with_inputs, repo_root, require_host_argument, resolve_inputs,
    resolve_pinned_darwin_rebuild_bin, resolve_target, run_command_status, sudo_preserve_env_vars,
};
use std::env;
use std::path::PathBuf;
use std::process::Command;

pub(crate) fn command_apply(args: &ApplyArgs) -> Result<(), String> {
    let host_env = env::var("HOST").ok();
    let host = require_host_argument(args.target.host_value().or(host_env.as_deref()), "apply")?;
    let rice = args
        .target
        .rice_value()
        .map(ToOwned::to_owned)
        .or_else(|| env::var("RICE").ok());
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let target = resolve_target(&root, &inputs, &host, rice.as_deref())
        .map_err(|err| explain_darwin_targets_error(&inputs, &err))?;
    let flake_ref = flake_ref_for_root(&root);
    let darwin_rebuild_bin = resolve_pinned_darwin_rebuild_bin(&flake_ref)?;

    let needs_privilege =
        matches!(args.action, ApplyAction::Switch) && !args.no_sudo && !is_effective_root();

    let mut command = if !needs_privilege {
        Command::new(&darwin_rebuild_bin)
    } else {
        let mut sudo = Command::new("sudo");
        sudo.arg(format!("--preserve-env={}", sudo_preserve_env_vars()));
        sudo.arg(&darwin_rebuild_bin);
        sudo
    };

    command.arg(args.action.as_str());
    command.arg("--flake");
    command.arg(format!("{}#{}", flake_ref, target));
    command.args(nix_args_with_inputs(&inputs));
    command.args(&args.passthrough);

    let status = run_command_status(&mut command)?;
    if status.success() {
        emit_post_apply_advisories(&flake_ref, &inputs, &target, &host, rice.as_deref())?;
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn emit_post_apply_advisories(
    flake_ref: &str,
    inputs: &dotfiles_core::support::InputRefs,
    target: &str,
    host: &str,
    rice: Option<&str>,
) -> Result<(), String> {
    let claude_enabled = eval_target_bool(
        flake_ref,
        inputs,
        target,
        "myconfig.tools.aiCodingAgent.claudeCode.enable",
    )?;
    if claude_enabled != Some(true) {
        return Ok(());
    }

    let home = env::var("HOME")
        .map(PathBuf::from)
        .map_err(|_| "HOME is not set".to_string())?;
    let native_path = home.join(".local/bin/claude");
    let apply_command = claude_native_apply_command(host, rice);
    if native_path.is_file() {
        return Ok(());
    }

    match find_in_path("claude") {
        Some(found_path) => {
            log("Claude Code is enabled for this target, but dotfiles does not install it.");
            log(&format!(
                "found a non-native Claude launcher at {}; prefer the upstream native install at {}",
                found_path.display(),
                native_path.display()
            ));
            log("if that launcher came from Homebrew, remove it before reinstalling natively");
            log("see https://code.claude.com/docs/en/quickstart for the current native install flow");
            log(&format!(
                "after installing, run `{}`, then refresh your shell with `exec zsh -l` so the managed PATH picks up ~/.local/bin",
                apply_command
            ));
        }
        None => {
            log("Claude Code is enabled for this target, but dotfiles does not install it.");
            log("install Claude Code by following https://code.claude.com/docs/en/quickstart");
            log(&format!(
                "after installing, run `{}`, then refresh your shell with `exec zsh -l` so the managed PATH picks up {}",
                apply_command,
                native_path.parent().unwrap_or(&native_path).display()
            ));
        }
    }

    Ok(())
}

fn claude_native_apply_command(host: &str, rice: Option<&str>) -> String {
    match rice {
        Some(rice_name) => format!("nix run .#apply -- --host {} --rice {}", host, rice_name),
        None => format!("nix run .#apply -- --host {}", host),
    }
}
