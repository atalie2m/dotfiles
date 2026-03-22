use crate::commands::{SyncArgs, SyncSurface};
use dotfiles_core::shell_sync;
use dotfiles_core::support::{exit_with_status, find_in_path, repo_root, run_command_status};
use std::env;
use std::path::PathBuf;
use std::process::{self, Command};

pub(crate) fn command_sync(args: &SyncArgs) -> Result<(), String> {
    match args.surface {
        SyncSurface::Shell => {
            let result = shell_sync::run_cli(&args.args)?;
            let exit_code = result.exit_code(shell_sync::ShellSyncMode::Check);
            let effective = if args.args.iter().any(|arg| arg == "--apply") {
                result.exit_code(shell_sync::ShellSyncMode::Apply)
            } else {
                exit_code
            };
            if effective == 0 {
                Ok(())
            } else {
                process::exit(effective)
            }
        }
        SyncSurface::Vscode => {
            let engine = resolve_sync_vscode_bin()?;
            let mut command = Command::new(engine);
            command.args(&args.args);
            let status = run_command_status(&mut command)?;
            if status.success() {
                Ok(())
            } else {
                exit_with_status(status)
            }
        }
    }
}

pub(crate) fn resolve_sync_vscode_bin() -> Result<PathBuf, String> {
    if let Ok(bin) = env::var("DOTFILES_SYNC_VSCODE_BIN") {
        if !bin.is_empty() {
            let configured = PathBuf::from(&bin);
            if configured.is_file() {
                return Ok(configured);
            }
            return Err(format!(
                "configured VS Code sync binary is not executable: {}",
                configured.display()
            ));
        }
    }

    if let Some(path) = find_in_path("dotfiles-sync-vscode") {
        return Ok(path);
    }

    let root = repo_root()?;
    let local = root.join("result/bin/dotfiles-sync-vscode");
    if local.is_file() {
        return Ok(local);
    }

    Err("dotfiles-sync-vscode binary not found (set DOTFILES_SYNC_VSCODE_BIN or add it to PATH)".to_string())
}
