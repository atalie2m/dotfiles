use serde_json::Value;
use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::Duration;
use tempfile::NamedTempFile;

use crate::app::runtime::Context;
use crate::domain::model::{ProfileEvaluation, ProfilePlan, StateLists, StateLoad};
use crate::domain::state::{load_state_lists, write_state_file};
use crate::infra::collections::{file_intersection, file_minus_file};
use crate::infra::enablement_db::bootstrap_default_disabled_extensions;
use crate::infra::extension_manifest::{
    add_custom_profile_extension_membership as add_manifest_extension_membership,
    ensure_custom_profile_runtime as ensure_manifest_runtime,
    list_profile_extensions as list_manifest_profile_extensions, prune_orphaned_extension_dirs,
    remove_custom_profile_extension_membership as remove_manifest_extension_membership,
};
use crate::infra::json::{sort_object, write_json_atomically};
use crate::log;

pub(crate) fn apply_profile(context: &Context, plan: &ProfilePlan) -> Result<(), String> {
    ensure_profile_runtime(context, &plan.profile_dir_name, &plan.profile_name)?;

    let state_lists =
        match load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)? {
            StateLoad::Loaded(lists) => lists,
            StateLoad::Missing | StateLoad::Invalid => StateLists::default(),
        };

    let current_extensions = list_manifest_profile_extensions(context, &plan.profile_dir_name)?;
    let desired_missing = file_minus_file(&plan.desired_extensions, &current_extensions);
    let stale_owned_extensions =
        file_minus_file(&state_lists.owned_extensions, &plan.desired_extensions);
    let stale_installed = file_intersection(&stale_owned_extensions, &current_extensions);

    for extension_id in desired_missing {
        install_profile_extension(
            context,
            &plan.profile_dir_name,
            &plan.profile_name,
            &extension_id,
        )?;
    }

    for extension_id in stale_installed {
        uninstall_profile_extension(
            context,
            &plan.profile_dir_name,
            &plan.profile_name,
            &extension_id,
        )?;
    }

    let updated_bootstrapped_default_disabled = bootstrap_default_disabled_extensions(
        context,
        &plan.profile_dir_name,
        &plan.desired_default_disabled,
        &state_lists.bootstrapped_default_disabled_extensions,
    )?;

    write_json_atomically(
        &Value::Object(sort_object(&plan.desired_settings)),
        &plan.settings_path,
    )?;

    write_state_file(
        &plan.state_file,
        &plan.profile_dir_name,
        &plan.profile_name,
        &plan.desired_extensions,
        &updated_bootstrapped_default_disabled,
    )
}

pub(crate) fn prepare_apply_run(context: &Context) -> Result<(), String> {
    prune_orphaned_extension_dirs(context)
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
    let mut left_file =
        NamedTempFile::new().map_err(|err| format!("failed to create temp file: {}", err))?;
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

    ensure_manifest_runtime(context, profile_dir_name, profile_name)
}

