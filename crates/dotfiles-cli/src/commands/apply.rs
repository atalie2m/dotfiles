use crate::commands::{is_effective_root, ApplyAction, ApplyArgs};
use dotfiles_core::support::{
    explain_darwin_targets_error, exit_with_status, flake_ref_for_root, nix_args_with_inputs,
    repo_root, require_host_argument, resolve_inputs, resolve_pinned_darwin_rebuild_bin,
    resolve_target, run_command_status, sudo_preserve_env_vars,
};
use std::env;
use std::process::Command;

pub(crate) fn command_apply(args: &ApplyArgs) -> Result<(), String> {
    let host_env = env::var("HOST").ok();
    let host = require_host_argument(
        args.target.host_value().or(host_env.as_deref()),
        "apply",
    )?;
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
        Ok(())
    } else {
        exit_with_status(status)
    }
}
