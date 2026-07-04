use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{Map, Value};

use crate::app::runtime::Context;
use crate::infra::collections::{file_intersection, file_minus_file, unique_lines};
use crate::infra::paths::{profile_enablement_db_path, profile_global_storage_dir};

pub(crate) fn ensure_enablement_db(
    context: &Context,
    profile_dir_name: &str,
) -> Result<(), String> {
    let storage_dir = profile_global_storage_dir(context, profile_dir_name);
    let db_path = profile_enablement_db_path(context, profile_dir_name);
    ensure_enablement_db_path(&storage_dir, &db_path)
}

pub(crate) fn ensure_enablement_db_path(storage_dir: &Path, db_path: &Path) -> Result<(), String> {
    fs::create_dir_all(storage_dir)
        .map_err(|err| format!("failed to create profile globalStorage: {}", err))?;

    let connection = open_connection(db_path)?;
    connection
        .execute(
            "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);",
            [],
        )
        .map_err(|err| format!("failed to initialize enablement DB {}: {}", db_path.display(), err))?;

    Ok(())
}

pub(crate) fn read_enablement_ids_from_db(
    db_path: &Path,
    key: &str,
) -> Result<Vec<String>, String> {
    if !db_path.is_file() {
        return Ok(Vec::new());
    }

    let connection = open_connection(db_path)?;
    let raw_json = connection
        .query_row(
            "SELECT value FROM ItemTable WHERE key = ?1;",
            [key],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|err| {
            format!(
                "failed to read enablement DB {}: {}",
                db_path.display(),
                err
            )
        })?;
    let raw_json = raw_json.unwrap_or_default();
    let raw_json = raw_json.trim();

    if raw_json.is_empty() {
        return Ok(Vec::new());
    }

    let parsed: Value = serde_json::from_str(raw_json).map_err(|err| {
        format!(
            "enablement DB {} contains invalid JSON for key '{}': {}",
            db_path.display(),
            key,
            err
        )
    })?;

    let items = parsed.as_array().ok_or_else(|| {
        format!(
            "enablement DB {} key '{}' must contain a JSON array",
            db_path.display(),
            key
        )
    })?;

    let mut ids = Vec::new();
    for (index, item) in items.iter().enumerate() {
        let id = item.get("id").and_then(Value::as_str).ok_or_else(|| {
            format!(
                "enablement DB {} key '{}' contains an invalid entry at index {}",
                db_path.display(),
                key,
                index
            )
        })?;
        ids.push(id.to_string());
    }

    ids.sort();
    ids.dedup();
    Ok(ids)
}

pub(crate) fn write_enablement_ids_to_db(
    db_path: &Path,
    key: &str,
    ids: &[String],
) -> Result<(), String> {
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

    let connection = open_connection(db_path)?;
    connection
        .execute(
            "INSERT INTO ItemTable(key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
            params![key, value_text],
        )
        .map_err(|err| format!("failed to update enablement DB {}: {}", db_path.display(), err))?;
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

    write_enablement_ids_to_db(
        &db_path,
        "extensionsIdentifiers/disabled",
        &updated_disabled,
    )?;
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

fn open_connection(db_path: &Path) -> Result<Connection, String> {
    Connection::open(db_path).map_err(|err| {
        format!(
            "failed to open enablement DB {}: {}",
            db_path.display(),
            err
        )
    })
}

#[cfg(test)]
mod tests {
    use super::{
        bootstrap_default_disabled_extensions, ensure_enablement_db_path,
        pending_default_disabled_extensions, read_enablement_ids_from_db,
        write_enablement_ids_to_db,
    };
    use crate::app::runtime::{Context, Mode};
    use crate::infra::paths::profile_enablement_db_path;
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
    fn enablement_db_round_trips_ids() {
        let temp = tempfile::tempdir().expect("tempdir");
        let storage_dir = temp.path().join("globalStorage");
        let db_path = storage_dir.join("state.vscdb");

        ensure_enablement_db_path(&storage_dir, &db_path).expect("db");
        write_enablement_ids_to_db(
            &db_path,
            "extensionsIdentifiers/disabled",
            &[
                "zed.alpha".to_string(),
                "zed.alpha".to_string(),
                "zed.beta".to_string(),
            ],
        )
        .expect("write");

        let ids =
            read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/disabled").expect("read");
        assert_eq!(ids, vec!["zed.alpha".to_string(), "zed.beta".to_string()]);
    }

    #[test]
    fn bootstrap_default_disabled_seeds_missing_ids() {
        let temp = tempfile::tempdir().expect("tempdir");
        let context = test_context(temp.path());
        let seeded = bootstrap_default_disabled_extensions(
            &context,
            "focus",
            &["alpha.one".to_string(), "beta.two".to_string()],
            &["alpha.one".to_string()],
        )
        .expect("bootstrap");

        assert_eq!(
            seeded,
            vec!["alpha.one".to_string(), "beta.two".to_string()]
        );

        let db_path = profile_enablement_db_path(&context, "focus");
        let disabled =
            read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/disabled").expect("ids");
        assert_eq!(
            disabled,
            vec!["alpha.one".to_string(), "beta.two".to_string()]
        );

        let pending = pending_default_disabled_extensions(
            &context,
            "focus",
            &["alpha.one".to_string(), "beta.two".to_string()],
            &seeded,
        )
        .expect("pending");
        assert!(pending.is_empty());
    }

    #[test]
    fn invalid_enablement_json_fails_closed() {
        let temp = tempfile::tempdir().expect("tempdir");
        let storage_dir = temp.path().join("globalStorage");
        let db_path = storage_dir.join("state.vscdb");

        ensure_enablement_db_path(&storage_dir, &db_path).expect("db");
        let connection = rusqlite::Connection::open(&db_path).expect("open");
        connection
            .execute(
                "INSERT INTO ItemTable(key, value) VALUES (?1, ?2)",
                rusqlite::params!["extensionsIdentifiers/disabled", "{not-json"],
            )
            .expect("insert");

        let error = read_enablement_ids_from_db(&db_path, "extensionsIdentifiers/disabled")
            .expect_err("err");
        assert!(error.contains("contains invalid JSON"));
    }
}
