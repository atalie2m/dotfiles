use crate::commands::GcArgs;
use dotfiles_core::support::{
    exit_with_status, home_dir, log, repo_root, run_command_status, sudo_preserve_env_vars,
};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Clone, Debug, Eq, PartialEq)]
struct RepoGcRoot {
    path: PathBuf,
    target: PathBuf,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ProfileHistory {
    label: &'static str,
    path: PathBuf,
    needs_sudo: bool,
}

pub(crate) fn command_gc(args: &GcArgs) -> Result<(), String> {
    let root = repo_root()?;
    let repo_roots = collect_repo_gc_roots(&root)?;
    let profiles = if args.store_only {
        Vec::new()
    } else {
        collect_profile_histories()?
    };

    log(&format!("repo root: {}", root.display()));
    if repo_roots.is_empty() {
        log("repo GC roots: no result symlinks found");
    } else {
        for repo_root in &repo_roots {
            if args.apply {
                fs::remove_file(&repo_root.path).map_err(|err| {
                    format!(
                        "failed to remove repo GC root {}: {}",
                        repo_root.path.display(),
                        err
                    )
                })?;
                log(&format!(
                    "removed repo GC root: {} -> {}",
                    repo_root.path.display(),
                    repo_root.target.display()
                ));
            } else {
                log(&format!(
                    "would remove repo GC root: {} -> {}",
                    repo_root.path.display(),
                    repo_root.target.display()
                ));
            }
        }
    }

    if args.apply {
        wipe_profile_histories(args, &profiles, false)?;
        run_collection()?;
        if args.optimise {
            run_optimise()?;
        }
    } else {
        log("dry-run: run with --apply to remove repo GC roots and collect store garbage");
        wipe_profile_histories(args, &profiles, true)?;
        run_store_gc_dry_run()?;
    }

    Ok(())
}

fn collect_repo_gc_roots(root: &Path) -> Result<Vec<RepoGcRoot>, String> {
    let mut roots = Vec::new();
    collect_repo_gc_roots_from_dir(root, &mut roots)?;
    roots.sort_by(|left, right| left.path.cmp(&right.path));
    Ok(roots)
}

fn collect_repo_gc_roots_from_dir(dir: &Path, roots: &mut Vec<RepoGcRoot>) -> Result<(), String> {
    for entry in
        fs::read_dir(dir).map_err(|err| format!("failed to read {}: {}", dir.display(), err))?
    {
        let entry = entry.map_err(|err| format!("failed to read {}: {}", dir.display(), err))?;
        let path = entry.path();
        let file_name = entry.file_name();
        if file_name == ".git" {
            continue;
        }

        let metadata = fs::symlink_metadata(&path)
            .map_err(|err| format!("failed to inspect {}: {}", path.display(), err))?;
        let file_type = metadata.file_type();
        if file_type.is_dir() {
            collect_repo_gc_roots_from_dir(&path, roots)?;
            continue;
        }

        if !file_type.is_symlink() {
            continue;
        }

        let target = fs::read_link(&path)
            .map_err(|err| format!("failed to read {}: {}", path.display(), err))?;
        if is_repo_gc_root_link(&path, &target) {
            roots.push(RepoGcRoot { path, target });
        }
    }

    Ok(())
}

fn is_repo_gc_root_link(path: &Path, target: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };

    (name == "result" || name.starts_with("result-")) && target.starts_with("/nix/store")
}

fn collect_profile_histories() -> Result<Vec<ProfileHistory>, String> {
    let home = home_dir()?;
    let candidates = vec![
        ProfileHistory {
            label: "system",
            path: PathBuf::from("/nix/var/nix/profiles/system"),
            needs_sudo: true,
        },
        ProfileHistory {
            label: "user",
            path: home.join(".local/state/nix/profiles/profile"),
            needs_sudo: false,
        },
        ProfileHistory {
            label: "home-manager",
            path: home.join(".local/state/nix/profiles/home-manager"),
            needs_sudo: false,
        },
        ProfileHistory {
            label: "root",
            path: PathBuf::from("/nix/var/nix/profiles/per-user/root/profile"),
            needs_sudo: true,
        },
    ];

    Ok(candidates
        .into_iter()
        .filter(|profile| profile.path.exists())
        .collect())
}

fn wipe_profile_histories(
    args: &GcArgs,
    profiles: &[ProfileHistory],
    dry_run: bool,
) -> Result<(), String> {
    if profiles.is_empty() {
        log("profile history: skipped");
        return Ok(());
    }

    for profile in profiles {
        if dry_run && profile.needs_sudo {
            log(&format!(
                "would wipe non-current {} profile generations with sudo: {}",
                profile.label,
                profile.path.display()
            ));
            continue;
        }

        let mut command = profile_wipe_command(args, profile, dry_run);
        let status = run_command_status(&mut command)?;
        if status.success() {
            continue;
        }

        exit_with_status(status);
    }

    Ok(())
}

