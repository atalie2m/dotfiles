use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::fs;
use std::path::PathBuf;
use std::process;

mod apply;
mod cli;
mod context;
mod db;
mod extensions;
mod settings;
mod state;

pub(crate) const SCRIPT_LABEL: &str = "sync-vscode";
pub(crate) const STATE_VERSION: u32 = 3;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Check,
    Apply,
}

#[derive(Clone)]
struct CliArgs {
    managed_dir: Option<PathBuf>,
    state_dir: Option<PathBuf>,
    mode: Mode,
    details: bool,
    diff_output: bool,
    profile_filters: Vec<String>,
}

#[derive(Clone)]
struct Context {
    managed_dir: PathBuf,
    state_dir: PathBuf,
    mode: Mode,
    details: bool,
    diff_output: bool,
    profile_filters: Vec<String>,
    code_bin: String,
    code_cli_retries: u32,
    vscode_data_home: PathBuf,
    user_data_home: PathBuf,
    profiles_home: PathBuf,
    global_storage_dir: PathBuf,
    storage_json_path: PathBuf,
    extensions_root: PathBuf,
    extensions_manifest_path: PathBuf,
    legacy_instances_dir: PathBuf,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ProfileStatus {
    InSync,
    NeedsApply,
    Missing,
    Invalid,
}

impl ProfileStatus {
    fn as_str(self) -> &'static str {
        match self {
            ProfileStatus::InSync => "in-sync",
            ProfileStatus::NeedsApply => "needs-apply",
            ProfileStatus::Missing => "missing",
            ProfileStatus::Invalid => "invalid",
        }
    }
}

#[derive(Clone)]
struct ProfilePlan {
    profile_dir_name: String,
    profile_name: String,
    desired_settings: Map<String, Value>,
    desired_extensions: Vec<String>,
    desired_default_disabled: Vec<String>,
    state_file: PathBuf,
    settings_path: PathBuf,
    extensions_manifest: PathBuf,
    runtime_dir: PathBuf,
}

#[derive(Clone)]
struct ProfileEvaluation {
    status: ProfileStatus,
    reason: String,
    settings_diff_expected: Option<Value>,
    settings_diff_actual: Option<Value>,
    extensions_add: Vec<String>,
    extensions_remove: Vec<String>,
}

#[derive(Clone, Default)]
struct StateLists {
    owned_settings_keys: Vec<String>,
    owned_extensions: Vec<String>,
    bootstrapped_default_disabled_extensions: Vec<String>,
}

enum StateLoad {
    Missing,
    Invalid,
    Loaded(StateLists),
}

#[derive(Serialize, Deserialize)]
struct StateFile {
    version: u32,
    #[serde(rename = "profileDirName")]
    profile_dir_name: String,
    #[serde(rename = "profileName")]
    profile_name: String,
    #[serde(rename = "ownedSettingsKeys")]
    owned_settings_keys: Vec<String>,
    #[serde(rename = "ownedExtensions")]
    owned_extensions: Vec<String>,
    #[serde(rename = "bootstrappedDefaultDisabledExtensions")]
    bootstrapped_default_disabled_extensions: Vec<String>,
}

#[derive(Default)]
struct Summary {
    selected_count: u32,
    checked: u32,
    in_sync: u32,
    needs_apply: u32,
    missing: u32,
    invalid: u32,
    applied: u32,
    errors: u32,
}

fn main() {
    if let Err(err) = run() {
        die(&err);
    }
}

