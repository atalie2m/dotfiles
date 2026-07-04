use serde_json::{Map, Value};
use std::fs;

use crate::app::runtime::Context;
use crate::infra::json::{read_json, write_json_atomically};

pub(crate) fn ensure_custom_profile_registry(
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

    let existing = read_user_data_profiles(&mut storage_object)?;

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

pub(crate) fn ensure_storage_json_exists(context: &Context) -> Result<(), String> {
    fs::create_dir_all(&context.global_storage_dir).map_err(|err| {
        format!(
            "failed to create global storage dir {}: {}",
            context.global_storage_dir.display(),
            err
        )
    })?;

    if context.storage_json_path.is_file() {
        validate_storage_json_shape(&read_json(&context.storage_json_path)?)?;
        return Ok(());
    }

    write_json_atomically(&Value::Object(Map::new()), &context.storage_json_path)
}

pub(crate) fn validate_storage_json_shape(storage_json: &Value) -> Result<(), String> {
    let Some(storage_object) = storage_json.as_object() else {
        return Err("storage.json must be an object".to_string());
    };

    match storage_object.get("userDataProfiles") {
        None | Some(Value::Array(_)) => Ok(()),
        Some(_) => {
            Err("unsupported storage.json shape: userDataProfiles must be an array".to_string())
        }
    }
}

pub(crate) fn managed_profile_entry_matches_expected(
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

fn read_user_data_profiles(storage_object: &mut Map<String, Value>) -> Result<Vec<Value>, String> {
    match storage_object.remove("userDataProfiles") {
        None => Ok(Vec::new()),
        Some(Value::Array(items)) => Ok(items),
        Some(_) => {
            Err("unsupported storage.json shape: userDataProfiles must be an array".to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ensure_custom_profile_registry, validate_storage_json_shape};
    use crate::app::runtime::{Context, Mode};
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
    fn registry_upsert_replaces_conflicting_entries() {
        let temp = tempfile::tempdir().expect("tempdir");
        let context = test_context(temp.path());
        std::fs::create_dir_all(&context.global_storage_dir).expect("globalStorage");
        std::fs::write(
            &context.storage_json_path,
            serde_json::to_vec_pretty(&json!({
                "userDataProfiles": [
                    { "name": "Focus", "location": "old-focus" },
                    { "name": "Other", "location": "other" },
                    { "name": "Spare", "location": "focus-profile" }
                ]
            }))
            .expect("json"),
        )
        .expect("write");

        ensure_custom_profile_registry(&context, "Focus", "focus-profile").expect("upsert");

        let actual: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&context.storage_json_path).expect("read"))
                .expect("parse");
        let profiles = actual
            .get("userDataProfiles")
            .and_then(serde_json::Value::as_array)
            .expect("profiles");

        assert!(profiles.iter().any(|item| {
            item.get("name").and_then(serde_json::Value::as_str) == Some("Focus")
                && item.get("location").and_then(serde_json::Value::as_str) == Some("focus-profile")
        }));
        assert!(profiles.iter().any(|item| {
            item.get("name").and_then(serde_json::Value::as_str) == Some("Other")
                && item.get("location").and_then(serde_json::Value::as_str) == Some("other")
        }));
        assert_eq!(profiles.len(), 2);
    }

    #[test]
    fn registry_rejects_unsupported_user_data_profiles_shape() {
        let error =
            validate_storage_json_shape(&json!({ "userDataProfiles": {} })).expect_err("shape");
        assert!(error.contains("userDataProfiles"));
    }
}