fn profile_wipe_command(args: &GcArgs, profile: &ProfileHistory, dry_run: bool) -> Command {
    let mut command = command_with_optional_sudo("nix", profile.needs_sudo);
    command.arg("profile");
    command.arg("wipe-history");
    command.arg("--profile");
    command.arg(&profile.path);
    if let Some(age) = args.delete_older_than.as_deref() {
        command.arg("--older-than");
        command.arg(age);
    }
    if dry_run {
        command.arg("--dry-run");
    }
    command
}

fn run_collection() -> Result<(), String> {
    let mut command = collection_command(false);
    let status = run_command_status(&mut command)?;
    if status.success() {
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn run_store_gc_dry_run() -> Result<(), String> {
    let mut command = collection_command(true);
    let status = run_command_status(&mut command)?;
    if status.success() {
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn run_optimise() -> Result<(), String> {
    let mut command = nix_command();
    command.arg("store");
    command.arg("optimise");

    let status = run_command_status(&mut command)?;
    if status.success() {
        Ok(())
    } else {
        exit_with_status(status)
    }
}

fn collection_command(dry_run: bool) -> Command {
    let mut command = nix_command();
    command.arg("store");
    command.arg("gc");
    if dry_run {
        command.arg("--dry-run");
    }
    command
}

fn nix_command() -> Command {
    command_with_optional_sudo("nix", false)
}

fn command_with_optional_sudo(program: &str, use_sudo: bool) -> Command {
    if !use_sudo {
        return Command::new(program);
    }

    let mut command = Command::new("sudo");
    command.arg("-n");
    command.arg(format!("--preserve-env={}", sudo_preserve_env_vars()));
    command.arg(program);
    command
}

#[cfg(test)]
mod tests {
    use super::{
        collect_repo_gc_roots, is_repo_gc_root_link, profile_wipe_command, ProfileHistory,
    };
    use crate::commands::GcArgs;
    use std::fs;
    use std::os::unix::fs::symlink;
    use std::path::Path;

    #[test]
    fn repo_gc_roots_are_result_symlinks_to_the_nix_store() {
        assert!(is_repo_gc_root_link(
            Path::new("/repo/result"),
            Path::new("/nix/store/hash-package")
        ));
        assert!(is_repo_gc_root_link(
            Path::new("/repo/result-build"),
            Path::new("/nix/store/hash-package")
        ));
        assert!(!is_repo_gc_root_link(
            Path::new("/repo/not-result"),
            Path::new("/nix/store/hash-package")
        ));
        assert!(!is_repo_gc_root_link(
            Path::new("/repo/result"),
            Path::new("/tmp/hash-package")
        ));
    }

    #[test]
    fn collect_repo_gc_roots_scans_repo_but_skips_git_dir() {
        let temp = tempfile::tempdir().expect("tempdir");
        let root = temp.path();
        fs::create_dir(root.join("nested")).expect("nested");
        fs::create_dir(root.join(".git")).expect("git");

        symlink(
            "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-root",
            root.join("result"),
        )
        .expect("result");
        symlink(
            "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-root",
            root.join("nested/result-build"),
        )
        .expect("nested result");
        symlink("/tmp/not-store", root.join("result-local")).expect("local result");
        symlink(
            "/nix/store/cccccccccccccccccccccccccccccccc-root",
            root.join(".git/result"),
        )
        .expect("git result");

        let roots = collect_repo_gc_roots(root).expect("collect");
        let paths = roots
            .iter()
            .map(|entry| entry.path.strip_prefix(root).unwrap().to_path_buf())
            .collect::<Vec<_>>();

        assert_eq!(
            paths,
            vec![Path::new("nested/result-build"), Path::new("result")]
        );
    }

    #[test]
    fn profile_wipe_command_defaults_to_all_non_current_generations() {
        let args = GcArgs {
            apply: true,
            delete_older_than: None,
            store_only: false,
            optimise: false,
        };
        let profile = ProfileHistory {
            label: "user",
            path: Path::new("/tmp/profile").to_path_buf(),
            needs_sudo: false,
        };

        let command = profile_wipe_command(&args, &profile, false);
        let argv = command
            .get_args()
            .map(|arg| arg.to_string_lossy().to_string())
            .collect::<Vec<_>>();

        assert_eq!(
            argv,
            vec!["profile", "wipe-history", "--profile", "/tmp/profile"]
        );
    }

    #[test]
    fn profile_wipe_command_can_keep_recent_generations() {
        let args = GcArgs {
            apply: true,
            delete_older_than: Some("7d".to_string()),
            store_only: false,
            optimise: false,
        };
        let profile = ProfileHistory {
            label: "user",
            path: Path::new("/tmp/profile").to_path_buf(),
            needs_sudo: false,
        };

        let command = profile_wipe_command(&args, &profile, true);
        let argv = command
            .get_args()
            .map(|arg| arg.to_string_lossy().to_string())
            .collect::<Vec<_>>();

        assert_eq!(
            argv,
            vec![
                "profile",
                "wipe-history",
                "--profile",
                "/tmp/profile",
                "--older-than",
                "7d",
                "--dry-run"
            ]
        );
    }
}