fn install_profile_extension(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<(), String> {
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

    for entry in fs::read_dir(managed_dir).map_err(|err| {
        format!(
            "failed to read managed dir {}: {}",
            managed_dir.display(),
            err
        )
    })? {
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

pub(crate) fn profile_selected(filters: &[String], profile_dir_name: &str) -> bool {
    if filters.is_empty() {
        return true;
    }
    filters.iter().any(|filter| filter == profile_dir_name)
}

fn write_output_bytes(bytes: &[u8], stderr: bool) -> Result<(), String> {
    if bytes.is_empty() {
        return Ok(());
    }
    if stderr {
        let mut handle = std::io::stderr().lock();
        handle
            .write_all(bytes)
            .map_err(|err| format!("failed to write stderr: {}", err))?;
        handle
            .flush()
            .map_err(|err| format!("failed to flush stderr: {}", err))
    } else {
        let mut handle = std::io::stdout().lock();
        handle
            .write_all(bytes)
            .map_err(|err| format!("failed to write stdout: {}", err))?;
        handle
            .flush()
            .map_err(|err| format!("failed to flush stdout: {}", err))
    }
}

fn json_bytes(value: &Value) -> Result<Vec<u8>, String> {
    let mut bytes = serde_json::to_vec_pretty(value)
        .map_err(|err| format!("failed to encode diff JSON: {}", err))?;
    bytes.push(b'\n');
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::{apply_profile, prepare_apply_run};
    use crate::app::runtime::{Context, Mode};
    use crate::domain::model::ProfilePlan;
    use crate::infra::json::write_json_atomically;
    use crate::infra::paths::{
        profile_extensions_manifest_path, profile_id, profile_runtime_dir, profile_settings_path,
    };
    use serde_json::{json, Map, Value};
    use std::path::Path;

    fn test_context(root: &Path) -> Context {
        let managed_dir = root.join("managed");
        let state_dir = root.join("state");
        let user_data_home = root.join("user-data");
        let profiles_home = user_data_home.join("profiles");
        let global_storage_dir = user_data_home.join("globalStorage");
        let extensions_root = root.join("extensions");

        std::fs::create_dir_all(managed_dir.join("_default")).expect("managed");
        std::fs::create_dir_all(&global_storage_dir).expect("globalStorage");
        std::fs::create_dir_all(&extensions_root).expect("extensions");

        Context {
            managed_dir,
            state_dir,
            mode: Mode::Apply,
            details: false,
            diff_output: false,
            profile_filters: Vec::new(),
            code_bin: "/usr/bin/true".to_string(),
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

    fn write_minimal_runtime(
        context: &Context,
        profile_dir_name: &str,
        profile_name: &str,
    ) -> ProfilePlan {
        let runtime_dir = profile_runtime_dir(context, profile_dir_name);
        let settings_path = profile_settings_path(context, profile_dir_name);
        let extensions_manifest = profile_extensions_manifest_path(context, profile_dir_name);
        let state_file = context.state_dir.join(format!("{}.json", profile_dir_name));

        std::fs::create_dir_all(&runtime_dir).expect("runtime");
        std::fs::create_dir_all(settings_path.parent().expect("settings parent"))
            .expect("settings parent");
        std::fs::create_dir_all(context.storage_json_path.parent().expect("storage parent"))
            .expect("storage parent");
        std::fs::write(&settings_path, "{}\n").expect("settings");
        std::fs::write(&extensions_manifest, "[]\n").expect("manifest");
        std::fs::write(
            &context.storage_json_path,
            serde_json::to_vec_pretty(&json!({
                "userDataProfiles": [
                    { "name": profile_name, "location": profile_id(profile_dir_name) }
                ]
            }))
            .expect("json"),
        )
        .expect("storage");
        std::fs::create_dir_all(&context.state_dir).expect("state dir");

        ProfilePlan {
            profile_dir_name: profile_dir_name.to_string(),
            profile_name: profile_name.to_string(),
            desired_settings: Map::new(),
            desired_extensions: vec!["ext.base".to_string()],
            desired_default_disabled: Vec::new(),
            state_file,
            settings_path,
            extensions_manifest,
            runtime_dir,
        }
    }

    #[test]
    fn prepare_apply_run_prunes_orphans_before_apply() {
        let temp = tempfile::tempdir().expect("tempdir");
        let context = test_context(temp.path());
        let plan = write_minimal_runtime(&context, "focus", "Focus");

        let keep_dir = context.extensions_root.join("ext.base-1.0.0");
        let orphan_dir = context.extensions_root.join("orphan.me-1.0.0");
        std::fs::create_dir_all(&keep_dir).expect("keep");
        std::fs::create_dir_all(&orphan_dir).expect("orphan");
        write_json_atomically(
            &Value::Array(vec![json!({
                "identifier": { "id": "ext.base" },
                "relativeLocation": "ext.base-1.0.0"
            })]),
            &context.extensions_manifest_path,
        )
        .expect("global manifest");

        prepare_apply_run(&context).expect("prepare");
        assert!(!orphan_dir.exists());

        apply_profile(&context, &plan).expect("apply");

        let profile_manifest = std::fs::read_to_string(&plan.extensions_manifest).expect("profile");
        assert!(profile_manifest.contains("ext.base"));
    }
}
