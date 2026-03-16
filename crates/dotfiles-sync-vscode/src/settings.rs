use serde_json::{Map, Value};

use crate::apply::{deep_merge, read_json_object, sort_json, sort_object};
use crate::Context;

pub(crate) fn all_desired_keys_match(
    actual_settings: &Map<String, Value>,
    desired_settings: &Map<String, Value>,
    desired_keys: &[String],
) -> bool {
    desired_keys.iter().all(|key| {
        actual_settings
            .get(key)
            .zip(desired_settings.get(key))
            .map(|(actual, desired)| actual == desired)
            .unwrap_or(false)
    })
}

pub(crate) fn apply_settings_owned_subset(
    actual_settings: &Map<String, Value>,
    desired_settings: &Map<String, Value>,
    desired_keys: &[String],
    stale_keys: &[String],
) -> Map<String, Value> {
    let mut updated = actual_settings.clone();

    for stale_key in stale_keys {
        updated.remove(stale_key);
    }

    for desired_key in desired_keys {
        if let Some(desired_value) = desired_settings.get(desired_key) {
            updated.insert(desired_key.clone(), desired_value.clone());
        }
    }

    sort_object(&updated)
}

pub(crate) fn project_settings_subset(input: &Map<String, Value>, keys: &[String]) -> Map<String, Value> {
    let mut projected = Map::new();

    for key in keys {
        if let Some(value) = input.get(key) {
            projected.insert(key.clone(), value.clone());
        }
    }

    projected
}


pub(crate) fn build_desired_settings(
    context: &Context,
    profile_dir_name: &str,
) -> Result<Map<String, Value>, String> {
    let default_settings = context.managed_dir.join("_default/settings.json");
    let profile_settings = context
        .managed_dir
        .join(profile_dir_name)
        .join("settings.json");

    let default_exists = default_settings.is_file();
    let profile_exists = profile_settings.is_file();

    if !default_exists && !profile_exists {
        return Ok(Map::new());
    }

    if !default_exists && profile_exists {
        return Ok(sort_object(&read_json_object(&profile_settings)?));
    }

    if default_exists && !profile_exists {
        return Ok(sort_object(&read_json_object(&default_settings)?));
    }

    let mut merged = Value::Object(read_json_object(&default_settings)?);
    let profile = Value::Object(read_json_object(&profile_settings)?);
    deep_merge(&mut merged, &profile);

    match sort_json(&merged) {
        Value::Object(object) => Ok(object),
        _ => Ok(Map::new()),
    }
}
