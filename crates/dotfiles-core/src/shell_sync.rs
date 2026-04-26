use crate::support::{home_dir, log, repo_root};
use clap::error::ErrorKind;
use clap::{Parser, ValueEnum};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use tempfile::NamedTempFile;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShellSyncMode {
    Check,
    Apply,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ShellGroup {
    Zsh,
    Bash,
}

impl ShellGroup {
    fn as_str(self) -> &'static str {
        match self {
            Self::Zsh => "zsh",
            Self::Bash => "bash",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShellSyncOptions {
    pub managed_dir: Option<PathBuf>,
    pub mode: ShellSyncMode,
    pub details: bool,
    pub diff_output: bool,
    pub group_filters: Vec<ShellGroup>,
    pub item_filter: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
enum ShellGroupArg {
    Zsh,
    Bash,
    All,
}

#[derive(Parser, Debug)]
#[command(
    name = "sync-shell",
    about = "Keep writable shell entrypoints aligned with repo-managed blocks/files.",
    disable_version_flag = true
)]
struct ShellSyncCliArgs {
    #[arg(long, conflicts_with = "apply")]
    check: bool,
    #[arg(long, conflicts_with = "check")]
    apply: bool,
    #[arg(long)]
    details: bool,
    #[arg(long = "diff")]
    diff_output: bool,
    #[arg(long = "group", value_enum)]
    group_filters: Vec<ShellGroupArg>,
    #[arg(long = "item")]
    item_filter: Option<String>,
    #[arg(long = "managed-dir")]
    managed_dir: Option<PathBuf>,
}

impl Default for ShellSyncOptions {
    fn default() -> Self {
        Self {
            managed_dir: None,
            mode: ShellSyncMode::Check,
            details: false,
            diff_output: false,
            group_filters: Vec::new(),
            item_filter: None,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ShellSyncResult {
    pub selected_count: u32,
    pub checked: u32,
    pub in_sync: u32,
    pub needs_apply: u32,
    pub missing: u32,
    pub invalid: u32,
    pub applied: u32,
    pub errors: u32,
}

impl ShellSyncResult {
    pub fn exit_code(&self, mode: ShellSyncMode) -> i32 {
        match mode {
            ShellSyncMode::Apply => {
                if self.errors == 0 {
                    0
                } else {
                    1
                }
            }
            ShellSyncMode::Check => {
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

#[derive(Clone, Debug)]
struct TargetDefinition {
    id: &'static str,
    shell_name: ShellGroup,
    actual_path: PathBuf,
    desired_path: PathBuf,
    begin_marker: &'static str,
    end_marker: &'static str,
}

#[derive(Clone, Copy, Debug)]
struct TargetSpec {
    id: &'static str,
    shell_name: ShellGroup,
    actual_relative_path: &'static str,
    desired_file_name: &'static str,
    begin_marker: &'static str,
    end_marker: &'static str,
}

const TARGET_SPECS: [TargetSpec; 2] = [
    TargetSpec {
        id: "zsh-zdotdir",
        shell_name: ShellGroup::Zsh,
        actual_relative_path: ".nix/.zshrc",
        desired_file_name: "zdotdir.zshrc.block.sh",
        begin_marker: "# >>> dotfiles-managed:zdotdir.zshrc >>>",
        end_marker: "# <<< dotfiles-managed:zdotdir.zshrc <<<",
    },
    TargetSpec {
        id: "bash-rc",
        shell_name: ShellGroup::Bash,
        actual_relative_path: ".bashrc",
        desired_file_name: "bashrc.entrypoint.block.sh",
        begin_marker: "# >>> dotfiles-managed:bashrc >>>",
        end_marker: "# <<< dotfiles-managed:bashrc <<<",
    },
];

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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ExtractError {
    MissingBlock,
    InvalidBlock,
}

pub fn run_cli(args: &[String]) -> Result<ShellSyncResult, String> {
    let options = parse_cli_args(args)?;
    run(options)
}

pub fn run(mut options: ShellSyncOptions) -> Result<ShellSyncResult, String> {
    if options.managed_dir.is_none() {
        options.managed_dir = Some(repo_root()?.join("surfaces/shell/desired"));
    }

    let managed_dir = options
        .managed_dir
        .clone()
        .ok_or_else(|| "managed dir is required".to_string())?;

    if !managed_dir.is_dir() {
        return Err(format!("managed dir not found: {}", managed_dir.display()));
    }

    let targets = list_targets(&managed_dir)?;
    let mut result = ShellSyncResult::default();

    for target in targets {
        if !target_selected(&options, &target) {
            continue;
        }

        result.selected_count += 1;
        result.checked += 1;

        let mut evaluation = classify_target(&target)?;
        match evaluation.status {
            TargetStatus::InSync => result.in_sync += 1,
            TargetStatus::NeedsApply => result.needs_apply += 1,
            TargetStatus::Missing => result.missing += 1,
            TargetStatus::Invalid => result.invalid += 1,
        }

        if options.details {
            print_target_details(&target, &evaluation);
        }

        if options.diff_output && evaluation.status == TargetStatus::NeedsApply {
            print_target_diff(&target, &evaluation)?;
        }

        if options.mode == ShellSyncMode::Apply {
            match apply_target_with_recheck(&target, &evaluation)? {
                ApplyStatus::Skipped => {}
                ApplyStatus::Applied => result.applied += 1,
                ApplyStatus::Error(message) => {
                    result.errors += 1;
                    log(&message);
                }
            }
        }
    }

    if result.selected_count == 0 {
        if let Some(item) = &options.item_filter {
            return Err(format!("no item matched --item '{}'", item));
        }
        if !options.group_filters.is_empty() {
            let joined = options
                .group_filters
                .iter()
                .map(|group| group.as_str())
                .collect::<Vec<_>>()
                .join(",");
            return Err(format!("no item matched --group '{}'", joined));
        }
        return Err("no shell targets selected".to_string());
    }

    log(&format!(
        "summary: checked={} in_sync={} needs_apply={} missing={} invalid={} applied={} errors={}",
        result.checked,
        result.in_sync,
        result.needs_apply,
        result.missing,
        result.invalid,
        result.applied,
        result.errors
    ));

    Ok(result)
}

fn parse_cli_args(args: &[String]) -> Result<ShellSyncOptions, String> {
    for arg in args {
        match arg.as_str() {
            "--adopt" | "--forget" | "--migrate" | "--state-dir" | "--force" | "--in-place"
            | "--output-dir" => {
                return Err(format!("{} is no longer supported for sync shell", arg));
            }
            _ => {}
        }
    }

    let parsed = parse_cli_or_display(ShellSyncCliArgs::try_parse_from(
        std::iter::once("sync-shell".to_string()).chain(args.iter().cloned()),
    ))?;

    let mut group_filters = Vec::new();
    let group_all = parsed
        .group_filters
        .iter()
        .any(|group| matches!(group, ShellGroupArg::All));
    if !group_all {
        for group in parsed.group_filters {
            match group {
                ShellGroupArg::Zsh => push_group_filter(&mut group_filters, ShellGroup::Zsh),
                ShellGroupArg::Bash => push_group_filter(&mut group_filters, ShellGroup::Bash),
                ShellGroupArg::All => {}
            }
        }
    }

    Ok(ShellSyncOptions {
        managed_dir: parsed.managed_dir,
        mode: if parsed.apply {
            ShellSyncMode::Apply
        } else {
            ShellSyncMode::Check
        },
        details: parsed.details,
        diff_output: parsed.diff_output,
        group_filters,
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

fn push_group_filter(filters: &mut Vec<ShellGroup>, group: ShellGroup) {
    if !filters.iter().any(|entry| entry == &group) {
        filters.push(group);
    }
}

fn list_targets(managed_dir: &Path) -> Result<Vec<TargetDefinition>, String> {
    let home_path = home_dir()?;
    Ok(TARGET_SPECS
        .iter()
        .map(|spec| TargetDefinition {
            id: spec.id,
            shell_name: spec.shell_name,
            actual_path: home_path.join(spec.actual_relative_path),
            desired_path: managed_dir.join(spec.desired_file_name),
            begin_marker: spec.begin_marker,
            end_marker: spec.end_marker,
        })
        .collect())
}

fn target_selected(options: &ShellSyncOptions, target: &TargetDefinition) -> bool {
    if let Some(item) = &options.item_filter {
        if target.id != item {
            return false;
        }
    }

    if options.group_filters.is_empty() {
        return true;
    }

    options
        .group_filters
        .iter()
        .any(|group| group == &target.shell_name)
}

fn classify_target(target: &TargetDefinition) -> Result<TargetEvaluation, String> {
    let desired_text = canonicalize_file(&target.desired_path)
        .map_err(|_| format!("desired file not found: {}", target.desired_path.display()))?;
    let actual_kind = path_kind(&target.actual_path);
    let mut evaluation = TargetEvaluation {
        status: TargetStatus::Invalid,
        reason: String::new(),
        actual_kind: actual_kind.clone(),
        shape_needs_rewrite: matches!(
            actual_kind,
            PathKind::SymlinkStore(_) | PathKind::SymlinkRegular(_)
        ),
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
            evaluation.reason = "non-store symlink does not resolve to a regular file".to_string();
            Ok(evaluation)
        }
        PathKind::Regular | PathKind::SymlinkStore(_) | PathKind::SymlinkRegular(_) => {
            let actual_source =
                read_existing_source(&target.actual_path, &actual_kind).map_err(|_| {
                    format!(
                        "failed to inspect target contents: {}",
                        target.actual_path.display()
                    )
                })?;
            match extract_managed_block(&actual_source, target.begin_marker, target.end_marker) {
                Ok(actual_text) => {
                    evaluation.actual_text = actual_text;
                    if evaluation.shape_needs_rewrite {
                        evaluation.status = TargetStatus::NeedsApply;
                        evaluation.reason =
                            "target should be materialized as a writable regular file".to_string();
                    } else if evaluation.actual_text == evaluation.desired_text {
                        evaluation.status = TargetStatus::InSync;
                        evaluation.reason = "managed block matches desired".to_string();
                    } else {
                        evaluation.status = TargetStatus::NeedsApply;
                        evaluation.reason = "managed block differs from desired".to_string();
                    }
                    Ok(evaluation)
                }
                Err(ExtractError::MissingBlock) => {
                    evaluation.status = TargetStatus::NeedsApply;
                    evaluation.reason = if evaluation.shape_needs_rewrite {
                        "target should be materialized as a writable regular file".to_string()
                    } else {
                        "managed block is missing".to_string()
                    };
                    Ok(evaluation)
                }
                Err(ExtractError::InvalidBlock) => {
                    evaluation.status = TargetStatus::Invalid;
                    evaluation.reason =
                        "managed block markers are duplicated or malformed".to_string();
                    Ok(evaluation)
                }
            }
        }
    }
}

fn print_target_details(target: &TargetDefinition, evaluation: &TargetEvaluation) {
    log(&format!("details: {}", target.id));
    log(&format!("  shell: {}", target.shell_name.as_str()));
    log("  type: block");
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
    if evaluation.shape_needs_rewrite && evaluation.actual_text == evaluation.desired_text {
        log("  note: content matches desired, but target must be rewritten as a writable regular file");
        return Ok(());
    }
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

fn apply_target(target: &TargetDefinition, evaluation: &TargetEvaluation) -> Result<(), String> {
    match evaluation.actual_kind {
        PathKind::Missing
        | PathKind::Regular
        | PathKind::SymlinkStore(_)
        | PathKind::SymlinkRegular(_) => write_entrypoint_file(
            &target.actual_path,
            &target.desired_path,
            target.begin_marker,
            target.end_marker,
        ),
        _ => Err("target is not writable".to_string()),
    }
}

#[derive(Debug, PartialEq, Eq)]
enum ApplyStatus {
    Skipped,
    Applied,
    Error(String),
}

fn apply_target_with_recheck(
    target: &TargetDefinition,
    evaluation: &TargetEvaluation,
) -> Result<ApplyStatus, String> {
    match evaluation.status {
        TargetStatus::InSync => Ok(ApplyStatus::Skipped),
        TargetStatus::Invalid => Ok(ApplyStatus::Error(format!(
            "apply refused for '{}': {}",
            target.id, evaluation.reason
        ))),
        TargetStatus::Missing | TargetStatus::NeedsApply => {
            match apply_target(target, evaluation) {
                Ok(()) => {
                    let post = classify_target(target)?;
                    if post.status == TargetStatus::InSync {
                        Ok(ApplyStatus::Applied)
                    } else {
                        Ok(ApplyStatus::Error(format!(
                            "apply failed to converge '{}': status={} reason={}",
                            target.id,
                            post.status.as_str(),
                            post.reason
                        )))
                    }
                }
                Err(err) => Ok(ApplyStatus::Error(format!(
                    "apply failed for '{}': {}",
                    target.id, err
                ))),
            }
        }
    }
}

fn write_entrypoint_file(
    target_file: &Path,
    desired_file: &Path,
    begin_marker: &str,
    end_marker: &str,
) -> Result<(), String> {
    let desired_text = canonicalize_file(desired_file)
        .map_err(|_| format!("desired file not found: {}", desired_file.display()))?;
    let output = if target_file.exists() || fs::symlink_metadata(target_file).is_ok() {
        let kind = path_kind(target_file);
        let source = read_existing_source(target_file, &kind)
            .map_err(|_| format!("failed to read target contents: {}", target_file.display()))?;
        match replace_managed_block(&source, &desired_text, begin_marker, end_marker) {
            Ok(updated) => updated,
            Err(ExtractError::MissingBlock) => {
                let mut updated = managed_block_text(&desired_text, begin_marker, end_marker);
                if !source.is_empty() {
                    updated.push('\n');
                    updated.push_str(&source);
                }
                updated
            }
            Err(ExtractError::InvalidBlock) => {
                return Err("managed block markers are duplicated or malformed".to_string())
            }
        }
    } else {
        managed_block_text(&desired_text, begin_marker, end_marker)
    };

    write_file_atomically(target_file, &output)
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

fn managed_block_text(desired_text: &str, begin_marker: &str, end_marker: &str) -> String {
    let mut output = String::new();
    output.push_str(begin_marker);
    output.push('\n');
    output.push_str(desired_text);
    output.push_str(end_marker);
    output.push('\n');
    output
}

fn canonicalize_file(path: &Path) -> io::Result<String> {
    fs::read_to_string(path).map(|text| canonicalize_text(&text))
}

fn read_existing_source(path: &Path, kind: &PathKind) -> io::Result<String> {
    match canonicalize_file(path) {
        Ok(source) => Ok(source),
        Err(_) if matches!(kind, PathKind::SymlinkStore(_)) => Ok(String::new()),
        Err(err) => Err(err),
    }
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

fn extract_managed_block(
    source: &str,
    begin_marker: &str,
    end_marker: &str,
) -> Result<String, ExtractError> {
    let mut begin_count = 0u32;
    let mut end_count = 0u32;
    let mut in_block = false;
    let mut block = String::new();

    for line in source.lines() {
        if line == begin_marker {
            begin_count += 1;
            if begin_count > 1 || in_block {
                return Err(ExtractError::InvalidBlock);
            }
            in_block = true;
            continue;
        }

        if line == end_marker {
            end_count += 1;
            if !in_block || end_count > 1 {
                return Err(ExtractError::InvalidBlock);
            }
            in_block = false;
            continue;
        }

        if in_block {
            block.push_str(line);
            block.push('\n');
        }
    }

    if begin_count == 0 && end_count == 0 {
        return Err(ExtractError::MissingBlock);
    }
    if begin_count == 1 && end_count == 1 && !in_block {
        return Ok(block);
    }
    Err(ExtractError::InvalidBlock)
}

fn replace_managed_block(
    source: &str,
    desired_text: &str,
    begin_marker: &str,
    end_marker: &str,
) -> Result<String, ExtractError> {
    let mut begin_count = 0u32;
    let mut end_count = 0u32;
    let mut in_block = false;
    let mut output = String::new();

    for line in source.lines() {
        if line == begin_marker {
            begin_count += 1;
            if begin_count > 1 || in_block {
                return Err(ExtractError::InvalidBlock);
            }
            output.push_str(begin_marker);
            output.push('\n');
            output.push_str(desired_text);
            in_block = true;
            continue;
        }

        if line == end_marker {
            end_count += 1;
            if !in_block || end_count > 1 {
                return Err(ExtractError::InvalidBlock);
            }
            in_block = false;
            output.push_str(end_marker);
            output.push('\n');
            continue;
        }

        if !in_block {
            output.push_str(line);
            output.push('\n');
        }
    }

    if begin_count == 0 && end_count == 0 {
        return Err(ExtractError::MissingBlock);
    }
    if begin_count == 1 && end_count == 1 && !in_block {
        return Ok(output);
    }
    Err(ExtractError::InvalidBlock)
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
        apply_target_with_recheck, classify_target, write_entrypoint_file, ApplyStatus, PathKind,
        ShellGroup, TargetDefinition, TargetStatus,
    };
    use std::fs;
    use tempfile::tempdir;

    fn setup_managed_dir(root: &std::path::Path) -> std::path::PathBuf {
        let managed = root.join("managed");
        fs::create_dir_all(&managed).expect("managed dir");
        fs::write(
            managed.join("bashrc.entrypoint.block.sh"),
            "source ~/.nix/hm-bash/.bashrc\n",
        )
        .expect("write bash");
        fs::write(
            managed.join("zdotdir.zshrc.block.sh"),
            "source ~/.nix/hm-zsh/.zshrc\n",
        )
        .expect("write zsh");
        managed
    }

    #[test]
    fn classify_missing_target_reports_missing() {
        let temp = tempdir().expect("tempdir");
        let managed = setup_managed_dir(temp.path());
        let target = TargetDefinition {
            id: "bash-rc",
            shell_name: ShellGroup::Bash,
            actual_path: temp.path().join("home/.bashrc"),
            desired_path: managed.join("bashrc.entrypoint.block.sh"),
            begin_marker: "# >>> dotfiles-managed:bashrc >>>",
            end_marker: "# <<< dotfiles-managed:bashrc <<<",
        };

        let evaluation = classify_target(&target).expect("classify");
        assert_eq!(evaluation.status, TargetStatus::Missing);
        assert_eq!(evaluation.actual_kind, PathKind::Missing);
    }

    #[test]
    fn apply_preserves_unmanaged_tail_when_block_missing() {
        let temp = tempdir().expect("tempdir");
        let managed = setup_managed_dir(temp.path());
        let bashrc_path = temp.path().join("home/.bashrc");
        fs::create_dir_all(bashrc_path.parent().expect("parent")).expect("parent dir");
        fs::write(&bashrc_path, "# custom tail\n").expect("write tail");

        write_entrypoint_file(
            &bashrc_path,
            &managed.join("bashrc.entrypoint.block.sh"),
            "# >>> dotfiles-managed:bashrc >>>",
            "# <<< dotfiles-managed:bashrc <<<",
        )
        .expect("apply");

        let bashrc = fs::read_to_string(&bashrc_path).expect("bashrc");
        assert!(bashrc.contains("# custom tail"));
        assert!(bashrc.contains("# >>> dotfiles-managed:bashrc >>>"));
    }

    #[test]
    fn classify_broken_store_symlink_as_repairable() {
        let temp = tempdir().expect("tempdir");
        let managed = setup_managed_dir(temp.path());
        let bashrc_path = temp.path().join("home/.bashrc");
        fs::create_dir_all(bashrc_path.parent().expect("parent")).expect("parent dir");
        #[cfg(unix)]
        std::os::unix::fs::symlink("/nix/store/fake-hm-bashrc", &bashrc_path).expect("symlink");

        let target = TargetDefinition {
            id: "bash-rc",
            shell_name: ShellGroup::Bash,
            actual_path: bashrc_path,
            desired_path: managed.join("bashrc.entrypoint.block.sh"),
            begin_marker: "# >>> dotfiles-managed:bashrc >>>",
            end_marker: "# <<< dotfiles-managed:bashrc <<<",
        };

        let evaluation = classify_target(&target).expect("classify");
        assert_eq!(evaluation.status, TargetStatus::NeedsApply);
        assert_eq!(
            evaluation.reason,
            "target should be materialized as a writable regular file"
        );
        assert!(matches!(evaluation.actual_kind, PathKind::SymlinkStore(_)));
    }

    #[test]
    fn apply_materializes_broken_store_symlink() {
        let temp = tempdir().expect("tempdir");
        let managed = setup_managed_dir(temp.path());
        let bashrc_path = temp.path().join("home/.bashrc");
        fs::create_dir_all(bashrc_path.parent().expect("parent")).expect("parent dir");
        #[cfg(unix)]
        std::os::unix::fs::symlink("/nix/store/fake-hm-bashrc", &bashrc_path).expect("symlink");

        write_entrypoint_file(
            &bashrc_path,
            &managed.join("bashrc.entrypoint.block.sh"),
            "# >>> dotfiles-managed:bashrc >>>",
            "# <<< dotfiles-managed:bashrc <<<",
        )
        .expect("apply");

        let metadata = fs::symlink_metadata(&bashrc_path).expect("metadata");
        assert!(metadata.is_file());
        assert!(!metadata.file_type().is_symlink());

        let bashrc = fs::read_to_string(&bashrc_path).expect("bashrc");
        assert!(bashrc.contains("# >>> dotfiles-managed:bashrc >>>"));
        assert!(bashrc.contains("source ~/.nix/hm-bash/.bashrc"));
    }

    #[test]
    fn apply_reports_root_cause_when_parent_path_is_not_a_directory() {
        let temp = tempdir().expect("tempdir");
        let managed = setup_managed_dir(temp.path());
        let home_dir = temp.path().join("home");
        fs::create_dir_all(&home_dir).expect("home");
        let blocked_parent = home_dir.join(".nix");
        fs::write(&blocked_parent, "not a directory\n").expect("blocked");

        let target = TargetDefinition {
            id: "zsh-zdotdir",
            shell_name: ShellGroup::Zsh,
            actual_path: blocked_parent.join(".zshrc"),
            desired_path: managed.join("zdotdir.zshrc.block.sh"),
            begin_marker: "# >>> dotfiles-managed:zdotdir.zshrc >>>",
            end_marker: "# <<< dotfiles-managed:zdotdir.zshrc <<<",
        };

        let evaluation = classify_target(&target).expect("classify");
        assert_eq!(evaluation.status, TargetStatus::Missing);

        let status = apply_target_with_recheck(&target, &evaluation).expect("apply");
        match status {
            ApplyStatus::Error(message) => {
                assert!(message.contains("apply failed for 'zsh-zdotdir':"));
                assert!(message.contains("failed to create"));
            }
            other => panic!("expected root-cause apply error, got {:?}", other),
        }
    }
}
