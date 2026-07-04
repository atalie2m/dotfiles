use std::env;
use std::path::PathBuf;

use dotfiles_core::support::{find_in_path, home_dir, is_executable_file, repo_root};

use crate::app::runtime::{CliArgs, Context};

pub(crate) fn build_context(args: CliArgs) -> Result<Context, String> {
    let managed_dir = if let Some(path) = args.managed_dir.clone() {
        path
    } else {
        repo_root()?.join("apps/vscode")
    };

    let home = home_dir()?;
    let state_dir = if let Some(path) = args.state_dir.clone() {
        path
    } else if let Ok(xdg_state_home) = env::var("XDG_STATE_HOME") {
        PathBuf::from(xdg_state_home).join("dotfiles/vscode")
    } else {
        home.join(".local/state/dotfiles/vscode")
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

    let vscode_data_home = env::var("VSCODE_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home.join("Library/Application Support/Code"));
    let user_data_home = vscode_data_home.join("User");
    let profiles_home = user_data_home.join("profiles");
    let global_storage_dir = user_data_home.join("globalStorage");
    let storage_json_path = global_storage_dir.join("storage.json");

    let extensions_root = env::var("VSCODE_EXTENSIONS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home.join(".vscode/extensions"));
    let extensions_manifest_path = extensions_root.join("extensions.json");

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
    })
}

fn resolve_code_bin() -> Result<String, String> {
    if let Ok(bin) = env::var("VSCODE_CODE_BIN") {
        if !bin.is_empty() {
            let configured = PathBuf::from(&bin);
            if is_executable_file(&configured) {
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
    candidates.push(
        home_dir()?.join("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"),
    );
    candidates.push(PathBuf::from(
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
    ));

    for candidate in candidates {
        if is_executable_file(&candidate) {
            return Ok(candidate.to_string_lossy().to_string());
        }
    }

    Err(
        "VS Code CLI not found (set VSCODE_CODE_BIN, install 'code' in PATH, or install Visual Studio Code.app)"
            .to_string(),
    )
}
