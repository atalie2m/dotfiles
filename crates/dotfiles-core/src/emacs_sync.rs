use crate::support::{home_dir, log, repo_root};
use clap::error::ErrorKind;
use clap::Parser;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use tempfile::NamedTempFile;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmacsSyncMode {
    Check,
    Apply,
    Adopt,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EmacsSyncOptions {
    pub managed_dir: Option<PathBuf>,
    pub emacs_dir: Option<PathBuf>,
    pub mode: EmacsSyncMode,
    pub details: bool,
    pub diff_output: bool,
    pub item_filter: Option<String>,
}

#[derive(Parser, Debug)]
#[command(
    name = "sync-emacs",
    about = "Keep mutable Emacs config files aligned with repo-managed files.",
    disable_version_flag = true
)]
struct EmacsSyncCliArgs {
    #[arg(long, conflicts_with_all = ["apply", "adopt"])]
    check: bool,
    #[arg(long, conflicts_with_all = ["check", "adopt"])]
    apply: bool,
    #[arg(long, conflicts_with_all = ["check", "apply"])]
    adopt: bool,
    #[arg(long)]
    details: bool,
    #[arg(long = "diff")]
    diff_output: bool,
    #[arg(long = "item")]
    item_filter: Option<String>,
    #[arg(long = "managed-dir")]
    managed_dir: Option<PathBuf>,
    #[arg(long = "emacs-dir")]
    emacs_dir: Option<PathBuf>,
}

