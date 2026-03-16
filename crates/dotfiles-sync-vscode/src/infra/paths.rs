use sha2::{Digest, Sha256};
use std::path::PathBuf;

use crate::app::runtime::Context;

pub(crate) fn profile_display_name(profile_dir_name: &str) -> String {
    let words: Vec<String> = profile_dir_name
        .split(|c| c == '-' || c == '_')
        .filter(|word| !word.is_empty())
        .map(|word| {
            let lower = word.to_ascii_lowercase();
            let mut chars = lower.chars();
            if let Some(first) = chars.next() {
                format!("{}{}", first.to_ascii_uppercase(), chars.collect::<String>())
            } else {
                String::new()
            }
        })
        .filter(|word| !word.is_empty())
        .collect();

    words.join(" ")
}

pub(crate) fn profile_id(profile_dir_name: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(format!("dotfiles:vscode-profile:{}", profile_dir_name));
    let digest = hasher.finalize();
    let hex = format!("{:x}", digest);
    hex.chars().take(32).collect()
}

pub(crate) fn profile_state_file(context: &Context, profile_dir_name: &str) -> PathBuf {
    context.state_dir.join(format!("{}.json", profile_dir_name))
}

pub(crate) fn profile_runtime_dir(context: &Context, profile_dir_name: &str) -> PathBuf {
    context.profiles_home.join(profile_id(profile_dir_name))
}

pub(crate) fn profile_settings_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_runtime_dir(context, profile_dir_name).join("settings.json")
}

pub(crate) fn profile_extensions_manifest_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_runtime_dir(context, profile_dir_name).join("extensions.json")
}

pub(crate) fn profile_default_disabled_file_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    context
        .managed_dir
        .join(profile_dir_name)
        .join("default-disabled-extensions.txt")
}

pub(crate) fn profile_global_storage_dir(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_runtime_dir(context, profile_dir_name).join("globalStorage")
}

pub(crate) fn profile_enablement_db_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_global_storage_dir(context, profile_dir_name).join("state.vscdb")
}
