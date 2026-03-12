use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use std::thread;
use std::time::Duration;
use tempfile::NamedTempFile;

const SCRIPT_LABEL: &str = "sync-vscode";
const STATE_VERSION: u32 = 3;

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
    let cli_args = parse_args()?;
    let context = build_context(cli_args)?;

    let mut summary = Summary::default();
    let managed_profiles = list_managed_profiles(&context.managed_dir)?;

    for profile_dir_name in managed_profiles {
        if !profile_selected(&context.profile_filters, &profile_dir_name) {
            continue;
        }

        summary.selected_count += 1;
        summary.checked += 1;

        let profile_name = profile_display_name(&profile_dir_name);
        let desired_settings = build_desired_settings(&context, &profile_dir_name)?;
        let desired_extensions = build_desired_extensions(&context, &profile_dir_name)?;
        let desired_default_disabled =
            build_desired_default_disabled_extensions(&context, &profile_dir_name)?;

        let plan = ProfilePlan {
            profile_dir_name: profile_dir_name.clone(),
            profile_name,
            desired_settings,
            desired_extensions,
            desired_default_disabled,
            state_file: profile_state_file(&context, &profile_dir_name),
            settings_path: profile_settings_path(&context, &profile_dir_name),
            extensions_manifest: profile_extensions_manifest_path(&context, &profile_dir_name),
            runtime_dir: profile_runtime_dir(&context, &profile_dir_name),
        };

        let eval = classify_profile(&context, &plan)?;

        match eval.status {
            ProfileStatus::InSync => summary.in_sync += 1,
            ProfileStatus::NeedsApply => summary.needs_apply += 1,
            ProfileStatus::Missing => summary.missing += 1,
            ProfileStatus::Invalid => summary.invalid += 1,
        }

        if context.details {
            profile_details(&plan, &eval);
        }

        if context.diff_output && eval.status != ProfileStatus::InSync {
            profile_diff(&plan, &eval)?;
        }

        if context.mode == Mode::Apply {
            match eval.status {
                ProfileStatus::InSync => {}
                ProfileStatus::Missing | ProfileStatus::NeedsApply => {
                    if apply_profile(&context, &plan).is_ok() {
                        let post = classify_profile(&context, &plan)?;
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

fn usage() {
    println!(
        "Usage:
  nix run .#dotfiles -- sync vscode --check [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]
  nix run .#dotfiles -- sync vscode --apply [--details] [--diff] [--profile <name>] [--managed-dir <path>] [--state-dir <path>]

Description:
  Keep repo-managed VS Code native profiles aligned with repo-managed settings
  and extensions while preserving unmanaged drift outside the owned subset.

Options:
  --check              Report in-sync / needs-apply / missing / invalid (default mode)
  --apply              Reconcile managed settings, extensions, and profile registry state
  --details            Print concise per-profile details
  --diff               Print projected settings diff and extension add/remove lists
  --profile <name>     Restrict to one managed profile dir name (repeatable)
  --managed-dir <path> Profile definitions directory (default: <repo>/apps/vscode)
  --state-dir <path>   Owned-subset state directory (default: ${{XDG_STATE_HOME:-$HOME/.local/state}}/dotfiles/vscode)
  --help               Show this help"
    );
}

fn parse_args() -> Result<CliArgs, String> {
    let mut args = env::args().skip(1).peekable();

    let mut managed_dir = None;
    let mut state_dir = None;
    let mut mode = Mode::Check;
    let mut mode_explicit = false;
    let mut details = false;
    let mut diff_output = false;
    let mut profile_filters: Vec<String> = Vec::new();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--check" => {
                if mode_explicit && mode != Mode::Check {
                    return Err("choose only one of --check or --apply".to_string());
                }
                mode = Mode::Check;
                mode_explicit = true;
            }
            "--apply" => {
                if mode_explicit && mode != Mode::Apply {
                    return Err("choose only one of --check or --apply".to_string());
                }
                mode = Mode::Apply;
                mode_explicit = true;
            }
            "--details" => details = true,
            "--diff" => diff_output = true,
            "--profile" => {
                let value = args
                    .next()
                    .ok_or_else(|| "missing value for --profile".to_string())?;
                if !profile_filters.iter().any(|entry| entry == &value) {
                    profile_filters.push(value);
                }
            }
            "--managed-dir" => {
                let value = args
                    .next()
                    .ok_or_else(|| "missing value for --managed-dir".to_string())?;
                managed_dir = Some(PathBuf::from(value));
            }
            "--state-dir" => {
                let value = args
                    .next()
                    .ok_or_else(|| "missing value for --state-dir".to_string())?;
                state_dir = Some(PathBuf::from(value));
            }
            "--help" | "-h" => {
                usage();
                process::exit(0);
            }
            _ => {
                return Err(format!("unknown option for sync vscode: {}", arg));
            }
        }
    }

    Ok(CliArgs {
        managed_dir,
        state_dir,
        mode,
        details,
        diff_output,
        profile_filters,
    })
}

fn build_context(args: CliArgs) -> Result<Context, String> {
    let managed_dir = if let Some(path) = args.managed_dir.clone() {
        path
    } else {
        resolve_repo_root()?.join("apps/vscode")
    };

    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    let state_dir = if let Some(path) = args.state_dir.clone() {
        path
    } else if let Ok(xdg_state_home) = env::var("XDG_STATE_HOME") {
        PathBuf::from(xdg_state_home).join("dotfiles/vscode")
    } else {
        PathBuf::from(home.clone()).join(".local/state/dotfiles/vscode")
    };

    if !managed_dir.is_dir() {
        return Err(format!("managed dir not found: {}", managed_dir.display()));
    }

    if !managed_dir.join("_default").is_dir() {
        return Err(format!(
            "managed default profile dir not found: {}",
            managed_dir.join("_default").display()
        ));
    }

    let code_bin = resolve_code_bin()?;

    if find_in_path("jq").is_none() {
        return Err("jq is required for sync vscode".to_string());
    }

    if find_in_path("sqlite3").is_none() {
        return Err("sqlite3 is required for sync vscode".to_string());
    }

    let vscode_data_home = env::var("VSCODE_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(home.clone()).join("Library/Application Support/Code"));
    let user_data_home = vscode_data_home.join("User");
    let profiles_home = user_data_home.join("profiles");
    let global_storage_dir = user_data_home.join("globalStorage");
    let storage_json_path = global_storage_dir.join("storage.json");

    let extensions_root = env::var("VSCODE_EXTENSIONS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(home.clone()).join(".vscode/extensions"));
    let extensions_manifest_path = extensions_root.join("extensions.json");

    let legacy_instances_dir = env::var("VSCODE_LEGACY_INSTANCES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(home).join(".local/share/vscode-instances"));

    let code_cli_retries = env::var("VSCODE_CODE_RETRIES")
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(3);

    Ok(Context {
        managed_dir,
        state_dir,
        mode: args.mode,
        details: args.details,
        diff_output: args.diff_output,
        profile_filters: args.profile_filters,
        code_bin,
        code_cli_retries,
        vscode_data_home,
        user_data_home,
        profiles_home,
        global_storage_dir,
        storage_json_path,
        extensions_root,
        extensions_manifest_path,
        legacy_instances_dir,
    })
}

fn resolve_repo_root() -> Result<PathBuf, String> {
    if let Ok(dotfiles_root) = env::var("DOTFILES_ROOT") {
        let root = PathBuf::from(&dotfiles_root);
        if !root.is_dir() {
            return Err(format!(
                "DOTFILES_ROOT is not a readable directory: {}",
                dotfiles_root
            ));
        }
        if !root.join("flake.nix").is_file() {
            return Err(format!(
                "unable to resolve flake root (expected flake.nix under {})",
                root.display()
            ));
        }
        return Ok(root);
    }

    let mut candidates: Vec<PathBuf> = Vec::new();

    if let Ok(exe_path) = env::current_exe() {
        for ancestor in exe_path.ancestors() {
            candidates.push(ancestor.to_path_buf());
        }
    }

    if let Ok(cwd) = env::current_dir() {
        for ancestor in cwd.ancestors() {
            candidates.push(ancestor.to_path_buf());
        }
    }

    let mut seen = HashSet::new();
    for candidate in candidates {
        let candidate_key = candidate.to_string_lossy().to_string();
        if !seen.insert(candidate_key) {
            continue;
        }

        if candidate.join("flake.nix").is_file() {
            return Ok(candidate);
        }
    }

    Err("unable to resolve flake root (expected flake.nix under repository root)".to_string())
}

fn classify_profile(context: &Context, plan: &ProfilePlan) -> Result<ProfileEvaluation, String> {
    if context
        .managed_dir
        .join("_default/extensions-disabled.txt")
        .is_file()
    {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: "apps/vscode/_default/extensions-disabled.txt is no longer supported".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if profile_legacy_disabled_file_path(context, &plan.profile_dir_name).is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: format!(
                "apps/vscode/{}/extensions-disabled.txt is no longer supported",
                plan.profile_dir_name
            ),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if context
        .managed_dir
        .join("_default/launch-disabled-extensions.txt")
        .is_file()
    {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: "apps/vscode/_default/launch-disabled-extensions.txt has been replaced by default-disabled-extensions.txt".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if profile_legacy_launch_disabled_file_path(context, &plan.profile_dir_name).is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Invalid,
            reason: format!(
                "apps/vscode/{}/launch-disabled-extensions.txt has been replaced by default-disabled-extensions.txt",
                plan.profile_dir_name
            ),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    let state_load = load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)?;
    let (state_missing, state_lists) = match state_load {
        StateLoad::Invalid => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::NeedsApply,
                reason: "state file schema changed or is malformed".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
        StateLoad::Missing => (true, StateLists::default()),
        StateLoad::Loaded(lists) => (false, lists),
    };

    let desired_keys = object_keys_unsorted(&plan.desired_settings);
    let stale_keys = file_minus_file(&state_lists.owned_settings_keys, &desired_keys);
    let stale_extensions = file_minus_file(&state_lists.owned_extensions, &plan.desired_extensions);

    if !context.storage_json_path.is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "VS Code profile registry is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    let storage_json = match read_json(&context.storage_json_path) {
        Ok(value) => value,
        Err(_) => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::Invalid,
                reason: "VS Code profile registry is not valid JSON".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
    };

    if !custom_profile_entry_matches_expected(
        &storage_json,
        &plan.profile_name,
        &profile_id(&plan.profile_dir_name),
    ) {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason:
                "managed profile is not registered at the expected native profile location".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if !plan.runtime_dir.is_dir() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "managed profile directory is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if !plan.settings_path.is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "managed profile settings file is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    if !plan.extensions_manifest.is_file() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::Missing,
            reason: "managed profile extensions manifest is missing".to_string(),
            settings_diff_expected: None,
            settings_diff_actual: None,
            extensions_add: Vec::new(),
            extensions_remove: Vec::new(),
        });
    }

    let actual_settings = match read_json_object(&plan.settings_path) {
        Ok(object) => object,
        Err(_) => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::Invalid,
                reason: "settings file is not valid JSON".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
    };

    let actual_extensions = match list_profile_extensions(context, &plan.profile_dir_name) {
        Ok(items) => items,
        Err(_) => {
            return Ok(ProfileEvaluation {
                status: ProfileStatus::Invalid,
                reason: "failed to inspect installed extensions".to_string(),
                settings_diff_expected: None,
                settings_diff_actual: None,
                extensions_add: Vec::new(),
                extensions_remove: Vec::new(),
            });
        }
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
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "state file is missing".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !all_desired_keys_match(&actual_settings, &plan.desired_settings, &desired_keys) {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "managed settings differ from desired values".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !stale_keys_present.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "previously owned settings keys still exist locally".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !desired_missing.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "required extensions are missing".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !stale_installed.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "previously owned extensions still exist locally".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
    }

    if !pending_default_disabled.is_empty() {
        return Ok(ProfileEvaluation {
            status: ProfileStatus::NeedsApply,
            reason: "default-disabled extensions have not been bootstrapped yet".to_string(),
            settings_diff_expected: Some(Value::Object(settings_diff_expected)),
            settings_diff_actual: Some(Value::Object(settings_diff_actual)),
            extensions_add: desired_missing,
            extensions_remove: stale_installed,
        });
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

fn apply_profile(context: &Context, plan: &ProfilePlan) -> Result<(), String> {
    ensure_profile_runtime(context, &plan.profile_dir_name, &plan.profile_name)?;

    let state_lists = match load_state_lists(&plan.state_file, &plan.profile_dir_name, &plan.profile_name)? {
        StateLoad::Loaded(lists) => lists,
        StateLoad::Missing | StateLoad::Invalid => StateLists::default(),
    };

    let desired_keys = object_keys_unsorted(&plan.desired_settings);
    let stale_keys = file_minus_file(&state_lists.owned_settings_keys, &desired_keys);

    let current_extensions = list_profile_extensions(context, &plan.profile_dir_name)?;
    let desired_missing = file_minus_file(&plan.desired_extensions, &current_extensions);
    let stale_owned_extensions = file_minus_file(&state_lists.owned_extensions, &plan.desired_extensions);
    let stale_installed = file_intersection(&stale_owned_extensions, &current_extensions);

    for extension_id in desired_missing {
        install_profile_extension(context, &plan.profile_dir_name, &plan.profile_name, &extension_id)?;
    }

    for extension_id in stale_installed {
        uninstall_profile_extension(context, &plan.profile_dir_name, &plan.profile_name, &extension_id)?;
    }

    let updated_bootstrapped_default_disabled = bootstrap_default_disabled_extensions(
        context,
        &plan.profile_dir_name,
        &plan.desired_default_disabled,
        &state_lists.bootstrapped_default_disabled_extensions,
    )?;

    let actual_settings = read_json_object(&plan.settings_path)?;
    let updated_settings = apply_settings_owned_subset(
        &actual_settings,
        &plan.desired_settings,
        &desired_keys,
        &stale_keys,
    );
    write_json_atomically(&Value::Object(updated_settings), &plan.settings_path)?;

    write_state_file(
        &plan.state_file,
        &plan.profile_dir_name,
        &plan.profile_name,
        &desired_keys,
        &plan.desired_extensions,
        &updated_bootstrapped_default_disabled,
    )
}

fn profile_details(plan: &ProfilePlan, eval: &ProfileEvaluation) {
    log(&format!("details: {}", plan.profile_dir_name));
    log(&format!("  profile-name: {}", plan.profile_name));
    log(&format!("  status: {}", eval.status.as_str()));
    log(&format!("  settings: {}", plan.settings_path.display()));
    log(&format!("  state: {}", plan.state_file.display()));
    log(&format!("  reason: {}", eval.reason));
}

fn profile_diff(plan: &ProfilePlan, eval: &ProfileEvaluation) -> Result<(), String> {
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
    let mut left_file = NamedTempFile::new().map_err(|err| format!("failed to create temp file: {}", err))?;
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

    prune_orphaned_extension_dirs(context)?;
    ensure_custom_profile_runtime(context, profile_dir_name, profile_name)
}

fn ensure_custom_profile_runtime(
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

fn ensure_custom_profile_registry(
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

    let existing = storage_object
        .remove("userDataProfiles")
        .and_then(|value| match value {
            Value::Array(items) => Some(items),
            _ => None,
        })
        .unwrap_or_default();

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

fn ensure_storage_json_exists(context: &Context) -> Result<(), String> {
    fs::create_dir_all(&context.global_storage_dir).map_err(|err| {
        format!(
            "failed to create global storage dir {}: {}",
            context.global_storage_dir.display(),
            err
        )
    })?;

    if context.storage_json_path.is_file() {
        read_json(&context.storage_json_path)?;
        return Ok(());
    }

    write_json_atomically(&Value::Object(Map::new()), &context.storage_json_path)
}

fn custom_profile_entry_matches_expected(
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

fn ensure_enablement_db(context: &Context, profile_dir_name: &str) -> Result<(), String> {
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

fn bootstrap_default_disabled_extensions(
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

fn pending_default_disabled_extensions(
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

fn prune_orphaned_extension_dirs(context: &Context) -> Result<(), String> {
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

fn normalize_custom_profile_extension_manifest(
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

fn add_custom_profile_extension_membership(
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

fn remove_custom_profile_extension_membership(
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

fn install_profile_extension(
    context: &Context,
    profile_dir_name: &str,
    profile_name: &str,
    extension_id: &str,
) -> Result<(), String> {
    prune_orphaned_extension_dirs(context)?;

    if add_custom_profile_extension_membership(context, profile_dir_name, profile_name, extension_id)? {
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
        add_custom_profile_extension_membership(context, profile_dir_name, profile_name, extension_id)?;
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
    prune_orphaned_extension_dirs(context)?;
    remove_custom_profile_extension_membership(context, profile_dir_name, profile_name, extension_id)
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

fn list_profile_extensions(context: &Context, profile_dir_name: &str) -> Result<Vec<String>, String> {
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

fn all_desired_keys_match(
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

fn apply_settings_owned_subset(
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

fn project_settings_subset(input: &Map<String, Value>, keys: &[String]) -> Map<String, Value> {
    let mut projected = Map::new();

    for key in keys {
        if let Some(value) = input.get(key) {
            projected.insert(key.clone(), value.clone());
        }
    }

    projected
}

fn write_state_file(
    state_file: &Path,
    profile_dir_name: &str,
    profile_name: &str,
    owned_keys: &[String],
    owned_extensions: &[String],
    bootstrapped_default_disabled_extensions: &[String],
) -> Result<(), String> {
    let state = StateFile {
        version: STATE_VERSION,
        profile_dir_name: profile_dir_name.to_string(),
        profile_name: profile_name.to_string(),
        owned_settings_keys: owned_keys.to_vec(),
        owned_extensions: owned_extensions.to_vec(),
        bootstrapped_default_disabled_extensions: bootstrapped_default_disabled_extensions.to_vec(),
    };

    let value = serde_json::to_value(state)
        .map_err(|err| format!("failed to encode state file JSON: {}", err))?;
    write_json_atomically(&value, state_file)
}

fn load_state_lists(
    state_file: &Path,
    profile_dir_name: &str,
    profile_name: &str,
) -> Result<StateLoad, String> {
    if !state_file.is_file() {
        return Ok(StateLoad::Missing);
    }

    let state_text = fs::read_to_string(state_file)
        .map_err(|err| format!("failed to read state file {}: {}", state_file.display(), err))?;

    let parsed: StateFile = match serde_json::from_str(&state_text) {
        Ok(state) => state,
        Err(_) => return Ok(StateLoad::Invalid),
    };

    if parsed.version != STATE_VERSION
        || parsed.profile_dir_name != profile_dir_name
        || parsed.profile_name != profile_name
    {
        return Ok(StateLoad::Invalid);
    }

    Ok(StateLoad::Loaded(StateLists {
        owned_settings_keys: parsed.owned_settings_keys,
        owned_extensions: parsed.owned_extensions,
        bootstrapped_default_disabled_extensions: parsed.bootstrapped_default_disabled_extensions,
    }))
}

fn build_desired_settings(
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

fn build_desired_extensions(
    context: &Context,
    profile_dir_name: &str,
) -> Result<Vec<String>, String> {
    let default_extensions = filter_extensions_file(&context.managed_dir.join("_default/extensions.txt"))?;
    let profile_extensions = filter_extensions_file(
        &context
            .managed_dir
            .join(profile_dir_name)
            .join("extensions.txt"),
    )?;

    let combined = [default_extensions, profile_extensions].concat();
    Ok(canonicalize_extension_ids(&combined))
}

fn build_desired_default_disabled_extensions(
    context: &Context,
    profile_dir_name: &str,
) -> Result<Vec<String>, String> {
    let default_disabled =
        filter_extensions_file(&profile_default_disabled_file_path(context, "_default"))?;
    let profile_disabled =
        filter_extensions_file(&profile_default_disabled_file_path(context, profile_dir_name))?;

    let combined = [default_disabled, profile_disabled].concat();
    Ok(canonicalize_extension_ids(&combined))
}

fn filter_extensions_file(path: &Path) -> Result<Vec<String>, String> {
    if !path.is_file() {
        return Ok(Vec::new());
    }

    let data = fs::read_to_string(path)
        .map_err(|err| format!("failed to read extensions file {}: {}", path.display(), err))?;

    let mut extensions = Vec::new();

    for line in data.lines() {
        let trimmed_start = line.trim_start();
        if trimmed_start.starts_with('#') {
            continue;
        }

        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        extensions.push(trimmed.to_string());
    }

    Ok(extensions)
}

fn canonicalize_extension_ids(ids: &[String]) -> Vec<String> {
    let mapped: Vec<String> = ids
        .iter()
        .map(|id| canonical_extension_id(id).to_string())
        .collect();
    unique_lines(&mapped)
}

fn canonical_extension_id(id: &str) -> &str {
    match id {
        "github.copilot" => "github.copilot-chat",
        _ => id,
    }
}

fn list_managed_profiles(managed_dir: &Path) -> Result<Vec<String>, String> {
    let mut profiles = Vec::new();

    for entry in fs::read_dir(managed_dir)
        .map_err(|err| format!("failed to read managed dir {}: {}", managed_dir.display(), err))?
    {
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

fn profile_selected(profile_filters: &[String], profile_name: &str) -> bool {
    if profile_filters.is_empty() {
        return true;
    }

    profile_filters.iter().any(|filter| filter == profile_name)
}

fn profile_display_name(profile_dir_name: &str) -> String {
    let words: Vec<String> = profile_dir_name
        .split(|c| c == '-' || c == '_')
        .filter(|word| !word.is_empty())
        .map(|word| {
            let lower = word.to_ascii_lowercase();
            let mut chars = lower.chars();
            if let Some(first) = chars.next() {
                format!("{}{}", first.to_ascii_uppercase(), chars.collect::<String>())
            } else {
                String::new()
            }
        })
        .filter(|word| !word.is_empty())
        .collect();

    words.join(" ")
}

fn profile_id(profile_dir_name: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(format!("dotfiles:vscode-profile:{}", profile_dir_name));
    let digest = hasher.finalize();
    let hex = format!("{:x}", digest);
    hex.chars().take(32).collect()
}

fn profile_state_file(context: &Context, profile_dir_name: &str) -> PathBuf {
    context.state_dir.join(format!("{}.json", profile_dir_name))
}

fn profile_runtime_dir(context: &Context, profile_dir_name: &str) -> PathBuf {
    context.profiles_home.join(profile_id(profile_dir_name))
}

fn profile_settings_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_runtime_dir(context, profile_dir_name).join("settings.json")
}

fn profile_extensions_manifest_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_runtime_dir(context, profile_dir_name).join("extensions.json")
}

fn profile_legacy_disabled_file_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    context
        .managed_dir
        .join(profile_dir_name)
        .join("extensions-disabled.txt")
}

fn profile_legacy_launch_disabled_file_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    context
        .managed_dir
        .join(profile_dir_name)
        .join("launch-disabled-extensions.txt")
}

fn profile_default_disabled_file_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    context
        .managed_dir
        .join(profile_dir_name)
        .join("default-disabled-extensions.txt")
}

fn profile_global_storage_dir(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_runtime_dir(context, profile_dir_name).join("globalStorage")
}

fn profile_enablement_db_path(context: &Context, profile_dir_name: &str) -> PathBuf {
    profile_global_storage_dir(context, profile_dir_name).join("state.vscdb")
}

fn read_json(path: &Path) -> Result<Value, String> {
    let data = fs::read_to_string(path)
        .map_err(|err| format!("failed to read JSON file {}: {}", path.display(), err))?;

    serde_json::from_str(&data)
        .map_err(|err| format!("failed to parse JSON file {}: {}", path.display(), err))
}

fn read_json_object(path: &Path) -> Result<Map<String, Value>, String> {
    match read_json(path)? {
        Value::Object(object) => Ok(object),
        _ => Err(format!("JSON object expected at {}", path.display())),
    }
}

fn read_json_array(path: &Path) -> Result<Vec<Value>, String> {
    match read_json(path)? {
        Value::Array(items) => Ok(items),
        _ => Err(format!("JSON array expected at {}", path.display())),
    }
}

fn write_json_atomically(value: &Value, target_json: &Path) -> Result<(), String> {
    let parent = target_json
        .parent()
        .ok_or_else(|| format!("path has no parent: {}", target_json.display()))?;

    fs::create_dir_all(parent)
        .map_err(|err| format!("failed to create parent dir {}: {}", parent.display(), err))?;

    let mut temp_file = NamedTempFile::new_in(parent)
        .map_err(|err| format!("failed to create temp file in {}: {}", parent.display(), err))?;

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

fn deep_merge(base: &mut Value, overlay: &Value) {
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

fn sort_json(value: &Value) -> Value {
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

fn sort_object(object: &Map<String, Value>) -> Map<String, Value> {
    match sort_json(&Value::Object(object.clone())) {
        Value::Object(sorted) => sorted,
        _ => Map::new(),
    }
}

fn object_keys_unsorted(object: &Map<String, Value>) -> Vec<String> {
    object.keys().cloned().collect()
}

fn file_minus_file(left: &[String], right: &[String]) -> Vec<String> {
    if left.is_empty() {
        return Vec::new();
    }

    if right.is_empty() {
        return left.to_vec();
    }

    let right_set: HashSet<&str> = right.iter().map(String::as_str).collect();
    left.iter()
        .filter(|item| !right_set.contains(item.as_str()))
        .cloned()
        .collect()
}

fn file_intersection(left: &[String], right: &[String]) -> Vec<String> {
    if left.is_empty() || right.is_empty() {
        return Vec::new();
    }

    let left_set: HashSet<&str> = left.iter().map(String::as_str).collect();
    right
        .iter()
        .filter(|item| left_set.contains(item.as_str()))
        .cloned()
        .collect()
}

fn unique_lines(lines: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut unique = Vec::new();

    for line in lines {
        if seen.insert(line.clone()) {
            unique.push(line.clone());
        }
    }

    unique
}

fn json_bytes(value: &Value) -> Result<Vec<u8>, String> {
    let mut bytes = serde_json::to_vec_pretty(value)
        .map_err(|err| format!("failed to encode JSON: {}", err))?;
    bytes.push(b'\n');
    Ok(bytes)
}

fn write_output_bytes(bytes: &[u8], stderr: bool) -> Result<(), String> {
    if bytes.is_empty() {
        return Ok(());
    }

    if stderr {
        let mut handle = std::io::stderr().lock();
        handle
            .write_all(bytes)
            .map_err(|err| format!("failed to write process stderr: {}", err))?;
        handle
            .flush()
            .map_err(|err| format!("failed to flush process stderr: {}", err))?;
    } else {
        let mut handle = std::io::stdout().lock();
        handle
            .write_all(bytes)
            .map_err(|err| format!("failed to write process stdout: {}", err))?;
        handle
            .flush()
            .map_err(|err| format!("failed to flush process stdout: {}", err))?;
    }

    Ok(())
}

fn resolve_code_bin() -> Result<String, String> {
    if let Ok(bin) = env::var("VSCODE_CODE_BIN") {
        if !bin.is_empty() {
            let configured = PathBuf::from(&bin);
            if configured.is_file() {
                return Ok(bin);
            }
            return Err(format!(
                "configured VS Code CLI is not executable: {}",
                configured.display()
            ));
        }
    }

    if let Some(path) = find_in_path("code") {
        return Ok(path.to_string_lossy().to_string());
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(home) = env::var("HOME") {
        candidates.push(
            PathBuf::from(home)
                .join("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"),
        );
    }
    candidates.push(PathBuf::from(
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
    ));

    for candidate in candidates {
        if candidate.is_file() {
            return Ok(candidate.to_string_lossy().to_string());
        }
    }

    Err(
        "VS Code CLI not found (set VSCODE_CODE_BIN, install 'code' in PATH, or install Visual Studio Code.app)"
            .to_string(),
    )
}

fn find_in_path(name: &str) -> Option<PathBuf> {
    let candidate = PathBuf::from(name);
    if candidate.components().count() > 1 {
        if candidate.exists() {
            return Some(candidate);
        }
        return None;
    }

    let path_var = env::var_os("PATH")?;
    for dir in env::split_paths(&path_var) {
        let full = dir.join(name);
        if full.exists() {
            return Some(full);
        }
    }

    None
}

fn log(message: &str) {
    eprintln!("{}: {}", SCRIPT_LABEL, message);
}

fn die(message: &str) -> ! {
    log(message);
    process::exit(1);
}