impl Default for EmacsSyncOptions {
    fn default() -> Self {
        Self {
            managed_dir: None,
            emacs_dir: None,
            mode: EmacsSyncMode::Check,
            details: false,
            diff_output: false,
            item_filter: None,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct EmacsSyncResult {
    pub selected_count: u32,
    pub checked: u32,
    pub in_sync: u32,
    pub needs_apply: u32,
    pub missing: u32,
    pub invalid: u32,
    pub applied: u32,
    pub adopted: u32,
    pub errors: u32,
}

impl EmacsSyncResult {
    pub fn exit_code(&self, mode: EmacsSyncMode) -> i32 {
        match mode {
            EmacsSyncMode::Apply | EmacsSyncMode::Adopt => {
                if self.errors == 0 {
                    0
                } else {
                    1
                }
            }
            EmacsSyncMode::Check => {
                if self.needs_apply == 0
                    && self.missing == 0
                    && self.invalid == 0
                    && self.errors == 0
                {
                    0
                } else {
                    1
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct TargetSpec {
    id: &'static str,
    file_name: &'static str,
}

const TARGET_SPECS: [TargetSpec; 2] = [
    TargetSpec {
        id: "early-init",
        file_name: "early-init.el",
    },
    TargetSpec {
        id: "init",
        file_name: "init.el",
    },
];

#[derive(Clone, Debug)]
struct TargetDefinition {
    id: &'static str,
    file_name: &'static str,
    actual_path: PathBuf,
    desired_path: PathBuf,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TargetStatus {
    InSync,
    NeedsApply,
    Missing,
    Invalid,
}

impl TargetStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::InSync => "in-sync",
            Self::NeedsApply => "needs-apply",
            Self::Missing => "missing",
            Self::Invalid => "invalid",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum PathKind {
    Missing,
    Regular,
    Directory,
    Special,
    SymlinkStore(String),
    SymlinkRegular(String),
    SymlinkDirectory(String),
    SymlinkSpecial(String),
    SymlinkBroken(String),
}

impl PathKind {
    fn label(&self) -> &'static str {
        match self {
            Self::Missing => "missing",
            Self::Regular => "regular",
            Self::Directory => "directory",
            Self::Special => "special",
            Self::SymlinkStore(_) => "symlink-store",
            Self::SymlinkRegular(_) => "symlink-regular",
            Self::SymlinkDirectory(_) => "symlink-directory",
            Self::SymlinkSpecial(_) => "symlink-special",
            Self::SymlinkBroken(_) => "symlink-broken",
        }
    }

    fn detail(&self) -> Option<&str> {
        match self {
            Self::SymlinkStore(detail)
            | Self::SymlinkRegular(detail)
            | Self::SymlinkDirectory(detail)
            | Self::SymlinkSpecial(detail)
            | Self::SymlinkBroken(detail) => Some(detail.as_str()),
            _ => None,
        }
    }

    fn is_readable_file_shape(&self) -> bool {
        matches!(
            self,
            Self::Regular | Self::SymlinkStore(_) | Self::SymlinkRegular(_)
        )
    }

    fn needs_materialize(&self) -> bool {
        matches!(self, Self::SymlinkStore(_) | Self::SymlinkRegular(_))
    }
}

#[derive(Clone, Debug)]
struct TargetEvaluation {
    status: TargetStatus,
    reason: String,
    actual_kind: PathKind,
    shape_needs_rewrite: bool,
    desired_text: String,
    actual_text: String,
}

#[derive(Debug, PartialEq, Eq)]
enum ActionStatus {
    Skipped,
    Changed,
    Error(String),
}

pub fn run_cli(args: &[String]) -> Result<EmacsSyncResult, String> {
    let options = parse_cli_args(args)?;
    run(options)
}

pub fn run(mut options: EmacsSyncOptions) -> Result<EmacsSyncResult, String> {
    if options.managed_dir.is_none() {
        options.managed_dir = Some(repo_root()?.join("apps/emacs/config"));
    }
    if options.emacs_dir.is_none() {
        options.emacs_dir = Some(default_emacs_dir()?);
    }

    let managed_dir = options
        .managed_dir
        .clone()
        .ok_or_else(|| "managed dir is required".to_string())?;
    let emacs_dir = options
        .emacs_dir
        .clone()
        .ok_or_else(|| "emacs config dir is required".to_string())?;

    if !managed_dir.is_dir() {
        return Err(format!("managed dir not found: {}", managed_dir.display()));
    }

    let targets = list_targets(&managed_dir, &emacs_dir);
    let mut result = EmacsSyncResult::default();

    for target in targets {
        if !target_selected(&options, &target) {
            continue;
        }

        result.selected_count += 1;
        result.checked += 1;

        let evaluation = classify_target(&target)?;
        match evaluation.status {
            TargetStatus::InSync => result.in_sync += 1,
            TargetStatus::NeedsApply => result.needs_apply += 1,
            TargetStatus::Missing => result.missing += 1,
            TargetStatus::Invalid => result.invalid += 1,
        }

        if options.details {
            print_target_details(&target, &evaluation);
        }

        if options.diff_output && evaluation.status != TargetStatus::InSync {
            print_target_diff(&target, &evaluation)?;
        }

        match options.mode {
            EmacsSyncMode::Check => {}
            EmacsSyncMode::Apply => match apply_target_with_recheck(&target, &evaluation)? {
                ActionStatus::Skipped => {}
                ActionStatus::Changed => result.applied += 1,
                ActionStatus::Error(message) => {
                    result.errors += 1;
                    log(&message);
                }
            },
            EmacsSyncMode::Adopt => match adopt_target(&target, &evaluation)? {
                ActionStatus::Skipped => {}
                ActionStatus::Changed => result.adopted += 1,
                ActionStatus::Error(message) => {
                    result.errors += 1;
                    log(&message);
                }
            },
        }
    }

    if result.selected_count == 0 {
        if let Some(item) = &options.item_filter {
            return Err(format!("no item matched --item '{}'", item));
        }
        return Err("no Emacs targets selected".to_string());
    }

    log(&format!(
        "summary: checked={} in_sync={} needs_apply={} missing={} invalid={} applied={} adopted={} errors={}",
        result.checked,
        result.in_sync,
        result.needs_apply,
        result.missing,
        result.invalid,
        result.applied,
        result.adopted,
        result.errors
    ));

    Ok(result)
}

fn parse_cli_args(args: &[String]) -> Result<EmacsSyncOptions, String> {
    let parsed = parse_cli_or_display(EmacsSyncCliArgs::try_parse_from(
        std::iter::once("sync-emacs".to_string()).chain(args.iter().cloned()),
    ))?;
    Ok(EmacsSyncOptions {
        managed_dir: parsed.managed_dir,
        emacs_dir: parsed.emacs_dir,
        mode: if parsed.apply {
            EmacsSyncMode::Apply
        } else if parsed.adopt {
            EmacsSyncMode::Adopt
        } else {
            EmacsSyncMode::Check
        },
        details: parsed.details,
        diff_output: parsed.diff_output,
        item_filter: parsed.item_filter,
    })
}

fn parse_cli_or_display<T>(result: Result<T, clap::Error>) -> Result<T, String> {
    match result {
        Ok(value) => Ok(value),
        Err(err) => match err.kind() {
            ErrorKind::DisplayHelp | ErrorKind::DisplayVersion => {
                err.print()
                    .map_err(|io_error| format!("failed to print help: {}", io_error))?;
                process::exit(0);
            }
            _ => Err(err.to_string().trim_end().to_string()),
        },
    }
}

fn default_emacs_dir() -> Result<PathBuf, String> {
    if let Ok(value) = env::var("EMACSDIR") {
        if !value.is_empty() {
            return Ok(PathBuf::from(value));
        }
    }
    Ok(home_dir()?.join(".emacs.d"))
}

fn list_targets(managed_dir: &Path, emacs_dir: &Path) -> Vec<TargetDefinition> {
    TARGET_SPECS
        .iter()
        .map(|spec| TargetDefinition {
            id: spec.id,
            file_name: spec.file_name,
            actual_path: emacs_dir.join(spec.file_name),
            desired_path: managed_dir.join(spec.file_name),
        })
        .collect()
}

fn target_selected(options: &EmacsSyncOptions, target: &TargetDefinition) -> bool {
    let Some(item) = &options.item_filter else {
        return true;
    };
    item == target.id || item == target.file_name
}

fn classify_target(target: &TargetDefinition) -> Result<TargetEvaluation, String> {
    let desired_text = canonicalize_file(&target.desired_path)
        .map_err(|_| format!("desired file not found: {}", target.desired_path.display()))?;
    let actual_kind = path_kind(&target.actual_path);
    let shape_needs_rewrite = actual_kind.needs_materialize();
    let mut evaluation = TargetEvaluation {
        status: TargetStatus::Invalid,
        reason: String::new(),
        actual_kind: actual_kind.clone(),
        shape_needs_rewrite,
        desired_text,
        actual_text: String::new(),
    };

    match actual_kind {
        PathKind::Missing => {
            evaluation.status = TargetStatus::Missing;
            evaluation.reason = "target is missing".to_string();
            Ok(evaluation)
        }
        PathKind::Directory
        | PathKind::Special
        | PathKind::SymlinkDirectory(_)
        | PathKind::SymlinkSpecial(_) => {
            evaluation.status = TargetStatus::Invalid;
            evaluation.reason = "target is not a regular file".to_string();
            Ok(evaluation)
        }
        PathKind::SymlinkBroken(_) => {
            evaluation.status = TargetStatus::Invalid;
            evaluation.reason = "symlink does not resolve to a regular file".to_string();
            Ok(evaluation)
        }
        PathKind::Regular | PathKind::SymlinkStore(_) | PathKind::SymlinkRegular(_) => {
            evaluation.actual_text = canonicalize_file(&target.actual_path).map_err(|_| {
                format!(
                    "failed to inspect target contents: {}",
                    target.actual_path.display()
                )
            })?;
            if evaluation.shape_needs_rewrite {
                evaluation.status = TargetStatus::NeedsApply;
                evaluation.reason =
                    "target should be materialized as a writable regular file".to_string();
            } else if evaluation.actual_text == evaluation.desired_text {
                evaluation.status = TargetStatus::InSync;
                evaluation.reason = "target matches desired".to_string();
            } else {
                evaluation.status = TargetStatus::NeedsApply;
                evaluation.reason = "target differs from desired".to_string();
            }
            Ok(evaluation)
        }
    }
}

fn print_target_details(target: &TargetDefinition, evaluation: &TargetEvaluation) {
    log(&format!("details: {}", target.id));
    log("  surface: emacs");
    log("  type: file");
    log(&format!("  status: {}", evaluation.status.as_str()));
    log(&format!("  target: {}", target.actual_path.display()));
    log(&format!("  desired: {}", target.desired_path.display()));
    if let Some(detail) = evaluation.actual_kind.detail() {
        log(&format!(
            "  actual-type: {} ({})",
            evaluation.actual_kind.label(),
            detail
        ));
    } else {
        log(&format!(
            "  actual-type: {}",
            evaluation.actual_kind.label()
        ));
    }
    log(&format!("  reason: {}", evaluation.reason));
}

fn print_target_diff(
    target: &TargetDefinition,
    evaluation: &TargetEvaluation,
) -> Result<(), String> {
    log(&format!("diff: {}", target.id));
    print_unified_diff(&evaluation.desired_text, &evaluation.actual_text)
}

fn print_unified_diff(desired: &str, actual: &str) -> Result<(), String> {
    let mut left =
        NamedTempFile::new().map_err(|err| format!("failed to create temp file: {}", err))?;
    let mut right =
        NamedTempFile::new().map_err(|err| format!("failed to create temp file: {}", err))?;
    left.write_all(desired.as_bytes())
        .map_err(|err| format!("failed to write diff input: {}", err))?;
    right
        .write_all(actual.as_bytes())
        .map_err(|err| format!("failed to write diff input: {}", err))?;
    let output = Command::new("diff")
        .arg("-u")
        .arg(left.path())
        .arg(right.path())
        .output()
        .map_err(|err| format!("failed to run diff: {}", err))?;
    write_output(&output.stdout, false)?;
    write_output(&output.stderr, true)?;
    Ok(())
}

fn apply_target_with_recheck(
    target: &TargetDefinition,
    evaluation: &TargetEvaluation,
) -> Result<ActionStatus, String> {
    match evaluation.status {
        TargetStatus::InSync => Ok(ActionStatus::Skipped),
        TargetStatus::Invalid => Ok(ActionStatus::Error(format!(
            "apply refused for '{}': {}",
            target.id, evaluation.reason
        ))),
        TargetStatus::Missing | TargetStatus::NeedsApply => {
            match write_file_atomically(&target.actual_path, &evaluation.desired_text) {
                Ok(()) => {
                    let post = classify_target(target)?;
                    if post.status == TargetStatus::InSync {
                        Ok(ActionStatus::Changed)
                    } else {
                        Ok(ActionStatus::Error(format!(
                            "apply failed to converge '{}': status={} reason={}",
                            target.id,
                            post.status.as_str(),
                            post.reason
                        )))
                    }
                }
                Err(err) => Ok(ActionStatus::Error(format!(
                    "apply failed for '{}': {}",
                    target.id, err
                ))),
            }
        }
    }
}

fn adopt_target(
    target: &TargetDefinition,
    evaluation: &TargetEvaluation,
) -> Result<ActionStatus, String> {
    if target.desired_path.starts_with("/nix/store") {
        return Ok(ActionStatus::Error(format!(
            "adopt refused for '{}': managed file is in the Nix store; run from a writable checkout or pass --managed-dir",
            target.id
        )));
    }
    if !evaluation.actual_kind.is_readable_file_shape() {
        return Ok(ActionStatus::Error(format!(
            "adopt refused for '{}': {}",
            target.id, evaluation.reason
        )));
    }
    if evaluation.actual_text == evaluation.desired_text {
        return Ok(ActionStatus::Skipped);
    }

    match write_file_atomically(&target.desired_path, &evaluation.actual_text) {
        Ok(()) => Ok(ActionStatus::Changed),
        Err(err) => Ok(ActionStatus::Error(format!(
            "adopt failed for '{}': {}",
            target.id, err
        ))),
    }
}

fn write_file_atomically(target_file: &Path, contents: &str) -> Result<(), String> {
    let parent = target_file
        .parent()
        .ok_or_else(|| format!("path has no parent: {}", target_file.display()))?;
    fs::create_dir_all(parent)
        .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
    let mut temp = NamedTempFile::new_in(parent)
        .map_err(|err| format!("failed to create temp file: {}", err))?;
    temp.write_all(contents.as_bytes())
        .map_err(|err| format!("failed to write temp file: {}", err))?;
    temp.persist(target_file)
        .map_err(|err| format!("failed to replace {}: {}", target_file.display(), err.error))?;
    Ok(())
}

fn canonicalize_file(path: &Path) -> io::Result<String> {
    fs::read_to_string(path).map(|text| canonicalize_text(&text))
}

fn canonicalize_text(source: &str) -> String {
    if source.is_empty() {
        return String::new();
    }

    let mut parts: Vec<&str> = source.split('\n').collect();
    if source.ends_with('\n') {
        parts.pop();
    }

    let mut normalized = parts
        .into_iter()
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
        .collect::<Vec<_>>()
        .join("\n");
    normalized.push('\n');
    normalized
}

fn path_kind(path: &Path) -> PathKind {
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return PathKind::Missing;
    };

    if metadata.file_type().is_symlink() {
        let detail = fs::read_link(path)
            .ok()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_default();
        if detail.starts_with("/nix/store/") {
            return PathKind::SymlinkStore(detail);
        }
        match fs::metadata(path) {
            Ok(target) if target.is_file() => PathKind::SymlinkRegular(detail),
            Ok(target) if target.is_dir() => PathKind::SymlinkDirectory(detail),
            Ok(_) => PathKind::SymlinkSpecial(detail),
            Err(_) => PathKind::SymlinkBroken(detail),
        }
    } else if metadata.is_file() {
        PathKind::Regular
    } else if metadata.is_dir() {
        PathKind::Directory
    } else {
        PathKind::Special
    }
}

fn write_output(bytes: &[u8], stderr: bool) -> Result<(), String> {
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

#[cfg(test)]
mod tests {
    use super::{
        adopt_target, apply_target_with_recheck, classify_target, run, ActionStatus, EmacsSyncMode,
        EmacsSyncOptions, PathKind, TargetDefinition, TargetStatus,
    };
    use std::fs;
    use tempfile::tempdir;

    fn target(root: &std::path::Path) -> TargetDefinition {
        TargetDefinition {
            id: "init",
            file_name: "init.el",
            actual_path: root.join("home/.emacs.d/init.el"),
            desired_path: root.join("repo/apps/emacs/config/init.el"),
        }
    }

    fn write_desired(target: &TargetDefinition, text: &str) {
        fs::create_dir_all(target.desired_path.parent().expect("desired parent"))
            .expect("desired dir");
        fs::write(&target.desired_path, text).expect("desired");
    }

    fn write_actual(target: &TargetDefinition, text: &str) {
        fs::create_dir_all(target.actual_path.parent().expect("actual parent"))
            .expect("actual dir");
        fs::write(&target.actual_path, text).expect("actual");
    }

    fn write_emacs_config_set(dir: &std::path::Path) {
        fs::create_dir_all(dir).expect("emacs config dir");
        fs::write(
            dir.join("early-init.el"),
            "(setq package-enable-at-startup nil)\n",
        )
        .expect("early-init");
        fs::write(dir.join("init.el"), "(setq dotfiles-emacs-ready t)\n").expect("init");
    }

    fn options(
        managed_dir: &std::path::Path,
        emacs_dir: &std::path::Path,
        mode: EmacsSyncMode,
    ) -> EmacsSyncOptions {
        EmacsSyncOptions {
            managed_dir: Some(managed_dir.to_path_buf()),
            emacs_dir: Some(emacs_dir.to_path_buf()),
            mode,
            details: false,
            diff_output: false,
            item_filter: None,
        }
    }

    #[test]
    fn classify_matching_regular_file_as_in_sync() {
        let temp = tempdir().expect("tempdir");
        let target = target(temp.path());
        write_desired(&target, "(setq dotfiles-emacs-ready t)\n");
        write_actual(&target, "(setq dotfiles-emacs-ready t)\n");

        let evaluation = classify_target(&target).expect("classify");

        assert_eq!(evaluation.status, TargetStatus::InSync);
        assert_eq!(evaluation.actual_kind, PathKind::Regular);
    }

    #[test]
    fn apply_replaces_drifted_runtime_file() {
        let temp = tempdir().expect("tempdir");
        let target = target(temp.path());
        write_desired(&target, "(setq dotfiles-emacs-ready t)\n");
        write_actual(&target, "(setq dotfiles-emacs-ready nil)\n");
        let evaluation = classify_target(&target).expect("classify");

        let status = apply_target_with_recheck(&target, &evaluation).expect("apply");

        assert_eq!(status, ActionStatus::Changed);
        assert_eq!(
            fs::read_to_string(&target.actual_path).expect("actual"),
            "(setq dotfiles-emacs-ready t)\n"
        );
    }

    #[test]
    fn adopt_copies_runtime_file_back_to_repo() {
        let temp = tempdir().expect("tempdir");
        let target = target(temp.path());
        write_desired(&target, "(setq dotfiles-emacs-ready t)\n");
        write_actual(&target, "(setq dotfiles-emacs-ready nil)\n");
        let evaluation = classify_target(&target).expect("classify");

        let status = adopt_target(&target, &evaluation).expect("adopt");

        assert_eq!(status, ActionStatus::Changed);
        assert_eq!(
            fs::read_to_string(&target.desired_path).expect("desired"),
            "(setq dotfiles-emacs-ready nil)\n"
        );
    }

    #[test]
    fn symlinked_runtime_file_requires_materialization() {
        let temp = tempdir().expect("tempdir");
        let target = target(temp.path());
        write_desired(&target, "(setq dotfiles-emacs-ready t)\n");
        let linked = temp.path().join("linked-config.el");
        fs::write(&linked, "(setq dotfiles-emacs-ready t)\n").expect("linked");
        fs::create_dir_all(target.actual_path.parent().expect("actual parent"))
            .expect("actual dir");
        #[cfg(unix)]
        std::os::unix::fs::symlink(&linked, &target.actual_path).expect("symlink");

        let evaluation = classify_target(&target).expect("classify");

        assert_eq!(evaluation.status, TargetStatus::NeedsApply);
        assert!(evaluation.shape_needs_rewrite);
        let status = apply_target_with_recheck(&target, &evaluation).expect("apply");
        assert_eq!(status, ActionStatus::Changed);
        let metadata = fs::symlink_metadata(&target.actual_path).expect("metadata");
        assert!(metadata.is_file());
        assert!(!metadata.file_type().is_symlink());
    }

    #[test]
    fn check_passes_without_external_runtime() {
        let temp = tempdir().expect("tempdir");
        let managed_dir = temp.path().join("managed");
        let emacs_dir = temp.path().join("home/.emacs.d");
        write_emacs_config_set(&managed_dir);
        write_emacs_config_set(&emacs_dir);

        let result = run(options(&managed_dir, &emacs_dir, EmacsSyncMode::Check)).unwrap();

        assert_eq!(result.exit_code(EmacsSyncMode::Check), 0);
    }

    #[test]
    fn check_fails_when_runtime_config_is_missing() {
        let temp = tempdir().expect("tempdir");
        let managed_dir = temp.path().join("managed");
        let emacs_dir = temp.path().join("home/.emacs.d");
        write_emacs_config_set(&managed_dir);

        let result = run(options(&managed_dir, &emacs_dir, EmacsSyncMode::Check)).unwrap();

        assert_eq!(result.missing, 2);
        assert_eq!(result.exit_code(EmacsSyncMode::Check), 1);
    }
}