fn run() -> Result<(), String> {
    let cli_args = cli::parse_args()?;
    let context = context::build_context(cli_args)?;

    let mut summary = Summary::default();
    let managed_profiles = apply::list_managed_profiles(&context.managed_dir)?;

    for profile_dir_name in managed_profiles {
        if !apply::profile_selected(&context.profile_filters, &profile_dir_name) {
            continue;
        }

        summary.selected_count += 1;
        summary.checked += 1;

        let profile_name = apply::profile_display_name(&profile_dir_name);
        let desired_settings = settings::build_desired_settings(&context, &profile_dir_name)?;
        let desired_extensions = extensions::build_desired_extensions(&context, &profile_dir_name)?;
        let desired_default_disabled =
            extensions::build_desired_default_disabled_extensions(&context, &profile_dir_name)?;

        let plan = ProfilePlan {
            profile_dir_name: profile_dir_name.clone(),
            profile_name,
            desired_settings,
            desired_extensions,
            desired_default_disabled,
            state_file: apply::profile_state_file(&context, &profile_dir_name),
            settings_path: apply::profile_settings_path(&context, &profile_dir_name),
            extensions_manifest: apply::profile_extensions_manifest_path(&context, &profile_dir_name),
            runtime_dir: apply::profile_runtime_dir(&context, &profile_dir_name),
        };

        let eval = apply::classify_profile(&context, &plan)?;

        match eval.status {
            ProfileStatus::InSync => summary.in_sync += 1,
            ProfileStatus::NeedsApply => summary.needs_apply += 1,
            ProfileStatus::Missing => summary.missing += 1,
            ProfileStatus::Invalid => summary.invalid += 1,
        }

        if context.details {
            apply::profile_details(&plan, &eval);
        }

        if context.diff_output && eval.status != ProfileStatus::InSync {
            apply::profile_diff(&plan, &eval)?;
        }

        if context.mode == Mode::Apply {
            match eval.status {
                ProfileStatus::InSync => {}
                ProfileStatus::Missing | ProfileStatus::NeedsApply => {
                    if apply::apply_profile(&context, &plan).is_ok() {
                        let post = apply::classify_profile(&context, &plan)?;
                        if post.status == ProfileStatus::InSync {
                            summary.applied += 1;
                        } else {
                            summary.errors += 1;
                            log(&format!(
                                "apply failed to converge '{}': status={}",
                                plan.profile_dir_name,
                                post.status.as_str()
                            ));
                        }
                    } else {
                        summary.errors += 1;
                        log(&format!("apply failed for '{}'", plan.profile_dir_name));
                    }
                }
                ProfileStatus::Invalid => {
                    summary.errors += 1;
                    log(&format!(
                        "apply refused for '{}': {}",
                        plan.profile_dir_name, eval.reason
                    ));
                }
            }
        }
    }

    if summary.selected_count == 0 {
        if !context.profile_filters.is_empty() {
            return Err(format!(
                "no profile matched --profile '{}'",
                context.profile_filters.join(",")
            ));
        }
        return Err("no VS Code profiles selected".to_string());
    }

    if context.mode == Mode::Apply
        && summary.errors == 0
        && context.profile_filters.is_empty()
        && context.legacy_instances_dir.exists()
    {
        if context.legacy_instances_dir.is_dir() {
            fs::remove_dir_all(&context.legacy_instances_dir).map_err(|err| {
                format!(
                    "failed to remove legacy VS Code instances dir {}: {}",
                    context.legacy_instances_dir.display(),
                    err
                )
            })?;
        } else {
            fs::remove_file(&context.legacy_instances_dir).map_err(|err| {
                format!(
                    "failed to remove legacy VS Code instances path {}: {}",
                    context.legacy_instances_dir.display(),
                    err
                )
            })?;
        }
    }

    log(&format!(
        "summary: checked={} in_sync={} needs_apply={} missing={} invalid={} applied={} errors={}",
        summary.checked,
        summary.in_sync,
        summary.needs_apply,
        summary.missing,
        summary.invalid,
        summary.applied,
        summary.errors
    ));

    match context.mode {
        Mode::Apply => {
            if summary.errors == 0 {
                Ok(())
            } else {
                process::exit(1)
            }
        }
        Mode::Check => {
            if summary.needs_apply == 0
                && summary.missing == 0
                && summary.invalid == 0
                && summary.errors == 0
            {
                Ok(())
            } else {
                process::exit(1)
            }
        }
    }
}

pub(crate) fn log(message: &str) {
    eprintln!("{}: {}", SCRIPT_LABEL, message);
}

fn die(message: &str) -> ! {
    log(message);
    process::exit(1);
}
