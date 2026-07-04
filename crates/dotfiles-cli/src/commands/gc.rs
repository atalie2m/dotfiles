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

#[derive(Clone, Debug, Eq, PartialEq)]
struct LegacyHomeManagerProfile {
    profile_link: PathBuf,
    generation_link: PathBuf,
    legacy_target: PathBuf,
    current_target: PathBuf,
}

pub(crate) fn command_gc(args: &GcArgs) -> Result<(), String> {
    let root = repo_root()?;
    let repo_roots = collect_repo_gc_roots(&root)?;
    let legacy_home_manager_profile = if args.store_only {
        None
    } else {
        collect_legacy_home_manager_profile()?
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

    let profiles = if args.store_only {
        Vec::new()
    } else {
        collect_profile_histories()?
    };

    if args.apply {
        wipe_profile_histories(args, &profiles, false)?;
        if !args.store_only {
            handle_legacy_home_manager_profile(&legacy_home_manager_profile, true)?;
        }
        run_collection()?;
        if args.optimise {
            run_optimise()?;
        }
    } else {
        if !args.store_only {
            handle_legacy_home_manager_profile(&legacy_home_manager_profile, false)?;
        }
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

fn collect_legacy_home_manager_profile() -> Result<Option<LegacyHomeManagerProfile>, String> {
    collect_legacy_home_manager_profile_for_home(&home_dir()?)
}

fn collect_legacy_home_manager_profile_for_home(
    home: &Path,
) -> Result<Option<LegacyHomeManagerProfile>, String> {
    let current_link = home.join(".local/state/home-manager/gcroots/current-home");
    let profile_link = home.join(".local/state/nix/profiles/home-manager");

    let Some(current_target) = read_optional_link(&current_link)? else {
        return Ok(None);
    };
    let Some(legacy_profile_target) = read_optional_link(&profile_link)? else {
        return Ok(None);
    };

    if !current_target.starts_with("/nix/store") {
        return Ok(None);
    }

    let Some(profile_dir) = profile_link.parent() else {
        return Ok(None);
    };
    let generation_link = resolve_link_target(profile_dir, &legacy_profile_target);
    if !is_home_manager_generation_link(profile_dir, &generation_link) {
        return Ok(None);
    }

    let Some(legacy_target) = read_optional_link(&generation_link)? else {
        return Ok(None);
    };
    if !legacy_target.starts_with("/nix/store") {
        return Ok(None);
    }
    if legacy_target == current_target {
        return Ok(None);
    }

    Ok(Some(LegacyHomeManagerProfile {
        profile_link,
        generation_link,
        legacy_target,
        current_target,
    }))
}

fn read_optional_link(path: &Path) -> Result<Option<PathBuf>, String> {
    match fs::read_link(path) {
        Ok(target) => Ok(Some(target)),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(format!("failed to read {}: {}", path.display(), err)),
    }
}

fn resolve_link_target(base: &Path, target: &Path) -> PathBuf {
    if target.is_absolute() {
        target.to_path_buf()
    } else {
        base.join(target)
    }
}

fn is_home_manager_generation_link(profile_dir: &Path, path: &Path) -> bool {
    if path.parent() != Some(profile_dir) {
        return false;
    }

    let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };

    let Some(generation) = name
        .strip_prefix("home-manager-")
        .and_then(|value| value.strip_suffix("-link"))
    else {
        return false;
    };

    !generation.is_empty() && generation.chars().all(|value| value.is_ascii_digit())
}

fn handle_legacy_home_manager_profile(
    legacy_profile: &Option<LegacyHomeManagerProfile>,
    apply: bool,
) -> Result<(), String> {
    let Some(legacy_profile) = legacy_profile else {
        log("legacy Home Manager profile: no stale profile found");
        return Ok(());
    };

    if apply {
        remove_legacy_home_manager_link(
            &legacy_profile.profile_link,
            &legacy_profile.generation_link,
        )?;
        remove_legacy_home_manager_link(
            &legacy_profile.generation_link,
            &legacy_profile.legacy_target,
        )?;
    } else {
        log(&format!(
            "would remove legacy Home Manager profile: {} -> {}",
            legacy_profile.profile_link.display(),
            legacy_profile.generation_link.display()
        ));
        log(&format!(
            "would remove legacy Home Manager generation: {} -> {}",
            legacy_profile.generation_link.display(),
            legacy_profile.legacy_target.display()
        ));
        log(&format!(
            "current Home Manager generation is kept: {}",
            legacy_profile.current_target.display()
        ));
    }

    Ok(())
}

fn remove_legacy_home_manager_link(path: &Path, target: &Path) -> Result<(), String> {
    fs::remove_file(path).map_err(|err| {
        format!(
            "failed to remove legacy Home Manager link {}: {}",
            path.display(),
            err
        )
    })?;
    log(&format!(
        "removed legacy Home Manager link: {} -> {}",
        path.display(),
        target.display()
    ));
    Ok(())
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
    command.arg("-H");
    command.arg("-n");
    command.arg(format!("--preserve-env={}", sudo_preserve_env_vars()));
    command.arg(program);
    command
}

#[cfg(test)]
mod tests {
    use super::{
        collect_legacy_home_manager_profile_for_home, collect_repo_gc_roots,
        is_home_manager_generation_link, is_repo_gc_root_link, profile_wipe_command,
        LegacyHomeManagerProfile, ProfileHistory,
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
    fn home_manager_generation_links_must_be_numbered_links_in_the_profile_dir() {
        let dir = Path::new("/home/user/.local/state/nix/profiles");

        assert!(is_home_manager_generation_link(
            dir,
            Path::new("/home/user/.local/state/nix/profiles/home-manager-348-link")
        ));
        assert!(!is_home_manager_generation_link(
            dir,
            Path::new("/home/user/.local/state/nix/profiles/profile-348-link")
        ));
        assert!(!is_home_manager_generation_link(
            dir,
            Path::new("/home/user/.local/state/nix/profiles/home-manager-current-link")
        ));
        assert!(!is_home_manager_generation_link(
            dir,
            Path::new("/home/user/elsewhere/home-manager-348-link")
        ));
    }

    #[test]
    fn collect_legacy_home_manager_profile_finds_stale_current_profile() {
        let temp = tempfile::tempdir().expect("tempdir");
        let home = temp.path();
        let gcroots = home.join(".local/state/home-manager/gcroots");
        let profiles = home.join(".local/state/nix/profiles");
        fs::create_dir_all(&gcroots).expect("gcroots");
        fs::create_dir_all(&profiles).expect("profiles");

        let current_target =
            Path::new("/nix/store/currentcurrentcurrentcurrentcurrent-home-manager-generation");
        let legacy_target =
            Path::new("/nix/store/legacylegacylegacylegacylegacy-home-manager-generation");
        let profile_link = profiles.join("home-manager");
        let generation_link = profiles.join("home-manager-348-link");
        symlink(current_target, gcroots.join("current-home")).expect("current-home");
        symlink("home-manager-348-link", &profile_link).expect("profile");
        symlink(legacy_target, &generation_link).expect("generation");

        assert_eq!(
            collect_legacy_home_manager_profile_for_home(home).expect("collect"),
            Some(LegacyHomeManagerProfile {
                profile_link,
                generation_link,
                legacy_target: legacy_target.to_path_buf(),
                current_target: current_target.to_path_buf(),
            })
        );
    }

    #[test]
    fn collect_legacy_home_manager_profile_skips_current_profile() {
        let temp = tempfile::tempdir().expect("tempdir");
        let home = temp.path();
        let gcroots = home.join(".local/state/home-manager/gcroots");
        let profiles = home.join(".local/state/nix/profiles");
        fs::create_dir_all(&gcroots).expect("gcroots");
        fs::create_dir_all(&profiles).expect("profiles");

        let current_target =
            Path::new("/nix/store/currentcurrentcurrentcurrentcurrent-home-manager-generation");
        symlink(current_target, gcroots.join("current-home")).expect("current-home");
        symlink("home-manager-348-link", profiles.join("home-manager")).expect("profile");
        symlink(current_target, profiles.join("home-manager-348-link")).expect("generation");

        assert_eq!(
            collect_legacy_home_manager_profile_for_home(home).expect("collect"),
            None
        );
    }

    #[test]
    fn collect_legacy_home_manager_profile_skips_unexpected_profile_links() {
        let temp = tempfile::tempdir().expect("tempdir");
        let home = temp.path();
        let gcroots = home.join(".local/state/home-manager/gcroots");
        let profiles = home.join(".local/state/nix/profiles");
        fs::create_dir_all(&gcroots).expect("gcroots");
        fs::create_dir_all(&profiles).expect("profiles");

        symlink(
            "/nix/store/currentcurrentcurrentcurrentcurrent-home-manager-generation",
            gcroots.join("current-home"),
        )
        .expect("current-home");
        symlink("profile-348-link", profiles.join("home-manager")).expect("profile");
        symlink(
            "/nix/store/legacylegacylegacylegacylegacy-home-manager-generation",
            profiles.join("profile-348-link"),
        )
        .expect("generation");

        assert_eq!(
            collect_legacy_home_manager_profile_for_home(home).expect("collect"),
            None
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

    #[test]
    fn profile_wipe_command_uses_root_home_for_sudo_profiles() {
        let args = GcArgs {
            apply: true,
            delete_older_than: None,
            store_only: false,
            optimise: false,
        };
        let profile = ProfileHistory {
            label: "system",
            path: Path::new("/nix/var/nix/profiles/system").to_path_buf(),
            needs_sudo: true,
        };

        let command = profile_wipe_command(&args, &profile, false);
        let argv = command
            .get_args()
            .map(|arg| arg.to_string_lossy().to_string())
            .collect::<Vec<_>>();

        assert_eq!(command.get_program().to_string_lossy(), "sudo");
        assert_eq!(argv[0], "-H");
        assert_eq!(argv[1], "-n");
        assert!(argv[2].starts_with("--preserve-env="));
        assert_eq!(
            &argv[3..],
            [
                "nix",
                "profile",
                "wipe-history",
                "--profile",
                "/nix/var/nix/profiles/system"
            ]
        );
    }
}
