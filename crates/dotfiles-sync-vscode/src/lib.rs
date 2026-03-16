use std::process;

pub(crate) mod app;
pub(crate) mod domain;
pub(crate) mod infra;

use app::runtime::Summary;
use domain::model::ProfileStatus;

pub(crate) const SCRIPT_LABEL: &str = "sync-vscode";
pub(crate) const STATE_VERSION: u32 = 4;

pub(crate) fn log(message: &str) {
    eprintln!("{}: {}", SCRIPT_LABEL, message);
}

pub(crate) fn die(message: &str) -> ! {
    log(message);
    process::exit(1);
}

pub fn main() {
    if let Err(err) = run() {
        die(&err);
    }
}

pub fn run() -> Result<(), String> {
    let cli_args = infra::cli::parse_args()?;
    let context = infra::context::build_context(cli_args)?;

    let mut summary = Summary::default();
    let managed_profiles = app::apply::list_managed_profiles(&context.managed_dir)?;

    for profile_dir_name in managed_profiles {
        if !app::apply::profile_selected(&context.profile_filters, &profile_dir_name) {
            continue;
        }

        summary.selected_count += 1;
        summary.checked += 1;

        let profile_name = app::apply::profile_display_name(&profile_dir_name);
        let desired_settings = domain::settings::build_desired_settings(&context, &profile_dir_name)?;
        let desired_extensions =
            infra::extensions::build_desired_extensions(&context, &profile_dir_name)?;
        let desired_default_disabled =
            infra::extensions::build_desired_default_disabled_extensions(&context, &profile_dir_name)?;

        let plan = domain::model::ProfilePlan {
            profile_dir_name: profile_dir_name.clone(),
            profile_name,
            desired_settings,
            desired_extensions,
            desired_default_disabled,
            state_file: app::apply::profile_state_file(&context, &profile_dir_name),
            settings_path: app::apply::profile_settings_path(&context, &profile_dir_name),
            extensions_manifest: app::apply::profile_extensions_manifest_path(
                &context,
                &profile_dir_name,
            ),
            runtime_dir: app::apply::profile_runtime_dir(&context, &profile_dir_name),
        };

        let eval = app::planner::classify_profile(&context, &plan)?;

        match eval.status {
            ProfileStatus::InSync => summary.in_sync += 1,
            ProfileStatus::NeedsApply => summary.needs_apply += 1,
            ProfileStatus::Missing => summary.missing += 1,
            ProfileStatus::Invalid => summary.invalid += 1,
        }

        if context.details {
            app::apply::profile_details(&plan, &eval);
        }

        if context.diff_output && eval.status != ProfileStatus::InSync {
            app::apply::profile_diff(&plan, &eval)?;
        }

        if context.mode == app::runtime::Mode::Apply {
            match eval.status {
                ProfileStatus::InSync => {}
                ProfileStatus::Missing | ProfileStatus::NeedsApply => {
                    if app::apply::apply_profile(&context, &plan).is_ok() {
                        let post = app::planner::classify_profile(&context, &plan)?;
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
        app::runtime::Mode::Apply => {
            if summary.errors == 0 {
                Ok(())
            } else {
                process::exit(1)
            }
        }
        app::runtime::Mode::Check => {
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
