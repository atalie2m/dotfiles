use clap::error::ErrorKind;
use clap::Parser;
use std::env;
use std::path::PathBuf;
use std::process;

use crate::app::runtime::{CliArgs, Mode};

#[derive(Parser, Debug)]
#[command(
    name = "dotfiles-sync-vscode",
    about = "Reconcile repo-managed VS Code native profiles.",
    disable_version_flag = true
)]
struct VscodeCliArgs {
    #[arg(long, conflicts_with = "apply")]
    check: bool,
    #[arg(long, conflicts_with = "check")]
    apply: bool,
    #[arg(long)]
    details: bool,
    #[arg(long = "diff")]
    diff_output: bool,
    #[arg(long = "profile")]
    profile_filters: Vec<String>,
    #[arg(long = "managed-dir")]
    managed_dir: Option<PathBuf>,
    #[arg(long = "state-dir")]
    state_dir: Option<PathBuf>,
}

pub(crate) fn parse_args() -> Result<CliArgs, String> {
    let parsed = parse_or_display(VscodeCliArgs::try_parse_from(
        std::iter::once("dotfiles-sync-vscode".to_string()).chain(env::args().skip(1)),
    ))?;

    Ok(CliArgs {
        managed_dir: parsed.managed_dir,
        state_dir: parsed.state_dir,
        mode: if parsed.apply {
            Mode::Apply
        } else {
            Mode::Check
        },
        details: parsed.details,
        diff_output: parsed.diff_output,
        profile_filters: parsed.profile_filters,
    })
}

fn parse_or_display<T>(result: Result<T, clap::Error>) -> Result<T, String> {
    match result {
        Ok(value) => Ok(value),
        Err(err) => match err.kind() {
            ErrorKind::DisplayHelp | ErrorKind::DisplayVersion => {
                err.print()
                    .map_err(|io_error| format!("failed to print help: {}", io_error))?;
                process::exit(0);
            }
            _ => Err(err.to_string().trim_end().to_string()),
        },
    }
}
