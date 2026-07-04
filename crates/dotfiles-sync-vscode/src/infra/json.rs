use serde_json::{Map, Value};
use std::fs;
use std::io::Write;
use std::path::Path;
use tempfile::NamedTempFile;

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

    let mut temp_file = NamedTempFile::new_in(parent).map_err(|err| {
        format!(
            "failed to create temp file in {}: {}",
            parent.display(),
            err
        )
    })?;

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

fn json_bytes(value: &Value) -> Result<Vec<u8>, String> {
    let mut bytes = serde_json::to_vec_pretty(value)
        .map_err(|err| format!("failed to encode JSON: {}", err))?;
    bytes.push(b'\n');
    Ok(bytes)
}
