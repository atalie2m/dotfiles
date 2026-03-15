use serde_json::Value;

use crate::apply::{
    file_intersection, file_minus_file, object_keys_unsorted, profile_id, read_json,
    read_json_object, unique_lines,
};
use crate::enablement_db::pending_default_disabled_extensions;
use crate::extension_manifest::list_profile_extensions;
use crate::profile_registry::{
    managed_profile_entry_matches_expected, validate_storage_json_shape,
};
use crate::settings::{all_desired_keys_match, project_settings_subset};
use crate::state::load_state_lists;
use crate::{Context, ProfileEvaluation, ProfilePlan, ProfileStatus, StateLists, StateLoad};

pub(crate) fn classify_profile(
    context: &Context,
    plan: &ProfilePlan,
) -> Result<ProfileEvaluation, String> {
    if context
        .managed_dir
        .join("_default/extensions-disabled.txt")
        .is_file()
    {
        return Ok(invalid(
            "apps/vscode/_default/extensions-disabled.txt is no longer supported",
        ));
    }

    if context
        .managed_dir
        .join("_default/launch-disabled-extensions.txt")
        .is_file()
    {
        return Ok(invalid(
            "apps/vscode/_default/launch-disabled-extensions.txt has been replaced by default-disabled-extensions.txt",
        ));
    }

    let state_load = load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)?;
    let (state_missing, state_lists) = match state_load {
        StateLoad::Invalid => {
            return Ok(needs_apply("state file schema changed or is malformed"));
        }
        StateLoad::Missing => (true, StateLists::default()),
        StateLoad::Loaded(lists) => (false, lists),
    };

    let desired_keys = object_keys_unsorted(&plan.desired_settings);
    let stale_keys = file_minus_file(&state_lists.owned_settings_keys, &desired_keys);
    let stale_extensions = file_minus_file(&state_lists.owned_extensions, &plan.desired_extensions);

    if !context.storage_json_path.is_file() {
        return Ok(missing("VS Code profile registry is missing"));
    }

    let storage_json = match read_json(&context.storage_json_path) {
        Ok(value) => value,
        Err(_) => return Ok(invalid("VS Code profile registry is not valid JSON")),
    };
    if let Err(reason) = validate_storage_json_shape(&storage_json) {
        return Ok(invalid(reason));
    }

    if !managed_profile_entry_matches_expected(
        &storage_json,
        &plan.profile_name,
        &profile_id(&plan.profile_dir_name),
    ) {
        return Ok(missing(
            "managed profile is not registered at the expected native profile location",
        ));
    }

    if !plan.runtime_dir.is_dir() {
        return Ok(missing("managed profile directory is missing"));
    }

    if !plan.settings_path.is_file() {
        return Ok(missing("managed profile settings file is missing"));
    }

    if !plan.extensions_manifest.is_file() {
        return Ok(missing("managed profile extensions manifest is missing"));
    }

    let actual_settings = match read_json_object(&plan.settings_path) {
        Ok(object) => object,
        Err(_) => return Ok(invalid("settings file is not valid JSON")),
    };

    let actual_extensions = match list_profile_extensions(context, &plan.profile_dir_name) {
        Ok(items) => items,
        Err(_) => return Ok(invalid("failed to inspect installed extensions")),
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
        return Ok(needs_apply_with_diff(
            "state file is missing",
            settings_diff_expected,
            settings_diff_actual,
            desired_missing,
            stale_installed,
        ));
    }

    if !all_desired_keys_match(&actual_settings, &plan.desired_settings, &desired_keys) {
        return Ok(needs_apply_with_diff(
            "managed settings differ from desired values",
            settings_diff_expected,
            settings_diff_actual,
            desired_missing,
            stale_installed,
        ));
    }

    if !stale_keys_present.is_empty() {
        return Ok(needs_apply_with_diff(
            "previously owned settings keys still exist locally",
            settings_diff_expected,
            settings_diff_actual,
            desired_missing,
            stale_installed,
        ));
    }

    if !desired_missing.is_empty() {
        return Ok(needs_apply_with_diff(
            "required extensions are missing",
            settings_diff_expected,
            settings_diff_actual,
            desired_missing,
            stale_installed,
        ));
    }

    if !stale_installed.is_empty() {
        return Ok(needs_apply_with_diff(
            "previously owned extensions still exist locally",
            settings_diff_expected,
            settings_diff_actual,
            desired_missing,
            stale_installed,
        ));
    }

    if !pending_default_disabled.is_empty() {
        return Ok(needs_apply_with_diff(
            "default-disabled extensions have not been bootstrapped yet",
            settings_diff_expected,
            settings_diff_actual,
            desired_missing,
            stale_installed,
        ));
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

fn invalid(reason: impl Into<String>) -> ProfileEvaluation {
    ProfileEvaluation {
        status: ProfileStatus::Invalid,
        reason: reason.into(),
        settings_diff_expected: None,
        settings_diff_actual: None,
        extensions_add: Vec::new(),
        extensions_remove: Vec::new(),
    }
}

fn missing(reason: impl Into<String>) -> ProfileEvaluation {
    ProfileEvaluation {
        status: ProfileStatus::Missing,
        reason: reason.into(),
        settings_diff_expected: None,
        settings_diff_actual: None,
        extensions_add: Vec::new(),
        extensions_remove: Vec::new(),
    }
}

fn needs_apply(reason: impl Into<String>) -> ProfileEvaluation {
    ProfileEvaluation {
        status: ProfileStatus::NeedsApply,
        reason: reason.into(),
        settings_diff_expected: None,
        settings_diff_actual: None,
        extensions_add: Vec::new(),
        extensions_remove: Vec::new(),
    }
}

fn needs_apply_with_diff(
    reason: impl Into<String>,
    expected: serde_json::Map<String, Value>,
    actual: serde_json::Map<String, Value>,
    extensions_add: Vec<String>,
    extensions_remove: Vec<String>,
) -> ProfileEvaluation {
    ProfileEvaluation {
        status: ProfileStatus::NeedsApply,
        reason: reason.into(),
        settings_diff_expected: Some(Value::Object(expected)),
        settings_diff_actual: Some(Value::Object(actual)),
        extensions_add,
        extensions_remove,
    }
}

#[cfg(test)]
mod tests {
    use super::classify_profile;
    use crate::apply::{
        profile_extensions_manifest_path, profile_id, profile_runtime_dir, profile_settings_path,
    };
    use crate::state::write_state_file;
    use crate::{Context, Mode, ProfilePlan, ProfileStatus};
    use serde_json::Map;
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
        std::fs::create_dir_all(&global_storage_dir).expect("globalStorage");
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

    fn write_minimal_runtime(context: &Context, profile_dir_name: &str, profile_name: &str) -> ProfilePlan {
        let runtime_dir = profile_runtime_dir(context, profile_dir_name);
        let settings_path = profile_settings_path(context, profile_dir_name);
        let extensions_manifest = profile_extensions_manifest_path(context, profile_dir_name);
        let state_file = context.state_dir.join(format!("{}.json", profile_dir_name));

        std::fs::create_dir_all(&runtime_dir).expect("runtime");
        std::fs::create_dir_all(settings_path.parent().expect("settings parent")).expect("settings parent");
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
        write_state_file(&state_file, profile_dir_name, profile_name, &[], &[], &[]).expect("state");

        ProfilePlan {
            profile_dir_name: profile_dir_name.to_string(),
            profile_name: profile_name.to_string(),
            desired_settings: Map::new(),
            desired_extensions: Vec::new(),
            desired_default_disabled: Vec::new(),
            state_file,
            settings_path,
            extensions_manifest,
            runtime_dir,
        }
    }

    #[test]
    fn classify_profile_fails_closed_on_unsupported_registry_shape() {
        let temp = tempfile::tempdir().expect("tempdir");
        let context = test_context(temp.path());
        let plan = write_minimal_runtime(&context, "focus", "Focus");
        std::fs::write(
            &context.storage_json_path,
            serde_json::to_vec_pretty(&json!({ "userDataProfiles": {} })).expect("json"),
        )
        .expect("storage");

        let eval = classify_profile(&context, &plan).expect("classify");
        assert_eq!(eval.status, ProfileStatus::Invalid);
        assert!(eval.reason.contains("userDataProfiles"));
    }
}
