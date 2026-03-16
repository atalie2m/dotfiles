use std::fs;
use std::path::Path;

use crate::app::apply::{profile_default_disabled_file_path, unique_lines};
use crate::app::runtime::Context;

pub(crate) fn build_desired_extensions(
    context: &Context,
    profile_dir_name: &str,
) -> Result<Vec<String>, String> {
    let default_extensions = filter_extensions_file(&context.managed_dir.join("_default/extensions.txt"))?;
    let profile_extensions = filter_extensions_file(
        &context
            .managed_dir
            .join(profile_dir_name)
            .join("extensions.txt"),
    )?;

    let combined = [default_extensions, profile_extensions].concat();
    Ok(canonicalize_extension_ids(&combined))
}

pub(crate) fn build_desired_default_disabled_extensions(
    context: &Context,
    profile_dir_name: &str,
) -> Result<Vec<String>, String> {
    let default_disabled =
        filter_extensions_file(&profile_default_disabled_file_path(context, "_default"))?;
    let profile_disabled =
        filter_extensions_file(&profile_default_disabled_file_path(context, profile_dir_name))?;

    let combined = [default_disabled, profile_disabled].concat();
    Ok(canonicalize_extension_ids(&combined))
}

fn filter_extensions_file(path: &Path) -> Result<Vec<String>, String> {
    if !path.is_file() {
        return Ok(Vec::new());
    }

    let data = fs::read_to_string(path)
        .map_err(|err| format!("failed to read extensions file {}: {}", path.display(), err))?;

    let mut extensions = Vec::new();

    for line in data.lines() {
        let trimmed_start = line.trim_start();
        if trimmed_start.starts_with('#') {
            continue;
        }

        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        extensions.push(trimmed.to_string());
    }

    Ok(extensions)
}

fn canonicalize_extension_ids(ids: &[String]) -> Vec<String> {
    let mapped: Vec<String> = ids
        .iter()
        .map(|id| canonical_extension_id(id).to_string())
        .collect();
    unique_lines(&mapped)
}

pub(crate) fn canonical_extension_id(id: &str) -> &str {
    match id {
        "github.copilot" => "github.copilot-chat",
        _ => id,
    }
}
