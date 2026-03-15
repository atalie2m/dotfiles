use serde_json::{Map, Value};
use std::collections::HashSet;
use std::fs;
use std::path::Path;

use crate::apply::{
    profile_extensions_manifest_path, profile_id, profile_runtime_dir, profile_settings_path,
    read_json, read_json_array, write_json_atomically,
};
use crate::enablement_db::ensure_enablement_db;
use crate::extensions::canonical_extension_id;
use crate::profile_registry::ensure_custom_profile_registry;
use crate::Context;
use crate::log;

pub(crate) fn ensure_custom_profile_runtime(
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

pub(crate) fn prune_orphaned_extension_dirs(context: &Context) -> Result<(), String> {
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

pub(crate) fn normalize_custom_profile_extension_manifest(
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

pub(crate) fn add_custom_profile_extension_membership(
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

pub(crate) fn remove_custom_profile_extension_membership(
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

pub(crate) fn list_profile_extensions(
    context: &Context,
    profile_dir_name: &str,
) -> Result<Vec<String>, String> {
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

#[cfg(test)]
mod tests {
    use super::{
        add_custom_profile_extension_membership, list_profile_extensions, prune_orphaned_extension_dirs,
        remove_custom_profile_extension_membership,
    };
    use crate::{Context, Mode};
    use serde_json::json;
    use std::path::Path;

    fn test_context(root: &Path) -> Context {
        let managed_dir = root.join("managed");
        let state_dir = root.join("state");
        let user_data_home = root.join("user-data");
        let profiles_home = user_data_home.join("profiles");
        let global_storage_dir = user_data_home.join("globalStorage");
        let extensions_root = root.join("extensions");

        std::fs::create_dir_all(managed_dir.join("_default")).expect("managed");
        std::fs::create_dir_all(&extensions_root).expect("extensions");

        Context {
            managed_dir,
            state_dir,
            mode: Mode::Check,
            details: false,
            diff_output: false,
            profile_filters: Vec::new(),
            code_bin: "code".to_string(),
            code_cli_retries: 1,
            vscode_data_home: root.join("vscode-data"),
            user_data_home,
            profiles_home,
            global_storage_dir: global_storage_dir.clone(),
            storage_json_path: global_storage_dir.join("storage.json"),
            extensions_root: extensions_root.clone(),
            extensions_manifest_path: extensions_root.join("extensions.json"),
        }
    }

    #[test]
    fn profile_membership_add_and_remove_round_trip() {
        let temp = tempfile::tempdir().expect("tempdir");
        let context = test_context(temp.path());
        let payload_dir = context.extensions_root.join("zed.alpha-1.0.0");
        std::fs::create_dir_all(&payload_dir).expect("payload");
        std::fs::write(
            &context.extensions_manifest_path,
            serde_json::to_vec_pretty(&json!([
                {
                    "identifier": { "id": "zed.alpha" },
                    "relativeLocation": "zed.alpha-1.0.0"
                }
            ]))
            .expect("json"),
        )
        .expect("write");

        let added = add_custom_profile_extension_membership(&context, "focus", "Focus", "zed.alpha")
            .expect("add");
        assert!(added);

        let listed = list_profile_extensions(&context, "focus").expect("list");
        assert_eq!(listed, vec!["zed.alpha".to_string()]);

        remove_custom_profile_extension_membership(&context, "focus", "Focus", "zed.alpha")
            .expect("remove");
        let listed = list_profile_extensions(&context, "focus").expect("list");
        assert!(listed.is_empty());
    }

    #[test]
    fn orphan_cleanup_removes_unowned_extension_dirs() {
        let temp = tempfile::tempdir().expect("tempdir");
        let context = test_context(temp.path());
        let keep_dir = context.extensions_root.join("keep.me-1.0.0");
        let orphan_dir = context.extensions_root.join("orphan.me-1.0.0");
        std::fs::create_dir_all(&keep_dir).expect("keep");
        std::fs::create_dir_all(&orphan_dir).expect("orphan");
        std::fs::write(
            &context.extensions_manifest_path,
            serde_json::to_vec_pretty(&json!([
                {
                    "identifier": { "id": "keep.me" },
                    "relativeLocation": "keep.me-1.0.0"
                }
            ]))
            .expect("json"),
        )
        .expect("write");

        prune_orphaned_extension_dirs(&context).expect("prune");
        assert!(keep_dir.exists());
        assert!(!orphan_dir.exists());
    }
}
