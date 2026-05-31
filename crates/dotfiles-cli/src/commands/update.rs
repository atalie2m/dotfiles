use crate::commands::{ApplyAction, ApplyArgs, SelfUpdateArgs, TargetSelector, UpdateArgs};
use dotfiles_core::support::{
    exit_with_status, flake_ref_for_root, list_updateable_root_flake_inputs, log,
    nix_args_with_inputs, repo_root, require_host_argument, require_writable_checkout,
    resolve_inputs, run_command_output, run_command_status,
};
use std::env;
use std::process::Command;

pub(crate) fn command_update(args: &UpdateArgs) -> Result<(), String> {
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
        super::apply::command_apply(&ApplyArgs {
            target: TargetSelector {
                host,
                profile,
                host_positional: None,
            },
            action: ApplyAction::Build,
            no_sudo: false,
            passthrough: Vec::new(),
        })?;
    }

    Ok(())
}

pub(crate) fn command_self_update(args: &SelfUpdateArgs) -> Result<(), String> {
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
    require_host_argument(host.as_deref(), "self-update")?;

    if !args.no_user_profile {
        update_dotfiles_user_profile(false)?;
    }

    super::apply::command_apply(&ApplyArgs {
        target: TargetSelector {
            host,
            profile,
            host_positional: None,
        },
        action: args.action,
        no_sudo: args.no_sudo,
        passthrough: Vec::new(),
    })
}

pub(crate) fn update_dotfiles_user_profile(install_if_missing: bool) -> Result<(), String> {
    if default_user_profile_has_dotfiles()? {
        log("user nix profile: upgrading dotfiles entry");
        let mut command = Command::new("nix");
        command.arg("profile");
        command.arg("upgrade");
        command.arg("dotfiles");
        let status = run_command_status(&mut command)?;
        if status.success() {
            return Ok(());
        }
        exit_with_status(status);
    }

    if !install_if_missing {
        log("user nix profile: dotfiles entry not installed; skipped");
        return Ok(());
    }

    let root = repo_root()?;
    let flake_ref = flake_ref_for_root(&root);
    log(&format!(
        "user nix profile: installing dotfiles entry from {}",
        flake_ref
    ));
    let mut command = Command::new("nix");
    command.arg("profile");
    command.arg("install");
    command.arg(format!("{}#dotfiles", flake_ref));
    let status = run_command_status(&mut command)?;
    if status.success() {
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn default_user_profile_has_dotfiles() -> Result<bool, String> {
    let mut command = Command::new("nix");
    command.arg("profile");
    command.arg("list");
    command.arg("--json");
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "failed to inspect user nix profile for dotfiles entry: {}",
            stderr.trim()
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(profile_list_json_has_entry(&stdout, "dotfiles"))
}

fn profile_list_json_has_entry(profile_json: &str, name: &str) -> bool {
    profile_json.contains(&format!("\"{}\":", name))
}

#[cfg(test)]
mod tests {
    use super::profile_list_json_has_entry;

    #[test]
    fn profile_list_detection_matches_element_name_only() {
        assert!(profile_list_json_has_entry(
            r#"{"elements":{"dotfiles":{"active":true}},"version":3}"#,
            "dotfiles"
        ));
        assert!(!profile_list_json_has_entry(
            r#"{"elements":{"other":{"originalUrl":"github:atalie2m/dotfiles"}},"version":3}"#,
            "dotfiles"
        ));
    }
}
