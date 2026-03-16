use serde_json::{Map, Value};

use crate::app::apply::{deep_merge, read_json_object, sort_json, sort_object};
use crate::app::runtime::Context;

pub(crate) fn settings_match(
    actual_settings: &Map<String, Value>,
    desired_settings: &Map<String, Value>,
) -> bool {
    sort_object(actual_settings) == sort_object(desired_settings)
}

pub(crate) fn settings_value(input: &Map<String, Value>) -> Value {
    Value::Object(sort_object(input))
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
