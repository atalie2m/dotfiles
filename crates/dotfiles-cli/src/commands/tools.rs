use dotfiles_core::support::{
    explain_darwin_targets_error, exit_with_status, flake_ref_for_root, nix_args_with_inputs,
    parse_target_args, repo_root, require_host_argument, resolve_inputs, resolve_target,
    run_command_output,
};
use std::env;
use std::process::Command;

pub(crate) fn command_list_tools(args: &[String]) -> Result<(), String> {
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
        command.arg(format!("cfg: (import {} {{ }}).select cfg", tools_expr.display()));
    } else {
        command.arg(format!("cfg: (import {} {{ }}).text cfg", tools_expr.display()));
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

pub(crate) fn command_matrix_tools(args: &[String]) -> Result<(), String> {
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
