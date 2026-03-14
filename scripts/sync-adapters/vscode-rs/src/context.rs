use std::collections::HashSet;
use std::env;
use std::path::PathBuf;

use crate::{CliArgs, Context};

pub(crate) fn build_context(args: CliArgs) -> Result<Context, String> {
    let managed_dir = if let Some(path) = args.managed_dir.clone() {
        path
    } else {
        resolve_repo_root()?.join("apps/vscode")
    };

    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    let state_dir = if let Some(path) = args.state_dir.clone() {
        path
    } else if let Ok(xdg_state_home) = env::var("XDG_STATE_HOME") {
        PathBuf::from(xdg_state_home).join("dotfiles/vscode")
    } else {
        PathBuf::from(home.clone()).join(".local/state/dotfiles/vscode")
    };

    if !managed_dir.is_dir() {
        return Err(format!("managed dir not found: {}", managed_dir.display()));
    }

    if !managed_dir.join("_default").is_dir() {
        return Err(format!(
            "managed default profile dir not found: {}",
            managed_dir.join("_default").display()
        ));
    }

    let code_bin = resolve_code_bin()?;

    if find_in_path("jq").is_none() {
        return Err("jq is required for sync vscode".to_string());
    }

    if find_in_path("sqlite3").is_none() {
        return Err("sqlite3 is required for sync vscode".to_string());
    }

    let vscode_data_home = env::var("VSCODE_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(home.clone()).join("Library/Application Support/Code"));
    let user_data_home = vscode_data_home.join("User");
    let profiles_home = user_data_home.join("profiles");
    let global_storage_dir = user_data_home.join("globalStorage");
    let storage_json_path = global_storage_dir.join("storage.json");

    let extensions_root = env::var("VSCODE_EXTENSIONS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(home.clone()).join(".vscode/extensions"));
    let extensions_manifest_path = extensions_root.join("extensions.json");

    let legacy_instances_dir = env::var("VSCODE_LEGACY_INSTANCES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(home).join(".local/share/vscode-instances"));

    let code_cli_retries = env::var("VSCODE_CODE_RETRIES")
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(3);

    Ok(Context {
        managed_dir,
        state_dir,
        mode: args.mode,
        details: args.details,
        diff_output: args.diff_output,
        profile_filters: args.profile_filters,
        code_bin,
        code_cli_retries,
        vscode_data_home,
        user_data_home,
        profiles_home,
        global_storage_dir,
        storage_json_path,
        extensions_root,
        extensions_manifest_path,
        legacy_instances_dir,
    })
}

fn resolve_repo_root() -> Result<PathBuf, String> {
    if let Ok(dotfiles_root) = env::var("DOTFILES_ROOT") {
        let root = PathBuf::from(&dotfiles_root);
        if !root.is_dir() {
            return Err(format!(
                "DOTFILES_ROOT is not a readable directory: {}",
                dotfiles_root
            ));
        }
        if !root.join("flake.nix").is_file() {
            return Err(format!(
                "unable to resolve flake root (expected flake.nix under {})",
                root.display()
            ));
        }
        return Ok(root);
    }

    let mut candidates: Vec<PathBuf> = Vec::new();

    if let Ok(exe_path) = env::current_exe() {
        for ancestor in exe_path.ancestors() {
            candidates.push(ancestor.to_path_buf());
        }
    }

    if let Ok(cwd) = env::current_dir() {
        for ancestor in cwd.ancestors() {
            candidates.push(ancestor.to_path_buf());
        }
    }

    let mut seen = HashSet::new();
    for candidate in candidates {
        let candidate_key = candidate.to_string_lossy().to_string();
        if !seen.insert(candidate_key) {
            continue;
        }

        if candidate.join("flake.nix").is_file() {
            return Ok(candidate);
        }
    }

    Err("unable to resolve flake root (expected flake.nix under repository root)".to_string())
}

fn resolve_code_bin() -> Result<String, String> {
    if let Ok(bin) = env::var("VSCODE_CODE_BIN") {
        if !bin.is_empty() {
            let configured = PathBuf::from(&bin);
            if configured.is_file() {
                return Ok(bin);
            }
            return Err(format!(
                "configured VS Code CLI is not executable: {}",
                configured.display()
            ));
        }
    }

    if let Some(path) = find_in_path("code") {
        return Ok(path.to_string_lossy().to_string());
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(home) = env::var("HOME") {
        candidates.push(
            PathBuf::from(home)
                .join("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"),
        );
    }
    candidates.push(PathBuf::from(
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
    ));

    for candidate in candidates {
        if candidate.is_file() {
            return Ok(candidate.to_string_lossy().to_string());
        }
    }

    Err(
        "VS Code CLI not found (set VSCODE_CODE_BIN, install 'code' in PATH, or install Visual Studio Code.app)"
            .to_string(),
    )
}

fn find_in_path(name: &str) -> Option<PathBuf> {
    let candidate = PathBuf::from(name);
    if candidate.components().count() > 1 {
        if candidate.exists() {
            return Some(candidate);
        }
        return None;
    }

    let path_var = env::var_os("PATH")?;
    for dir in env::split_paths(&path_var) {
        let full = dir.join(name);
        if full.exists() {
            return Some(full);
        }
    }

    None
}
