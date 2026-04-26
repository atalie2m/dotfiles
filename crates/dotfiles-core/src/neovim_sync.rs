use crate::support::{home_dir, log, repo_root};
use clap::error::ErrorKind;
use clap::Parser;
use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use tempfile::NamedTempFile;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NeovimSyncMode {
    Check,
    Apply,
    Adopt,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NeovimSyncOptions {
    pub managed_dir: Option<PathBuf>,
    pub runtime_dir: Option<PathBuf>,
    pub state_dir: Option<PathBuf>,
    pub mode: NeovimSyncMode,
    pub details: bool,
    pub diff_output: bool,
}

impl Default for NeovimSyncOptions {
    fn default() -> Self {
        Self {
            managed_dir: None,
            runtime_dir: None,
            state_dir: None,
            mode: NeovimSyncMode::Check,
            details: false,
            diff_output: false,
        }
    }
}

#[derive(Parser, Debug)]
#[command(
    name = "sync-neovim",
    about = "Reconcile repo-managed Neovim config with runtime config and Lazy lock state.",
    disable_version_flag = true
)]
struct NeovimSyncCliArgs {
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
    #[arg(long = "managed-dir")]
    managed_dir: Option<PathBuf>,
    #[arg(long = "runtime-dir")]
    runtime_dir: Option<PathBuf>,
    #[arg(long = "state-dir")]
    state_dir: Option<PathBuf>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NeovimSyncResult {
    pub checked: u32,
    pub in_sync: u32,
    pub needs_apply: u32,
    pub missing: u32,
    pub runtime_only: u32,
    pub invalid: u32,
    pub applied: u32,
    pub adopted: u32,
    pub errors: u32,
}

impl NeovimSyncResult {
    pub fn exit_code(&self, mode: NeovimSyncMode) -> i32 {
        match mode {
            NeovimSyncMode::Check => {
                if self.needs_apply == 0
                    && self.missing == 0
                    && self.runtime_only == 0
                    && self.invalid == 0
                    && self.errors == 0
                {
                    0
                } else {
                    1
                }
            }
            NeovimSyncMode::Apply | NeovimSyncMode::Adopt => {
                if self.errors == 0 {
                    0
                } else {
                    1
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ItemKind {
    Config,
    LazyLock,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ItemStatus {
    InSync,
    NeedsApply,
    Missing,
    RuntimeOnly,
    Invalid,
}

impl ItemStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::InSync => "in-sync",
            Self::NeedsApply => "needs-apply",
            Self::Missing => "missing",
            Self::RuntimeOnly => "runtime-only",
            Self::Invalid => "invalid",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PathSide {
    Managed,
    Runtime,
}

impl PathSide {
    fn as_str(self) -> &'static str {
        match self {
            Self::Managed => "managed",
            Self::Runtime => "runtime",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct FileSnapshot {
    path: PathBuf,
    bytes: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PathIssue {
    rel_path: PathBuf,
    path: PathBuf,
    side: PathSide,
    reason: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct TreeSnapshot {
    files: BTreeMap<PathBuf, FileSnapshot>,
    issues: Vec<PathIssue>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SyncItem {
    rel_path: PathBuf,
    kind: ItemKind,
    status: ItemStatus,
    reason: String,
    managed_path: Option<PathBuf>,
    actual_path: Option<PathBuf>,
    desired: Option<Vec<u8>>,
    actual: Option<Vec<u8>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum OptionalSnapshot {
    Missing,
    File(FileSnapshot),
    Invalid(PathIssue),
}

pub fn run_cli(args: &[String]) -> Result<NeovimSyncResult, String> {
    let options = parse_cli_args(args)?;
    run(options)
}

pub fn run(mut options: NeovimSyncOptions) -> Result<NeovimSyncResult, String> {
    if options.managed_dir.is_none() {
        options.managed_dir = Some(repo_root()?.join("apps/neovim"));
    }
    if options.runtime_dir.is_none() {
        options.runtime_dir = Some(default_xdg_dir("XDG_CONFIG_HOME", ".config")?.join("nvim"));
    }
    if options.state_dir.is_none() {
        options.state_dir = Some(default_xdg_dir("XDG_STATE_HOME", ".local/state")?.join("nvim"));
    }

    let managed_dir = options
        .managed_dir
        .clone()
        .ok_or_else(|| "managed dir is required".to_string())?;
    let runtime_dir = options
        .runtime_dir
        .clone()
        .ok_or_else(|| "runtime dir is required".to_string())?;
    let state_dir = options
        .state_dir
        .clone()
        .ok_or_else(|| "state dir is required".to_string())?;

    if !managed_dir.is_dir() {
        return Err(format!("managed dir not found: {}", managed_dir.display()));
    }

    let items = classify_items(&managed_dir, &runtime_dir, &state_dir)?;
    let runtime_root_is_symlink = path_is_symlink(&runtime_dir);
    let mut result = NeovimSyncResult::default();

    for item in items {
        result.checked += 1;
        match item.status {
            ItemStatus::InSync => result.in_sync += 1,
            ItemStatus::NeedsApply => result.needs_apply += 1,
            ItemStatus::Missing => result.missing += 1,
            ItemStatus::RuntimeOnly => result.runtime_only += 1,
            ItemStatus::Invalid => result.invalid += 1,
        }

        if options.details {
            print_item_details(&item);
        }

        if options.diff_output
            && item.status != ItemStatus::InSync
            && item.status != ItemStatus::Invalid
        {
            print_item_diff(&item)?;
        }

        match options.mode {
            NeovimSyncMode::Check => {}
            NeovimSyncMode::Apply => {
                match apply_item(&item, &runtime_dir, &state_dir, runtime_root_is_symlink) {
                    Ok(ActionStatus::Skipped) => {}
                    Ok(ActionStatus::Changed) => result.applied += 1,
                    Err(err) => {
                        result.errors += 1;
                        log(&format!(
                            "apply failed for '{}': {}",
                            display_rel(&item.rel_path),
                            err
                        ));
                    }
                }
            }
            NeovimSyncMode::Adopt => match adopt_item(&item, &managed_dir) {
                Ok(ActionStatus::Skipped) => {}
                Ok(ActionStatus::Changed) => result.adopted += 1,
                Err(err) => {
                    result.errors += 1;
                    log(&format!(
                        "adopt failed for '{}': {}",
                        display_rel(&item.rel_path),
                        err
                    ));
                }
            },
        }
    }

    if result.checked == 0 {
        return Err("no Neovim config entries selected".to_string());
    }

    log(&format!(
        "summary: checked={} in_sync={} needs_apply={} missing={} runtime_only={} invalid={} applied={} adopted={} errors={}",
        result.checked,
        result.in_sync,
        result.needs_apply,
        result.missing,
        result.runtime_only,
        result.invalid,
        result.applied,
        result.adopted,
        result.errors
    ));

    Ok(result)
}

fn parse_cli_args(args: &[String]) -> Result<NeovimSyncOptions, String> {
    let parsed = parse_cli_or_display(NeovimSyncCliArgs::try_parse_from(
        std::iter::once("sync-neovim".to_string()).chain(args.iter().cloned()),
    ))?;

    Ok(NeovimSyncOptions {
        managed_dir: parsed.managed_dir,
        runtime_dir: parsed.runtime_dir,
        state_dir: parsed.state_dir,
        mode: if parsed.apply {
            NeovimSyncMode::Apply
        } else if parsed.adopt {
            NeovimSyncMode::Adopt
        } else {
            NeovimSyncMode::Check
        },
        details: parsed.details,
        diff_output: parsed.diff_output,
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

fn default_xdg_dir(env_name: &str, fallback_relative: &str) -> Result<PathBuf, String> {
    match env::var(env_name) {
        Ok(value) if !value.is_empty() => Ok(PathBuf::from(value)),
        _ => Ok(home_dir()?.join(fallback_relative)),
    }
}

fn classify_items(
    managed_dir: &Path,
    runtime_dir: &Path,
    state_dir: &Path,
) -> Result<Vec<SyncItem>, String> {
    let managed = collect_tree(managed_dir, PathSide::Managed)?;
    let runtime = collect_tree(runtime_dir, PathSide::Runtime)?;
    let mut rel_paths = BTreeSet::new();
    for rel_path in managed.files.keys() {
        rel_paths.insert(rel_path.clone());
    }
    for rel_path in runtime.files.keys() {
        rel_paths.insert(rel_path.clone());
    }

    let mut items = Vec::new();
    for rel_path in rel_paths {
        if is_runtime_metadata(&rel_path) {
            continue;
        }
        let desired = managed.files.get(&rel_path);
        let actual = runtime.files.get(&rel_path);
        items.push(classify_pair(
            rel_path,
            ItemKind::Config,
            desired.cloned(),
            actual.cloned(),
        ));
    }

    items.push(classify_lazy_lock(managed_dir, runtime_dir, state_dir)?);

    for issue in managed.issues.into_iter().chain(runtime.issues) {
        items.push(SyncItem {
            rel_path: issue.rel_path,
            kind: ItemKind::Config,
            status: ItemStatus::Invalid,
            reason: format!("{} path is invalid: {}", issue.side.as_str(), issue.reason),
            managed_path: (issue.side == PathSide::Managed).then_some(issue.path.clone()),
            actual_path: (issue.side == PathSide::Runtime).then_some(issue.path),
            desired: None,
            actual: None,
        });
    }

    items.sort_by(|left, right| left.rel_path.cmp(&right.rel_path));
    Ok(items)
}

fn classify_pair(
    rel_path: PathBuf,
    kind: ItemKind,
    desired: Option<FileSnapshot>,
    actual: Option<FileSnapshot>,
) -> SyncItem {
    let managed_path = desired.as_ref().map(|file| file.path.clone());
    let actual_path = actual.as_ref().map(|file| file.path.clone());
    let desired_bytes = desired.as_ref().map(|file| file.bytes.clone());
    let actual_bytes = actual.as_ref().map(|file| file.bytes.clone());
    let (status, reason) = match (&desired_bytes, &actual_bytes) {
        (Some(left), Some(right)) if left == right => (
            ItemStatus::InSync,
            "runtime file matches managed".to_string(),
        ),
        (Some(_), Some(_)) => (
            ItemStatus::NeedsApply,
            match kind {
                ItemKind::Config => "runtime file differs from managed".to_string(),
                ItemKind::LazyLock => "effective lazy lock differs from managed".to_string(),
            },
        ),
        (Some(_), None) => (
            ItemStatus::Missing,
            match kind {
                ItemKind::Config => "runtime file is missing".to_string(),
                ItemKind::LazyLock => "effective lazy lock is missing".to_string(),
            },
        ),
        (None, Some(_)) => (
            ItemStatus::RuntimeOnly,
            match kind {
                ItemKind::Config => "runtime file is not managed".to_string(),
                ItemKind::LazyLock => "effective lazy lock is not managed".to_string(),
            },
        ),
        (None, None) => (
            ItemStatus::Invalid,
            "neither managed nor runtime file exists".to_string(),
        ),
    };

    SyncItem {
        rel_path,
        kind,
        status,
        reason,
        managed_path,
        actual_path,
        desired: desired_bytes,
        actual: actual_bytes,
    }
}

fn classify_lazy_lock(
    managed_dir: &Path,
    runtime_dir: &Path,
    state_dir: &Path,
) -> Result<SyncItem, String> {
    let rel_path = PathBuf::from("lazy-lock.json");
    let managed_lock = read_optional_snapshot(
        &managed_dir.join(&rel_path),
        rel_path.clone(),
        PathSide::Managed,
    )?;
    let state_lock = read_optional_snapshot(
        &state_dir.join(&rel_path),
        rel_path.clone(),
        PathSide::Runtime,
    )?;
    let runtime_lock = read_optional_snapshot(
        &runtime_dir.join(&rel_path),
        rel_path.clone(),
        PathSide::Runtime,
    )?;

    let desired = match managed_lock {
        OptionalSnapshot::File(snapshot) => Some(snapshot),
        OptionalSnapshot::Missing => None,
        OptionalSnapshot::Invalid(issue) => return Ok(invalid_item(issue, ItemKind::LazyLock)),
    };

    let actual = match state_lock {
        OptionalSnapshot::File(snapshot) => Some(snapshot),
        OptionalSnapshot::Missing => match runtime_lock {
            OptionalSnapshot::File(snapshot) => Some(snapshot),
            OptionalSnapshot::Missing => None,
            OptionalSnapshot::Invalid(issue) => return Ok(invalid_item(issue, ItemKind::LazyLock)),
        },
        OptionalSnapshot::Invalid(issue) => return Ok(invalid_item(issue, ItemKind::LazyLock)),
    };

    Ok(classify_pair(rel_path, ItemKind::LazyLock, desired, actual))
}

fn invalid_item(issue: PathIssue, kind: ItemKind) -> SyncItem {
    SyncItem {
        rel_path: issue.rel_path,
        kind,
        status: ItemStatus::Invalid,
        reason: format!("{} path is invalid: {}", issue.side.as_str(), issue.reason),
        managed_path: (issue.side == PathSide::Managed).then_some(issue.path.clone()),
        actual_path: (issue.side == PathSide::Runtime).then_some(issue.path),
        desired: None,
        actual: None,
    }
}

fn collect_tree(root: &Path, side: PathSide) -> Result<TreeSnapshot, String> {
    let mut snapshot = TreeSnapshot::default();
    match fs::symlink_metadata(root) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                match fs::metadata(root) {
                    Ok(target) if target.is_dir() => collect_dir(root, root, side, &mut snapshot)?,
                    Ok(_) => snapshot.issues.push(PathIssue {
                        rel_path: PathBuf::from("."),
                        path: root.to_path_buf(),
                        side,
                        reason: "root is not a directory".to_string(),
                    }),
                    Err(err) => snapshot.issues.push(PathIssue {
                        rel_path: PathBuf::from("."),
                        path: root.to_path_buf(),
                        side,
                        reason: format!("root symlink is unreadable: {}", err),
                    }),
                }
            } else if metadata.is_dir() {
                collect_dir(root, root, side, &mut snapshot)?;
            } else {
                snapshot.issues.push(PathIssue {
                    rel_path: PathBuf::from("."),
                    path: root.to_path_buf(),
                    side,
                    reason: "root is not a directory".to_string(),
                });
            }
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => {
            return Err(format!(
                "failed to inspect {} dir {}: {}",
                side.as_str(),
                root.display(),
                err
            ));
        }
    }
    Ok(snapshot)
}

fn collect_dir(
    root: &Path,
    dir: &Path,
    side: PathSide,
    snapshot: &mut TreeSnapshot,
) -> Result<(), String> {
    let entries = fs::read_dir(dir).map_err(|err| {
        format!(
            "failed to read {} dir {}: {}",
            side.as_str(),
            dir.display(),
            err
        )
    })?;

    for entry in entries {
        let entry = entry.map_err(|err| {
            format!(
                "failed to read {} dir entry in {}: {}",
                side.as_str(),
                dir.display(),
                err
            )
        })?;
        let path = entry.path();
        let rel_path = path
            .strip_prefix(root)
            .map_err(|err| {
                format!(
                    "failed to compute relative path for {}: {}",
                    path.display(),
                    err
                )
            })?
            .to_path_buf();

        if is_runtime_metadata(&rel_path) {
            continue;
        }

        collect_path(root, &path, rel_path, side, snapshot)?;
    }

    Ok(())
}

fn collect_path(
    root: &Path,
    path: &Path,
    rel_path: PathBuf,
    side: PathSide,
    snapshot: &mut TreeSnapshot,
) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path).map_err(|err| {
        format!(
            "failed to inspect {} path {}: {}",
            side.as_str(),
            path.display(),
            err
        )
    })?;

    if metadata.file_type().is_symlink() {
        match fs::metadata(path) {
            Ok(target) if target.is_dir() => collect_dir(root, path, side, snapshot),
            Ok(target) if target.is_file() => {
                add_file(snapshot, path, rel_path, side)?;
                Ok(())
            }
            Ok(_) => {
                snapshot.issues.push(PathIssue {
                    rel_path,
                    path: path.to_path_buf(),
                    side,
                    reason: "symlink target is not a regular file or directory".to_string(),
                });
                Ok(())
            }
            Err(err) => {
                snapshot.issues.push(PathIssue {
                    rel_path,
                    path: path.to_path_buf(),
                    side,
                    reason: format!("symlink target is unreadable: {}", err),
                });
                Ok(())
            }
        }
    } else if metadata.is_dir() {
        collect_dir(root, path, side, snapshot)
    } else if metadata.is_file() {
        add_file(snapshot, path, rel_path, side)?;
        Ok(())
    } else {
        snapshot.issues.push(PathIssue {
            rel_path,
            path: path.to_path_buf(),
            side,
            reason: "path is not a regular file or directory".to_string(),
        });
        Ok(())
    }
}

fn add_file(
    snapshot: &mut TreeSnapshot,
    path: &Path,
    rel_path: PathBuf,
    side: PathSide,
) -> Result<(), String> {
    let bytes = fs::read(path).map_err(|err| {
        format!(
            "failed to read {} file {}: {}",
            side.as_str(),
            path.display(),
            err
        )
    })?;
    snapshot.files.insert(
        rel_path,
        FileSnapshot {
            path: path.to_path_buf(),
            bytes,
        },
    );
    Ok(())
}

fn read_optional_snapshot(
    path: &Path,
    rel_path: PathBuf,
    side: PathSide,
) -> Result<OptionalSnapshot, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                match fs::metadata(path) {
                    Ok(target) if target.is_file() => {
                        read_snapshot_file(path).map(OptionalSnapshot::File)
                    }
                    Ok(_) => Ok(OptionalSnapshot::Invalid(PathIssue {
                        rel_path,
                        path: path.to_path_buf(),
                        side,
                        reason: "symlink target is not a regular file".to_string(),
                    })),
                    Err(err) => Ok(OptionalSnapshot::Invalid(PathIssue {
                        rel_path,
                        path: path.to_path_buf(),
                        side,
                        reason: format!("symlink target is unreadable: {}", err),
                    })),
                }
            } else if metadata.is_file() {
                read_snapshot_file(path).map(OptionalSnapshot::File)
            } else {
                Ok(OptionalSnapshot::Invalid(PathIssue {
                    rel_path,
                    path: path.to_path_buf(),
                    side,
                    reason: "path is not a regular file".to_string(),
                }))
            }
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(OptionalSnapshot::Missing),
        Err(err) => Err(format!("failed to inspect {}: {}", path.display(), err)),
    }
}

fn read_snapshot_file(path: &Path) -> Result<FileSnapshot, String> {
    let bytes =
        fs::read(path).map_err(|err| format!("failed to read file {}: {}", path.display(), err))?;
    Ok(FileSnapshot {
        path: path.to_path_buf(),
        bytes,
    })
}

fn print_item_details(item: &SyncItem) {
    log(&format!("details: {}", display_rel(&item.rel_path)));
    log(&format!(
        "  type: {}",
        match item.kind {
            ItemKind::Config => "config",
            ItemKind::LazyLock => "lazy-lock",
        }
    ));
    log(&format!("  status: {}", item.status.as_str()));
    if let Some(path) = &item.managed_path {
        log(&format!("  managed: {}", path.display()));
    }
    if let Some(path) = &item.actual_path {
        log(&format!("  actual: {}", path.display()));
    }
    log(&format!("  reason: {}", item.reason));
}

fn print_item_diff(item: &SyncItem) -> Result<(), String> {
    log(&format!("diff: {}", display_rel(&item.rel_path)));
    print_unified_diff(
        bytes_to_text(item.desired.as_deref().unwrap_or_default()).as_ref(),
        bytes_to_text(item.actual.as_deref().unwrap_or_default()).as_ref(),
    )
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
    if !output.stdout.is_empty() {
        std::io::stdout()
            .write_all(&output.stdout)
            .map_err(|err| format!("failed to write diff output: {}", err))?;
    }
    if !output.stderr.is_empty() {
        std::io::stderr()
            .write_all(&output.stderr)
            .map_err(|err| format!("failed to write diff error output: {}", err))?;
    }
    Ok(())
}

fn bytes_to_text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ActionStatus {
    Skipped,
    Changed,
}

fn apply_item(
    item: &SyncItem,
    runtime_dir: &Path,
    state_dir: &Path,
    runtime_root_is_symlink: bool,
) -> Result<ActionStatus, String> {
    match item.status {
        ItemStatus::InSync => Ok(ActionStatus::Skipped),
        ItemStatus::Invalid => Err(item.reason.clone()),
        ItemStatus::NeedsApply | ItemStatus::Missing => {
            let desired = item
                .desired
                .as_ref()
                .ok_or_else(|| "managed content is missing".to_string())?;
            let target = actual_write_path(item, runtime_dir, state_dir)?;
            if item.kind == ItemKind::Config && runtime_root_is_symlink {
                return Err(format!(
                    "runtime dir is a symlink; run Home Manager activation or pass a writable --runtime-dir ({})",
                    runtime_dir.display()
                ));
            }
            write_file_atomically(&target, desired)?;
            Ok(ActionStatus::Changed)
        }
        ItemStatus::RuntimeOnly => {
            let target = item
                .actual_path
                .as_ref()
                .ok_or_else(|| "runtime path is missing".to_string())?;
            if item.kind == ItemKind::Config && runtime_root_is_symlink {
                return Err(format!(
                    "runtime dir is a symlink; run Home Manager activation or pass a writable --runtime-dir ({})",
                    runtime_dir.display()
                ));
            }
            fs::remove_file(target).map_err(|err| {
                format!(
                    "failed to remove runtime-only file {}: {}",
                    target.display(),
                    err
                )
            })?;
            Ok(ActionStatus::Changed)
        }
    }
}

fn adopt_item(item: &SyncItem, managed_dir: &Path) -> Result<ActionStatus, String> {
    match item.status {
        ItemStatus::InSync => Ok(ActionStatus::Skipped),
        ItemStatus::Invalid => Err(item.reason.clone()),
        ItemStatus::NeedsApply | ItemStatus::RuntimeOnly => {
            let actual = item
                .actual
                .as_ref()
                .ok_or_else(|| "runtime content is missing".to_string())?;
            let target = managed_dir.join(&item.rel_path);
            write_file_atomically(&target, actual)?;
            Ok(ActionStatus::Changed)
        }
        ItemStatus::Missing => Err(
            "runtime file is missing; adopt is non-destructive, so remove the managed file manually or run --apply".to_string(),
        ),
    }
}

fn actual_write_path(
    item: &SyncItem,
    runtime_dir: &Path,
    state_dir: &Path,
) -> Result<PathBuf, String> {
    match item.kind {
        ItemKind::Config => Ok(runtime_dir.join(&item.rel_path)),
        ItemKind::LazyLock => {
            if let Some(actual_path) = &item.actual_path {
                Ok(actual_path.clone())
            } else {
                Ok(state_dir.join(&item.rel_path))
            }
        }
    }
}

fn write_file_atomically(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("path has no parent: {}", path.display()))?;
    fs::create_dir_all(parent)
        .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
    let mut temp = NamedTempFile::new_in(parent).map_err(|err| {
        format!(
            "failed to create temp file in {}: {}",
            parent.display(),
            err
        )
    })?;
    temp.write_all(bytes)
        .map_err(|err| format!("failed to write temp file for {}: {}", path.display(), err))?;
    temp.persist(path)
        .map_err(|err| format!("failed to replace {}: {}", path.display(), err.error))?;
    Ok(())
}

fn path_is_symlink(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_symlink())
        .unwrap_or(false)
}

fn display_rel(path: &Path) -> String {
    if path == Path::new(".") {
        ".".to_string()
    } else {
        path.display().to_string()
    }
}

fn is_runtime_metadata(rel_path: &Path) -> bool {
    rel_path == Path::new("lazy-lock.json") || rel_path == Path::new("lazyvim.json")
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn write(path: &Path, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }

    fn options(
        managed: &Path,
        runtime: &Path,
        state: &Path,
        mode: NeovimSyncMode,
    ) -> NeovimSyncOptions {
        NeovimSyncOptions {
            managed_dir: Some(managed.to_path_buf()),
            runtime_dir: Some(runtime.to_path_buf()),
            state_dir: Some(state.to_path_buf()),
            mode,
            details: false,
            diff_output: false,
        }
    }

    #[test]
    fn check_detects_state_lock_drift() {
        let temp = TempDir::new().unwrap();
        let managed = temp.path().join("managed");
        let runtime = temp.path().join("runtime");
        let state = temp.path().join("state");
        write(&managed.join("init.lua"), "require('config.lazy')\n");
        write(&runtime.join("init.lua"), "require('config.lazy')\n");
        write(&managed.join("lazy-lock.json"), "{\"a\":\"old\"}\n");
        write(&runtime.join("lazy-lock.json"), "{\"a\":\"ignored\"}\n");
        write(&state.join("lazy-lock.json"), "{\"a\":\"new\"}\n");

        let result = run(options(&managed, &runtime, &state, NeovimSyncMode::Check)).unwrap();

        assert_eq!(result.checked, 2);
        assert_eq!(result.in_sync, 1);
        assert_eq!(result.needs_apply, 1);
        assert_eq!(result.exit_code(NeovimSyncMode::Check), 1);
    }

    #[test]
    fn adopt_copies_effective_state_lock_to_managed() {
        let temp = TempDir::new().unwrap();
        let managed = temp.path().join("managed");
        let runtime = temp.path().join("runtime");
        let state = temp.path().join("state");
        write(&managed.join("init.lua"), "old\n");
        write(&runtime.join("init.lua"), "new\n");
        write(&managed.join("lazy-lock.json"), "{\"a\":\"old\"}\n");
        write(&state.join("lazy-lock.json"), "{\"a\":\"new\"}\n");

        let result = run(options(&managed, &runtime, &state, NeovimSyncMode::Adopt)).unwrap();

        assert_eq!(result.adopted, 2);
        assert_eq!(
            fs::read_to_string(managed.join("init.lua")).unwrap(),
            "new\n"
        );
        assert_eq!(
            fs::read_to_string(managed.join("lazy-lock.json")).unwrap(),
            "{\"a\":\"new\"}\n"
        );
    }

    #[test]
    fn apply_writes_missing_lock_to_state_dir() {
        let temp = TempDir::new().unwrap();
        let managed = temp.path().join("managed");
        let runtime = temp.path().join("runtime");
        let state = temp.path().join("state");
        write(&managed.join("init.lua"), "same\n");
        write(&runtime.join("init.lua"), "same\n");
        write(&managed.join("lazy-lock.json"), "{\"a\":\"managed\"}\n");

        let result = run(options(&managed, &runtime, &state, NeovimSyncMode::Apply)).unwrap();

        assert_eq!(result.applied, 1);
        assert_eq!(
            fs::read_to_string(state.join("lazy-lock.json")).unwrap(),
            "{\"a\":\"managed\"}\n"
        );
    }

    #[test]
    fn check_detects_runtime_only_file() {
        let temp = TempDir::new().unwrap();
        let managed = temp.path().join("managed");
        let runtime = temp.path().join("runtime");
        let state = temp.path().join("state");
        write(&managed.join("init.lua"), "same\n");
        write(&runtime.join("init.lua"), "same\n");
        write(&runtime.join("lua/local.lua"), "runtime only\n");
        write(&managed.join("lazy-lock.json"), "{}\n");
        write(&state.join("lazy-lock.json"), "{}\n");

        let result = run(options(&managed, &runtime, &state, NeovimSyncMode::Check)).unwrap();

        assert_eq!(result.runtime_only, 1);
        assert_eq!(result.exit_code(NeovimSyncMode::Check), 1);
    }

    #[test]
    fn check_ignores_lazyvim_runtime_metadata() {
        let temp = TempDir::new().unwrap();
        let managed = temp.path().join("managed");
        let runtime = temp.path().join("runtime");
        let state = temp.path().join("state");
        write(&managed.join("init.lua"), "same\n");
        write(&runtime.join("init.lua"), "same\n");
        write(&runtime.join("lazyvim.json"), "{}\n");
        write(&managed.join("lazy-lock.json"), "{}\n");
        write(&state.join("lazy-lock.json"), "{}\n");

        let result = run(options(&managed, &runtime, &state, NeovimSyncMode::Check)).unwrap();

        assert_eq!(result.checked, 2);
        assert_eq!(result.runtime_only, 0);
        assert_eq!(result.exit_code(NeovimSyncMode::Check), 0);
    }
}
