use crate::commands::{ListToolsArgs, MatrixToolsArgs, OutputFormat};
use dotfiles_core::support::{
    explain_darwin_targets_error, exit_with_status, flake_ref_for_root, nix_args_with_inputs,
    repo_root, require_host_argument, resolve_inputs, resolve_target, run_command_output,
};
use std::env;
use std::process::Command;

pub(crate) fn command_list_tools(args: &ListToolsArgs) -> Result<(), String> {
    let host_env = env::var("HOST").ok();
    let host = require_host_argument(
        args.target.host_value().or(host_env.as_deref()),
        "list-tools",
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
    let attr = format!("{}#darwinConfigurations.{}.config", flake_ref_for_root(&root), target);
    let tools_expr = root.join("nix/scripts/list-tools.nix");
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg(match args.format {
        OutputFormat::Json => "--json",
        OutputFormat::Text => "--raw",
    });
    command.arg(attr);
    command.arg("--impure");
    command.arg("--apply");
    command.arg(match args.format {
        OutputFormat::Json => format!("cfg: (import {} {{ }}).select cfg", tools_expr.display()),
        OutputFormat::Text => format!("cfg: (import {} {{ }}).text cfg", tools_expr.display()),
    });
    command.args(nix_args_with_inputs(&inputs));
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        exit_with_status(output.status);
    }
    print!("{}", String::from_utf8_lossy(&output.stdout));
    if matches!(args.format, OutputFormat::Json) {
        println!();
    }
    Ok(())
}

pub(crate) fn command_matrix_tools(args: &MatrixToolsArgs) -> Result<(), String> {
    let root = repo_root()?;
    let inputs = resolve_inputs()?;
    let tools_expr = root.join("nix/scripts/matrix-tools.nix");
    let format_name = args.format.as_str();
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg(match args.format {
        OutputFormat::Json => "--json",
        OutputFormat::Text => "--raw",
    });
    command.arg(format!("{}#darwinConfigurations", flake_ref_for_root(&root)));
    command.arg("--impure");
    command.arg("--apply");
    command.arg(format!(
        "targets: (import {} {{ full = {}; }}).{} targets",
        tools_expr.display(),
        if args.full { "true" } else { "false" },
        format_name
    ));
    command.args(nix_args_with_inputs(&inputs));
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        exit_with_status(output.status);
    }
    print!("{}", String::from_utf8_lossy(&output.stdout));
    if matches!(args.format, OutputFormat::Json) {
        println!();
    }
    Ok(())
}
