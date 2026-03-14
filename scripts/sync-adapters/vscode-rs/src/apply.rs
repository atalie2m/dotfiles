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

use crate::db::{bootstrap_default_disabled_extensions, ensure_enablement_db, pending_default_disabled_extensions};
use crate::extensions::canonical_extension_id;
use crate::settings::{all_desired_keys_match, apply_settings_owned_subset, project_settings_subset};
use crate::state::{load_state_lists, write_state_file};
use crate::{Context, ProfileEvaluation, ProfilePlan, ProfileStatus, StateLists, StateLoad};
use crate::log;

pub(crate) fn classify_profile(context: &Context, plan: &ProfilePlan) -> Result<ProfileEvaluation, String> {
    if context
        .managed_dir
        .join("_default/extensions-disabled.txt")
        .is_file()
    {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: "apps/vscode/_default/extensions-disabled.txt is no longer supported".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if profile_legacy_disabled_file_path(context, &plan.profile_dir_name).is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: format!(
                "apps/vscode/{}/extensions-disabled.txt is no longer supported",
                plan.profile_dir_name
            ),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if context
        .managed_dir
        .join("_default/launch-disabled-extensions.txt")
        .is_file()
    {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: "apps/vscode/_default/launch-disabled-extensions.txt has been replaced by default-disabled-extensions.txt".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if profile_legacy_launch_disabled_file_path(context, &plan.profile_dir_name).is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: format!(
                "apps/vscode/{}/launch-disabled-extensions.txt has been replaced by default-disabled-extensions.txt",
                plan.profile_dir_name
            ),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    let state_load = load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)?;
    let (state_missing, state_lists) = match state_load {
        StateLoad::Invalid => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::NeedsApply,
                reason: "state file schema changed or is malformed".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
        StateLoad::Missing => (true, StateLists::default()),
        StateLoad::Loaded(lists) => (false, lists),
    };

    let desired_keys = object_keys_unsorted(&plan.desired_settings);
    let stale_keys = file_minus_file(&state_lists.owned_settings_keys, &desired_keys);
    let stale_extensions = file_minus_file(&state_lists.owned_extensions, &plan.desired_extensions);

    if !context.storage_json_path.is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "VS Code profile registry is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    let storage_json = match read_json(&context.storage_json_path) {
        Ok(value) => value,
        Err(_) => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::Invalid,
                reason: "VS Code profile registry is not valid JSON".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
    };

    if !custom_profile_entry_matches_expected(
        &storage_json,
        &plan.profile_name,
        &profile_id(&plan.profile_dir_name),
    ) {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason:
                "managed profile is not registered at the expected native profile location".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if !plan.runtime_dir.is_dir() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "managed profile directory is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if !plan.settings_path.is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "managed profile settings file is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if !plan.extensions_manifest.is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "managed profile extensions manifest is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    let actual_settings = match read_json_object(&plan.settings_path) {
        Ok(object) => object,
        Err(_) => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::Invalid,
                reason: "settings file is not valid JSON".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
    };

    let actual_extensions = match list_profile_extensions(context, &plan.profile_dir_name) {
        Ok(items) => items,
        Err(_) => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::Invalid,
                reason: "failed to inspect installed extensions".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
    };

    let stale_installed = file_intersection(&stale_extensions, &actual_extensions);
    let desired_missing = file_minus_file(&plan.desired_extensions, &actual_extensions);

    let stale_keys_present: Vec<String> = stale_keys
        .iter()
        .filter(|key| actual_settings.contains_key(*key))
        .cloned()
        .collect();

    let combined_keys = unique_lines(&[desired_keys.clone(), stale_keys_present.clone()].concat());

    let settings_diff_expected = project_settings_subset(&plan.desired_settings, &desired_keys);
    let settings_diff_actual = project_settings_subset(&actual_settings, &combined_keys);

    let pending_default_disabled = pending_default_disabled_extensions(
        context,
        &plan.profile_dir_name,
        &plan.desired_default_disabled,
        &state_lists.bootstrapped_default_disabled_extensions,
    )?;

    if state_missing {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "state file is missing".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !all_desired_keys_match(&actual_settings, &plan.desired_settings, &desired_keys) {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "managed settings differ from desired values".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !stale_keys_present.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "previously owned settings keys still exist locally".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !desired_missing.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "required extensions are missing".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !stale_installed.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "previously owned extensions still exist locally".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !pending_default_disabled.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "default-disabled extensions have not been bootstrapped yet".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    Ok(ProfileEvaluation {
        status: ProfileStatus::InSync,
        reason: "managed settings and extensions match desired state".to_string(),
        settings_diff_expected: Some(Value::Object(settings_diff_expected)),
        settings_diff_actual: Some(Value::Object(settings_diff_actual)),
        extensions_add: desired_missing,
        extensions_remove: stale_installed,
    })
}

pub(crate) fn apply_profile(context: &Context, plan: &ProfilePlan) -> Result<(), String> {
    ensure_profile_runtime(context, &plan.profile_dir_name, &plan.profile_name)?;

    let state_lists = match load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)? {
        StateLoad::Loaded(lists) => lists,
        StateLoad::Missing | StateLoad::Invalid => StateLists::default(),
    };

    let desired_keys = object_keys_unsorted(&plan.desired_settings);
    let stale_keys = file_minus_file(&state_lists.owned_settings_keys, &desired_keys);

    let current_extensions = list_profile_extensions(context, &plan.profile_dir_name)?;
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

    let actual_settings = read_json_object(&plan.settings_path)?;
    let updated_settings = apply_settings_owned_subset(
        &actual_settings,
        &plan.desired_settings,
        &desired_keys,
        &stale_keys,
    );
    write_json_atomically(&Value::Object(updated_settings), &plan.settings_path)?;

    write_state_file(
        &plan.state_file,
        &plan.profile_dir_name,
        &plan.profile_name,
        &desired_keys,
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
    ensure_custom_profile_runtime(context, profile_dir_name, profile_name)
}

fn ensure_custom_profile_runtime(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
) -> Result<(), String> {
    let profile_location = profile_id(profile_dir_name);
    let profile_dir = profile_runtime_dir(context, profile_dir_name);
    let settings_path = profile_settings_path(context, profile_dir_name);
    let extensions_manifest = profile_extensions_manifest_path(context, profile_dir_name);

    ensure_custom_profile_registry(context, profile_name, &profile_location)?;
    fs::create_dir_all(&profile_dir).map_err(|err| {
        format!(
            "failed to create profile dir {}: {}",
            profile_dir.display(),
            err
        )
    })?;

    if !settings_path.is_file() {
        write_json_atomically(&Value::Object(Map::new()), &settings_path)?;
    } else {
        read_json(&settings_path)?;
    }

    if !extensions_manifest.is_file() {
        write_json_atomically(&Value::Array(Vec::new()), &extensions_manifest)?;
    } else {
        read_json(&extensions_manifest)?;
    }

    normalize_custom_profile_extension_manifest(context, profile_dir_name)?;
    ensure_enablement_db(context, profile_dir_name)
}

fn ensure_custom_profile_registry(
    context: &Context,
    profile_name: &str,
    profile_location: &str,
) -> Result<(), String> {
    ensure_storage_json_exists(context)?;

    let storage_value = read_json(&context.storage_json_path)?;
    let mut storage_object = match storage_value {
        Value::Object(obj) => obj,
        _ => return Err("storage.json must be an object".to_string()),
    };

    let existing = storage_object
        .remove("userDataProfiles")
        .and_then(|value| match value {
            Value::Array(items) => Some(items),
            _ => None,
        })
        .unwrap_or_default();

    let mut filtered: Vec<Value> = existing
        .into_iter()
        .filter(|item| {
            let Some(item_obj) = item.as_object() else {
                return true;
            };

            let item_name = item_obj
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let item_location = item_obj
                .get("location")
                .and_then(Value::as_str)
                .unwrap_or_default();

            !(item_name == profile_name || item_location == profile_location)
        })
        .collect();

    let mut profile_object = Map::new();
    profile_object.insert("name".to_string(), Value::String(profile_name.to_string()));
    profile_object.insert(
        "location".to_string(),
        Value::String(profile_location.to_string()),
    );
    filtered.push(Value::Object(profile_object));

    storage_object.insert("userDataProfiles".to_string(), Value::Array(filtered));
    write_json_atomically(&Value::Object(storage_object), &context.storage_json_path)
}

fn ensure_storage_json_exists(context: &Context) -> Result<(), String> {
    fs::create_dir_all(&context.global_storage_dir).map_err(|err| {
        format!(
            "failed to create global storage dir {}: {}",
            context.global_storage_dir.display(),
            err
        )
    })?;

    if context.storage_json_path.is_file() {
        read_json(&context.storage_json_path)?;
        return Ok(());
    }

    write_json_atomically(&Value::Object(Map::new()), &context.storage_json_path)
}

fn custom_profile_entry_matches_expected(
    storage_json: &Value,
    profile_name: &str,
    profile_location: &str,
) -> bool {
    let Some(storage_object) = storage_json.as_object() else {
        return false;
    };

    let profiles = storage_object
        .get("userDataProfiles")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    profiles.into_iter().any(|item| {
        let Some(item_obj) = item.as_object() else {
            return false;
        };

        item_obj
            .get("name")
            .and_then(Value::as_str)
            .map(|value| value == profile_name)
            .unwrap_or(false)
            && item_obj
                .get("location")
                .and_then(Value::as_str)
                .map(|value| value == profile_location)
                .unwrap_or(false)
    })
}


fn prune_orphaned_extension_dirs(context: &Context) -> Result<(), String> {
    if !context.extensions_root.is_dir() || !context.extensions_manifest_path.is_file() {
        return Ok(());
    }

    let manifest = read_json_array(&context.extensions_manifest_path)?;
    let mut keep = HashSet::new();

    for entry in manifest {
        if let Some(relative_location) = entry.get("relativeLocation").and_then(Value::as_str) {
            if !relative_location.is_empty() {
                keep.insert(relative_location.to_string());
            }
        }
    }

    for dir_entry in fs::read_dir(&context.extensions_root).map_err(|err| {
        format!(
            "failed to read extensions dir {}: {}",
            context.extensions_root.display(),
            err
        )
    })? {
        let dir_entry = dir_entry.map_err(|err| format!("failed to read extension dir entry: {}", err))?;
        let path = dir_entry.path();
        if !path.is_dir() {
            continue;
        }

        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };

        if keep.contains(name) {
            continue;
        }

        log(&format!(
            "Removing orphaned VS Code extension dir: {}",
            path.display()
        ));
        fs::remove_dir_all(&path)
            .map_err(|err| format!("failed to remove extension dir {}: {}", path.display(), err))?;
    }

    Ok(())
}

fn normalize_custom_profile_extension_manifest(
    context: &Context,
    profile_dir_name: &str,
) -> Result<(), String> {
    let manifest_path = profile_extensions_manifest_path(context, profile_dir_name);

    if !manifest_path.is_file() {
        return Ok(());
    }

    let manifest_entries = read_json_array(&manifest_path)?;
    let mut ids: Vec<String> = Vec::new();
    let mut seen = HashSet::new();

    for entry in &manifest_entries {
        let Some(extension_id) = entry
            .get("identifier")
            .and_then(Value::as_object)
            .and_then(|identifier| identifier.get("id"))
            .and_then(Value::as_str)
        else {
            continue;
        };

        if seen.insert(extension_id.to_string()) {
            ids.push(extension_id.to_string());
        }
    }

    let mut rebuilt: Vec<Value> = Vec::new();

    for extension_id in ids {
        if let Some(global_entry) = global_extension_manifest_entry(context, &extension_id)? {
            rebuilt.push(global_entry);
            continue;
        }

        if let Some(existing_entry) = find_last_extension_manifest_entry(&manifest_entries, &extension_id)
        {
            if extension_manifest_entry_has_existing_payload(context, &existing_entry) {
                rebuilt.push(existing_entry);
            }
        }
    }

    write_json_atomically(&Value::Array(rebuilt), &manifest_path)
}

fn global_extension_manifest_entry(
    context: &Context,
    extension_id: &str,
) -> Result<Option<Value>, String> {
    if !context.extensions_manifest_path.is_file() {
        return Ok(None);
    }

    let manifest_entries = match read_json_array(&context.extensions_manifest_path) {
        Ok(entries) => entries,
        Err(_) => return Ok(None),
    };

    let Some(entry) = find_last_extension_manifest_entry(&manifest_entries, extension_id) else {
        return Ok(None);
    };

    if extension_manifest_entry_has_existing_payload(context, &entry) {
        return Ok(Some(entry));
    }

    Ok(None)
}

fn find_last_extension_manifest_entry(entries: &[Value], extension_id: &str) -> Option<Value> {
    let needle = extension_id.to_ascii_lowercase();

    entries
        .iter()
        .rev()
        .find(|entry| {
            entry
                .get("identifier")
                .and_then(Value::as_object)
                .and_then(|identifier| identifier.get("id"))
                .and_then(Value::as_str)
                .map(|id| id.to_ascii_lowercase() == needle)
                .unwrap_or(false)
        })
        .cloned()
}

fn extension_manifest_entry_has_existing_payload(context: &Context, entry: &Value) -> bool {
    let location_exists = entry
        .get("location")
        .and_then(Value::as_object)
        .and_then(|location| location.get("path"))
        .and_then(Value::as_str)
        .map(|path| !path.is_empty() && Path::new(path).exists())
        .unwrap_or(false);
    if location_exists {
        return true;
    }

    entry.get("relativeLocation")
        .and_then(Value::as_str)
        .map(|relative_location| {
            !relative_location.is_empty() && context.extensions_root.join(relative_location).exists()
        })
        .unwrap_or(false)
}

fn add_custom_profile_extension_membership(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<bool, String> {
    let manifest_path = profile_extensions_manifest_path(context, profile_dir_name);

    ensure_custom_profile_runtime(context, profile_dir_name, profile_name)?;

    let Some(entry) = global_extension_manifest_entry(context, extension_id)? else {
        return Ok(false);
    };

    let lower_id = extension_id.to_ascii_lowercase();
    let mut entries = read_json_array(&manifest_path)?;

    entries.retain(|item| {
        item.get("identifier")
            .and_then(Value::as_object)
            .and_then(|identifier| identifier.get("id"))
            .and_then(Value::as_str)
            .map(|id| id.to_ascii_lowercase() != lower_id)
            .unwrap_or(true)
    });
    entries.push(entry);

    write_json_atomically(&Value::Array(entries), &manifest_path)?;
    Ok(true)
}

fn remove_custom_profile_extension_membership(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<(), String> {
    let manifest_path = profile_extensions_manifest_path(context, profile_dir_name);

    ensure_custom_profile_runtime(context, profile_dir_name, profile_name)?;

    let lower_id = extension_id.to_ascii_lowercase();
    let mut entries = read_json_array(&manifest_path)?;
    entries.retain(|item| {
        item.get("identifier")
            .and_then(Value::as_object)
            .and_then(|identifier| identifier.get("id"))
            .and_then(Value::as_str)
            .map(|id| id.to_ascii_lowercase() != lower_id)
            .unwrap_or(true)
    });

    write_json_atomically(&Value::Array(entries), &manifest_path)
}

fn install_profile_extension(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<(), String> {
    prune_orphaned_extension_dirs(context)?;

    if add_custom_profile_extension_membership(context, profile_dir_name, profile_name, extension_id)? {
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
        add_custom_profile_extension_membership(context, profile_dir_name, profile_name, extension_id)?;
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
    remove_custom_profile_extension_membership(context, profile_dir_name, profile_name, extension_id)
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

fn list_profile_extensions(context: &Context, profile_dir_name: &str) -> Result<Vec<String>, String> {
    let manifest_path = profile_extensions_manifest_path(context, profile_dir_name);

    if !manifest_path.is_file() {
        return Ok(Vec::new());
    }

    let entries = read_json_array(&manifest_path)?;
    let mut extension_ids: Vec<String> = entries
        .iter()
        .filter_map(|entry| {
            if !extension_manifest_entry_has_existing_payload(context, entry) {
                return None;
            }

            entry
                .get("identifier")
                .and_then(Value::as_object)
                .and_then(|identifier| identifier.get("id"))
                .and_then(Value::as_str)
                .map(|id| canonical_extension_id(id).to_string())
        })
        .collect();

    extension_ids.sort();
    extension_ids.dedup();

    Ok(extension_ids)
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

fn profile_id(profile_dir_name: &str) -> String {
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

fn profile_legacy_disabled_file_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    context
        .managed_dir
        .join(profile_dir_name)
        .join("extensions-disabled.txt")
}

fn profile_legacy_launch_disabled_file_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    context
        .managed_dir
        .join(profile_dir_name)
        .join("launch-disabled-extensions.txt")
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

pub(crate) fn object_keys_unsorted(object: &Map<String, Value>) -> Vec<String> {
    object.keys().cloned().collect()
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

