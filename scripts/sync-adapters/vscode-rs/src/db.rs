use std::fs;
use std::path::Path;
use std::process::Command;

use serde_json::{Map, Value};

use crate::apply::{file_intersection, file_minus_file, profile_enablement_db_path, profile_global_storage_dir, unique_lines};
use crate::Context;

pub(crate) fn ensure_enablement_db(context: &Context, profile_dir_name: &str) -> Result<(), String> {
    let storage_dir = profile_global_storage_dir(context, profile_dir_name);
    let db_path = profile_enablement_db_path(context, profile_dir_name);

    fs::create_dir_all(&storage_dir)
        .map_err(|err| format!("failed to create profile globalStorage: {}", err))?;

    run_sqlite3(
        &db_path,
        "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);",
    )?;

    Ok(())
}

fn read_enablement_ids_from_db(db_path: &Path, key: &str) -> Result<Vec<String>, String> {
    if !db_path.is_file() {
        return Ok(Vec::new());
    }

    let escaped_key = sql_escape_single_quotes(key);
    let sql = format!("SELECT value FROM ItemTable WHERE key = '{}';", escaped_key);
    let raw_json = run_sqlite3(db_path, &sql)?;
    let raw_json = raw_json.trim();

    if raw_json.is_empty() {
        return Ok(Vec::new());
    }

    let parsed: Value = match serde_json::from_str(raw_json) {
        Ok(value) => value,
        Err(_) => return Ok(Vec::new()),
    };

    let mut ids: Vec<String> = parsed
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.get("id").and_then(Value::as_str).map(ToOwned::to_owned))
                .collect()
        })
        .unwrap_or_default();

    ids.sort();
    ids.dedup();
    Ok(ids)
}

fn write_enablement_ids_to_db(db_path: &Path, key: &str, ids: &[String]) -> Result<(), String> {
    let mut stable_ids = ids.to_vec();
    stable_ids.sort();
    stable_ids.dedup();

    let value_json = Value::Array(
        stable_ids
            .iter()
            .map(|id| {
                let mut entry = Map::new();
                entry.insert("id".to_string(), Value::String(id.clone()));
                Value::Object(entry)
            })
            .collect(),
    );

    let value_text = serde_json::to_string(&value_json)
        .map_err(|err| format!("failed to serialize enablement value: {}", err))?;

    let sql = format!(
        "INSERT INTO ItemTable(key, value) VALUES ('{}', '{}') ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
        sql_escape_single_quotes(key),
        sql_escape_single_quotes(&value_text)
    );

    run_sqlite3(db_path, &sql)?;
    Ok(())
}

pub(crate) fn bootstrap_default_disabled_extensions(
    context: &Context,
    profile_dir_name: &str,
    desired_default_disabled: &[String],
    seeded_default_disabled: &[String],
) -> Result<Vec<String>, String> {
    let mut output_seeded = file_intersection(seeded_default_disabled, desired_default_disabled);
    let pending_seed = pending_default_disabled_extensions(
        context,
        profile_dir_name,
        desired_default_disabled,
        seeded_default_disabled,
    )?;

    if pending_seed.is_empty() {
        return Ok(output_seeded);
    }

    ensure_enablement_db(context, profile_dir_name)?;

    let db_path = profile_enablement_db_path(context, profile_dir_name);
    let current_disabled = read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/disabled")?;
    let current_enabled = read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/enabled")?;

    let updated_disabled = unique_lines(&[current_disabled, pending_seed.clone()].concat());
    let updated_enabled = file_minus_file(&current_enabled, &pending_seed);
    output_seeded = unique_lines(&[output_seeded, pending_seed].concat());

    write_enablement_ids_to_db(&db_path, "extensionsIdentifiers/disabled", &updated_disabled)?;
    write_enablement_ids_to_db(&db_path, "extensionsIdentifiers/enabled", &updated_enabled)?;

    Ok(output_seeded)
}

pub(crate) fn pending_default_disabled_extensions(
    context: &Context,
    profile_dir_name: &str,
    desired_default_disabled: &[String],
    seeded_default_disabled: &[String],
) -> Result<Vec<String>, String> {
    let output_seeded = file_intersection(seeded_default_disabled, desired_default_disabled);
    if desired_default_disabled.is_empty() {
        return Ok(Vec::new());
    }

    let pending_seed_from_state = file_minus_file(desired_default_disabled, &output_seeded);
    let db_path = profile_enablement_db_path(context, profile_dir_name);
    if !db_path.is_file() {
        return Ok(unique_lines(
            &[pending_seed_from_state, desired_default_disabled.to_vec()].concat(),
        ));
    }

    let current_disabled = read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/disabled")?;
    let current_enabled = read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/enabled")?;
    let known_in_db = unique_lines(&[current_disabled, current_enabled].concat());
    let pending_seed_from_db = file_minus_file(desired_default_disabled, &known_in_db);

    Ok(unique_lines(
        &[pending_seed_from_state, pending_seed_from_db].concat(),
    ))
}

fn run_sqlite3(db_path: &Path, sql: &str) -> Result<String, String> {
    let output = Command::new("sqlite3")
        .arg(db_path)
        .arg(sql)
        .output()
        .map_err(|err| format!("failed to run sqlite3: {}", err))?;

    if !output.status.success() {
        return Err(format!(
            "sqlite3 failed for {}: {}",
            db_path.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn sql_escape_single_quotes(value: &str) -> String {
    value.replace('\'', "''")
}

