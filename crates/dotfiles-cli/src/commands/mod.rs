pub(crate) mod apply;
pub(crate) mod bootstrap;
pub(crate) mod doctor;
pub(crate) mod export_clean;
pub(crate) mod sync;
pub(crate) mod tools;
pub(crate) mod update;

use std::process;

#[derive(Clone)]
pub(crate) struct CheckRecord {
    pub(crate) name: String,
    pub(crate) status: String,
    pub(crate) message: String,
}

impl CheckRecord {
    pub(crate) fn new(name: &str, status: &str, message: impl Into<String>) -> Self {
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
        "apply" => apply::command_apply(tail),
        "update" => update::command_update(tail),
        "doctor" => doctor::command_doctor(tail),
        "bootstrap" => bootstrap::command_bootstrap(tail),
        "export-clean" => export_clean::command_export_clean(tail),
        "list-tools" => tools::command_list_tools(tail),
        "matrix-tools" => tools::command_matrix_tools(tail),
        "sync" => sync::command_sync(tail),
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

pub(crate) fn atty_stdin() -> bool {
    std::io::IsTerminal::is_terminal(&std::io::stdin())
}

pub(crate) fn is_effective_root() -> bool {
    let mut id = std::process::Command::new("id");
    id.arg("-u");
    dotfiles_core::support::run_command_output(&mut id)
        .ok()
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .as_deref()
        == Some("0")
}
