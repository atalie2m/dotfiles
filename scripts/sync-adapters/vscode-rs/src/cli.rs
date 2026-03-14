use std::env;
use std::path::PathBuf;
use std::process;

use crate::{CliArgs, Mode};

fn usage() {
    println!(
        "Usage:
  nix run .#dotfiles -- sync vscode --check [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- sync vscode --apply [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]

Description:
  Keep repo-managed VS Code native profiles aligned with repo-managed settings
  and extensions while preserving unmanaged drift outside the owned subset.

Options:
  --check              Report in-sync / needs-apply / missing / invalid (default mode)
  --apply              Reconcile managed settings, extensions, and profile registry state
  --details            Print concise per-profile details
  --diff               Print projected settings diff and extension add/remove lists
  --profile <name>     Restrict to one managed profile dir name (repeatable)
  --managed-dir <path> Profile definitions directory (default: <repo>/apps/vscode)
  --state-dir <path>   Owned-subset state directory (default: ${{XDG_STATE_HOME:-$HOME/.local/state}}/dotfiles/vscode)
  --help               Show this help"
    );
}

pub(crate) fn parse_args() -> Result<CliArgs, String> {
    let mut args = env::args().skip(1).peekable();

    let mut managed_dir = None;
    let mut state_dir = None;
    let mut mode = Mode::Check;
    let mut mode_explicit = false;
    let mut details = false;
    let mut diff_output = false;
    let mut profile_filters: Vec<String> = Vec::new();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--check" => {
                if mode_explicit && mode != Mode::Check {
                    return Err("choose only one of --check or --apply".to_string());
                }
                mode = Mode::Check;
                mode_explicit = true;
            }
            "--apply" => {
                if mode_explicit && mode != Mode::Apply {
                    return Err("choose only one of --check or --apply".to_string());
                }
                mode = Mode::Apply;
                mode_explicit = true;
            }
            "--details" => details = true,
            "--diff" => diff_output = true,
            "--profile" => {
                let value = args
                    .next()
                    .ok_or_else(|| "missing value for --profile".to_string())?;
                if !profile_filters.iter().any(|entry| entry == &value) {
                    profile_filters.push(value);
                }
            }
            "--managed-dir" => {
                let value = args
                    .next()
                    .ok_or_else(|| "missing value for --managed-dir".to_string())?;
                managed_dir = Some(PathBuf::from(value));
            }
            "--state-dir" => {
                let value = args
                    .next()
                    .ok_or_else(|| "missing value for --state-dir".to_string())?;
                state_dir = Some(PathBuf::from(value));
            }
            "--help" | "-h" => {
                usage();
                process::exit(0);
            }
            _ => {
                return Err(format!("unknown option for sync vscode: {}", arg));
            }
        }
    }

    Ok(CliArgs {
        managed_dir,
        state_dir,
        mode,
        details,
        diff_output,
        profile_filters,
    })
}
