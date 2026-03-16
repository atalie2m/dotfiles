use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;
use tempfile::NamedTempFile;

use crate::app::runtime::Context;
use crate::domain::model::{ProfileEvaluation, ProfilePlan, StateLists, StateLoad};
use crate::domain::state::{load_state_lists, write_state_file};
use crate::infra::enablement_db::bootstrap_default_disabled_extensions;
use crate::infra::extension_manifest::{
    add_custom_profile_extension_membership as add_manifest_extension_membership,
    ensure_custom_profile_runtime as ensure_manifest_runtime,
    list_profile_extensions as list_manifest_profile_extensions,
    prune_orphaned_extension_dirs,
    remove_custom_profile_extension_membership as remove_manifest_extension_membership,
};
use crate::log;

pub(crate) fn apply_profile(context: &Context, plan: &ProfilePlan) -> Result<(), String> {
    ensure_profile_runtime(context, &plan.profile_dir_name, &plan.profile_name)?;

    let state_lists = match load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)? {
        StateLoad::Loaded(lists) => lists,
        StateLoad::Missing | StateLoad::Invalid => StateLists::default(),
    };

    let current_extensions = list_manifest_profile_extensions(context, &plan.profile_dir_name)?;
    let desired_missing = file_minus_file(&plan.desired_extensions, &current_extensions);
    let stale_owned_extensions = file_minus_file(&state_lists.owned_extensions, &plan.desired_extensions);
    let stale_installed = file_intersection(&stale_owned_extensions, &current_extensions);

    for extension_id in desired_missing {
        install_profile_extension(context, &plan.profile_dir_name, &plan.profile_name, &extension_id)?;
    }

    for extension_id in stale_installed {
        uninstall_profile_extension(context, &plan.profile_dir_name, &plan.profile_name, &extension_id)?;
    }

    let updated_bootstrapped_default_disabled = bootstrap_default_disabled_extensions(
        context,
        &plan.profile_dir_name,
        &plan.desired_default_disabled,
        &state_lists.bootstrapped_default_disabled_extensions,
    )?;

    write_json_atomically(&Value::Object(sort_object(&plan.desired_settings)), &plan.settings_path)?;

    write_state_file(
        &plan.state_file,
        &plan.profile_dir_name,
        &plan.profile_name,
        &plan.desired_extensions,
        &updated_bootstrapped_default_disabled,
    )
}

pub(crate) fn profile_details(plan: &ProfilePlan, eval: &ProfileEvaluation) {
    log(&format!("details: {}", plan.profile_dir_name));
    log(&format!("  profile-name: {}", plan.profile_name));
    log(&format!("  status: {}", eval.status.as_str()));
    log(&format!("  settings: {}", plan.settings_path.display()));
    log(&format!("  state: {}", plan.state_file.display()));
    log(&format!("  reason: {}", eval.reason));
}

pub(crate) fn profile_diff(plan: &ProfilePlan, eval: &ProfileEvaluation) -> Result<(), String> {
    log(&format!("diff: {}", plan.profile_dir_name));

    if let (Some(expected), Some(actual)) = (
        eval.settings_diff_expected.as_ref(),
        eval.settings_diff_actual.as_ref(),
    ) {
        print_unified_diff(expected, actual)?;
    }

    if !eval.extensions_add.is_empty() {
        log("  extensions-add:");
        for extension_id in &eval.extensions_add {
            eprintln!("  + {}", extension_id);
        }
    }

    if !eval.extensions_remove.is_empty() {
        log("  extensions-remove:");
        for extension_id in &eval.extensions_remove {
            eprintln!("  - {}", extension_id);
        }
    }

    Ok(())
}

fn print_unified_diff(expected: &Value, actual: &Value) -> Result<(), String> {
    let mut left_file = NamedTempFile::new().map_err(|err| format!("failed to create temp file: {}", err))?;
    let mut right_file =
        NamedTempFile::new().map_err(|err| format!("failed to create temp file: {}", err))?;

    let left_bytes = json_bytes(expected)?;
    let right_bytes = json_bytes(actual)?;

    left_file
        .write_all(&left_bytes)
        .map_err(|err| format!("failed to write diff input: {}", err))?;
    right_file
        .write_all(&right_bytes)
        .map_err(|err| format!("failed to write diff input: {}", err))?;

    let output = Command::new("diff")
        .arg("-u")
        .arg(left_file.path())
        .arg(right_file.path())
        .output()
        .map_err(|err| format!("failed to run diff: {}", err))?;

    write_output_bytes(&output.stdout, false)?;
    write_output_bytes(&output.stderr, true)?;

    Ok(())
}

