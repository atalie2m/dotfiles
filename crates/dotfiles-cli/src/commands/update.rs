use dotfiles_core::support::{
    exit_with_status, flake_ref_for_root, list_updateable_root_flake_inputs, nix_args_with_inputs,
    parse_target_args, repo_root, require_host_argument, require_writable_checkout, resolve_inputs,
    run_command_status,
};
use std::env;
use std::process::Command;

pub(crate) fn command_update(args: &[String]) -> Result<(), String> {
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
        let mut apply_args = vec!["--action".to_string(), "build".to_string()];
        if let Some(host_name) = host {
            apply_args.push("--host".to_string());
            apply_args.push(host_name);
        }
        if let Some(rice_name) = rice {
            apply_args.push("--rice".to_string());
            apply_args.push(rice_name);
        }
        super::apply::command_apply(&apply_args)?;
    }

    Ok(())
}
