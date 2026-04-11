use crate::commands::{ExportCleanArgs, ExportFormat};
use dotfiles_core::support::{exit_with_status, git_tracked_files, repo_root, run_command_status};
use std::fs;
use std::process::Command;

pub(crate) fn command_export_clean(args: &ExportCleanArgs) -> Result<(), String> {
    let output = &args.output;
    let root = repo_root()?;
    if output.exists() {
        return Err(format!("output already exists: {}", output.display()));
    }
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
    }

    let temp = tempfile::tempdir().map_err(|err| format!("failed to create temp dir: {}", err))?;
    let export_root = temp.path().join("export");
    fs::create_dir_all(&export_root)
        .map_err(|err| format!("failed to create {}: {}", export_root.display(), err))?;

    let mut git_rev_parse = Command::new("git");
    git_rev_parse.current_dir(&root);
    git_rev_parse.arg("rev-parse");
    git_rev_parse.arg("--show-toplevel");
    let git_status = run_command_status(&mut git_rev_parse)?;
    if !git_status.success() {
        return Err(
            "export-clean requires a trusted Git worktree with a working git binary".to_string(),
        );
    }

    for relative in git_tracked_files(&root)? {
        let src = root.join(&relative);
        let dest = export_root.join(&relative);
        if !src.exists() && fs::symlink_metadata(&src).is_err() {
            return Err(format!(
                "tracked path is missing from the working tree: {}",
                relative.display()
            ));
        }
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)
                .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
        }
        fs::copy(&src, &dest)
            .map_err(|err| format!("failed to copy {}: {}", relative.display(), err))?;
    }

    match args.format {
        ExportFormat::Dir => {
            fs::rename(&export_root, output)
                .map_err(|err| format!("failed to move export dir: {}", err))?;
        }
        ExportFormat::Tar => {
            let mut tar = Command::new("tar");
            tar.env("COPYFILE_DISABLE", "1");
            tar.arg("-C");
            tar.arg(&export_root);
            tar.arg("-cf");
            tar.arg(output);
            tar.arg(".");
            let status = run_command_status(&mut tar)?;
            if !status.success() {
                exit_with_status(status);
            }
        }
    }

    Ok(())
}