fn ensure_profile_runtime(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
) -> Result<(), String> {
    fs::create_dir_all(&context.user_data_home).map_err(|err| {
        format!(
            "failed to create VS Code user data dir {}: {}",
            context.user_data_home.display(),
            err
        )
    })?;

    prune_orphaned_extension_dirs(context)?;
    ensure_manifest_runtime(context, profile_dir_name, profile_name)
}

fn install_profile_extension(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<(), String> {
    prune_orphaned_extension_dirs(context)?;

    if add_manifest_extension_membership(context, profile_dir_name, profile_name, extension_id)? {
        return Ok(());
    }

    let args = vec![
        OsString::from("--user-data-dir"),
        context.vscode_data_home.as_os_str().to_os_string(),
        OsString::from("--install-extension"),
        OsString::from(extension_id),
        OsString::from("--force"),
    ];

    if run_code_cli(context, &args)? {
        add_manifest_extension_membership(context, profile_dir_name, profile_name, extension_id)?;
        return Ok(());
    }

    Err(format!("failed to install extension '{}'", extension_id))
}

fn uninstall_profile_extension(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<(), String> {
    prune_orphaned_extension_dirs(context)?;
    remove_manifest_extension_membership(context, profile_dir_name, profile_name, extension_id)
}

fn run_code_cli(context: &Context, args: &[OsString]) -> Result<bool, String> {
    let mut attempt: u32 = 1;

    loop {
        let output = Command::new(&context.code_bin)
            .args(args)
            .output()
            .map_err(|err| format!("failed to run VS Code CLI '{}': {}", context.code_bin, err))?;

        if output.status.success() {
            write_output_bytes(&output.stdout, false)?;
            write_output_bytes(&output.stderr, true)?;
            return Ok(true);
        }

        let stderr_text = String::from_utf8_lossy(&output.stderr);
        let should_retry = attempt < context.code_cli_retries
            && (stderr_text.contains("FATAL ERROR: v8::ToLocalChecked Empty MaybeLocal")
                || stderr_text.contains("Abort trap: 6"));

        if should_retry {
            log(&format!(
                "VS Code CLI crashed; retrying ({}/{})",
                attempt, context.code_cli_retries
            ));
            attempt += 1;
            thread::sleep(Duration::from_secs(1));
            continue;
        }

        write_output_bytes(&output.stdout, false)?;
        write_output_bytes(&output.stderr, true)?;
        return Ok(false);
    }
}

pub(crate) fn list_managed_profiles(managed_dir: &Path) -> Result<Vec<String>, String> {
    let mut profiles = Vec::new();

    for entry in fs::read_dir(managed_dir)
        .map_err(|err| format!("failed to read managed dir {}: {}", managed_dir.display(), err))?
    {
        let entry = entry.map_err(|err| format!("failed to read managed dir entry: {}", err))?;
        let path = entry.path();

        if !path.is_dir() {
            continue;
        }

        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };

        if name == "_default" {
            continue;
        }

        profiles.push(name.to_string());
    }

    profiles.sort();
    Ok(profiles)
}

pub(crate) fn profile_selected(profile_filters: &[String], profile_name: &str) -> bool {
    if profile_filters.is_empty() {
        return true;
    }

    profile_filters.iter().any(|filter| filter == profile_name)
}

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

pub(crate) fn read_json(path: &Path) -> Result<Value, String> {
    let data = fs::read_to_string(path)
        .map_err(|err| format!("failed to read JSON file {}: {}", path.display(), err))?;

    serde_json::from_str(&data)
        .map_err(|err| format!("failed to parse JSON file {}: {}", path.display(), err))
}

pub(crate) fn read_json_object(path: &Path) -> Result<Map<String, Value>, String> {
    match read_json(path)? {
        Value::Object(object) => Ok(object),
        _ => Err(format!("JSON object expected at {}", path.display())),
    }
}

pub(crate) fn read_json_array(path: &Path) -> Result<Vec<Value>, String> {
    match read_json(path)? {
        Value::Array(items) => Ok(items),
        _ => Err(format!("JSON array expected at {}", path.display())),
    }
}

pub(crate) fn write_json_atomically(value: &Value, target_json: &Path) -> Result<(), String> {
    let parent = target_json
        .parent()
        .ok_or_else(|| format!("path has no parent: {}", target_json.display()))?;

    fs::create_dir_all(parent)
        .map_err(|err| format!("failed to create parent dir {}: {}", parent.display(), err))?;

    let mut temp_file = NamedTempFile::new_in(parent)
        .map_err(|err| format!("failed to create temp file in {}: {}", parent.display(), err))?;

    let sorted = sort_json(value);
    let bytes = json_bytes(&sorted)?;

    temp_file
        .write_all(&bytes)
        .map_err(|err| format!("failed to write temp JSON file: {}", err))?;

    temp_file
        .persist(target_json)
        .map_err(|err| format!("failed to replace {}: {}", target_json.display(), err.error))?;

    Ok(())
}

pub(crate) fn deep_merge(base: &mut Value, overlay: &Value) {
    match (base, overlay) {
        (Value::Object(base_map), Value::Object(overlay_map)) => {
            for (key, value) in overlay_map {
                match base_map.get_mut(key) {
                    Some(existing) => deep_merge(existing, value),
                    None => {
                        base_map.insert(key.clone(), value.clone());
                    }
                }
            }
        }
        (base_slot, overlay_value) => {
            *base_slot = overlay_value.clone();
        }
    }
}

pub(crate) fn sort_json(value: &Value) -> Value {
    match value {
        Value::Object(object) => {
            let mut keys: Vec<String> = object.keys().cloned().collect();
            keys.sort();

            let mut sorted = Map::new();
            for key in keys {
                if let Some(child) = object.get(&key) {
                    sorted.insert(key, sort_json(child));
                }
            }
            Value::Object(sorted)
        }
        Value::Array(items) => Value::Array(items.iter().map(sort_json).collect()),
        _ => value.clone(),
    }
}

pub(crate) fn sort_object(object: &Map<String, Value>) -> Map<String, Value> {
    match sort_json(&Value::Object(object.clone())) {
        Value::Object(sorted) => sorted,
        _ => Map::new(),
    }
}

pub(crate) fn file_minus_file(left: &[String], right: &[String]) -> Vec<String> {
    if left.is_empty() {
        return Vec::new();
    }

    if right.is_empty() {
        return left.to_vec();
    }

    let right_set: HashSet<&str> = right.iter().map(String::as_str).collect();
    left.iter()
        .filter(|item| !right_set.contains(item.as_str()))
        .cloned()
        .collect()
}

pub(crate) fn file_intersection(left: &[String], right: &[String]) -> Vec<String> {
    if left.is_empty() || right.is_empty() {
        return Vec::new();
    }

    let left_set: HashSet<&str> = left.iter().map(String::as_str).collect();
    right
        .iter()
        .filter(|item| left_set.contains(item.as_str()))
        .cloned()
        .collect()
}

pub(crate) fn unique_lines(lines: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut unique = Vec::new();

    for line in lines {
        if seen.insert(line.clone()) {
            unique.push(line.clone());
        }
    }

    unique
}

fn json_bytes(value: &Value) -> Result<Vec<u8>, String> {
    let mut bytes = serde_json::to_vec_pretty(value)
        .map_err(|err| format!("failed to encode JSON: {}", err))?;
    bytes.push(b'\n');
    Ok(bytes)
}

fn write_output_bytes(bytes: &[u8], stderr: bool) -> Result<(), String> {
    if bytes.is_empty() {
        return Ok(());
    }

    if stderr {
        let mut handle = std::io::stderr().lock();
        handle
            .write_all(bytes)
            .map_err(|err| format!("failed to write process stderr: {}", err))?;
        handle
            .flush()
            .map_err(|err| format!("failed to flush process stderr: {}", err))?;
    } else {
        let mut handle = std::io::stdout().lock();
        handle
            .write_all(bytes)
            .map_err(|err| format!("failed to write process stdout: {}", err))?;
        handle
            .flush()
            .map_err(|err| format!("failed to flush process stdout: {}", err))?;
    }

    Ok(())
}
