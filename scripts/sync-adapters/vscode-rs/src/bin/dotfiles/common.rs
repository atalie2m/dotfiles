use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{self, Command, ExitStatus};

pub(crate) const SCRIPT_LABEL: &str = "dotfiles";

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct InputRefs {
    pub(crate) facts_dir: Option<PathBuf>,
    pub(crate) secrets_dir: Option<PathBuf>,
    pub(crate) facts_ref: String,
    pub(crate) secrets_ref: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct ParsedTargetArgs {
    pub(crate) host: Option<String>,
    pub(crate) rice: Option<String>,
    pub(crate) passthrough: Vec<String>,
    pub(crate) args: Vec<String>,
    pub(crate) has_passthrough: bool,
}

pub(crate) fn log(message: &str) {
    eprintln!("{}: {}", SCRIPT_LABEL, message);
}

pub(crate) fn die(message: &str) -> ! {
    log(message);
    process::exit(1);
}

pub(crate) fn exit_with_status(status: ExitStatus) -> ! {
    process::exit(status.code().unwrap_or(1));
}

pub(crate) fn path_ref_to_dir(reference: &str) -> Option<PathBuf> {
    reference
        .strip_prefix("path:")
        .map(PathBuf::from)
}

pub(crate) fn resolve_inputs() -> Result<InputRefs, String> {
    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    resolve_inputs_from(
        Path::new(&home),
        env::var("FACTS_DIR").ok(),
        env::var("SECRETS_DIR").ok(),
        env::var("FACTS").ok(),
        env::var("SECRETS").ok(),
    )
}

pub(crate) fn resolve_inputs_from(
    home_dir: &Path,
    facts_dir_env: Option<String>,
    secrets_dir_env: Option<String>,
    facts_ref_env: Option<String>,
    secrets_ref_env: Option<String>,
) -> Result<InputRefs, String> {
    let default_inputs_dir = home_dir.join(".config/dotfiles");

    let mut facts_dir = facts_dir_env.map(PathBuf::from);
    let mut secrets_dir = secrets_dir_env.map(PathBuf::from);
    let facts_ref = if let Some(reference) = facts_ref_env {
        if facts_dir.is_none() {
            facts_dir = path_ref_to_dir(&reference);
        }
        reference
    } else {
        let dir = facts_dir
            .clone()
            .unwrap_or_else(|| default_inputs_dir.clone());
        facts_dir = Some(dir.clone());
        format!("path:{}", dir.display())
    };
    let secrets_ref = if let Some(reference) = secrets_ref_env {
        if secrets_dir.is_none() {
            secrets_dir = path_ref_to_dir(&reference);
        }
        reference
    } else {
        let dir = secrets_dir
            .clone()
            .unwrap_or_else(|| default_inputs_dir.clone());
        secrets_dir = Some(dir.clone());
        format!("path:{}", dir.display())
    };

    if let (Some(dir), Some(path_ref_dir)) = (facts_dir.clone(), path_ref_to_dir(&facts_ref)) {
        if path_ref_dir != dir {
            return Err(format!(
                "FACTS_DIR ({}) does not match FACTS ({})",
                dir.display(),
                facts_ref
            ));
        }
    }

    if let (Some(dir), Some(path_ref_dir)) = (secrets_dir.clone(), path_ref_to_dir(&secrets_ref)) {
        if path_ref_dir != dir {
            return Err(format!(
                "SECRETS_DIR ({}) does not match SECRETS ({})",
                dir.display(),
                secrets_ref
            ));
        }
    }

    Ok(InputRefs {
        facts_dir,
        secrets_dir,
        facts_ref,
        secrets_ref,
    })
}

pub(crate) fn require_input_directories(
    inputs: &InputRefs,
    command_name: &str,
) -> Result<(PathBuf, PathBuf), String> {
    let facts_dir = inputs.facts_dir.clone().ok_or_else(|| {
        format!(
            "FACTS_DIR is required when FACTS is not a path:... input ({} needs filesystem access)",
            command_name
        )
    })?;
    let secrets_dir = inputs.secrets_dir.clone().ok_or_else(|| {
        format!(
            "SECRETS_DIR is required when SECRETS is not a path:... input ({} needs filesystem access)",
            command_name
        )
    })?;
    Ok((facts_dir, secrets_dir))
}

pub(crate) fn ensure_inputs_dirs(facts_dir: &Path, secrets_dir: &Path) -> Result<(), String> {
    if !facts_dir.is_dir() {
        fs::create_dir_all(facts_dir)
            .map_err(|err| format!("failed to create {}: {}", facts_dir.display(), err))?;
        log(&format!("created {}", facts_dir.display()));
    }
    fs::set_permissions(facts_dir, fs::Permissions::from_mode(0o700))
        .map_err(|err| format!("failed to chmod {}: {}", facts_dir.display(), err))?;

    if !secrets_dir.is_dir() {
        fs::create_dir_all(secrets_dir)
            .map_err(|err| format!("failed to create {}: {}", secrets_dir.display(), err))?;
        log(&format!("created {}", secrets_dir.display()));
    }
    fs::set_permissions(secrets_dir, fs::Permissions::from_mode(0o700))
        .map_err(|err| format!("failed to chmod {}: {}", secrets_dir.display(), err))?;

    Ok(())
}

pub(crate) fn repo_root() -> Result<PathBuf, String> {
    if let Ok(root) = env::var("DOTFILES_ROOT") {
        let path = PathBuf::from(&root);
        if !path.is_dir() {
            return Err(format!("DOTFILES_ROOT is not a readable directory: {}", root));
        }
        if !path.join("flake.nix").is_file() {
            return Err(format!(
                "unable to resolve flake root (expected flake.nix under {})",
                path.display()
            ));
        }
        return Ok(path);
    }

    let cwd = env::current_dir().map_err(|err| format!("failed to resolve cwd: {}", err))?;
    if cwd.join("flake.nix").is_file() {
        return Ok(cwd);
    }

    let exe = env::current_exe().map_err(|err| format!("failed to resolve executable path: {}", err))?;
    let fallback = exe
        .ancestors()
        .nth(4)
        .ok_or_else(|| "unable to resolve flake root from executable".to_string())?;
    if fallback.join("flake.nix").is_file() {
        return Ok(fallback.to_path_buf());
    }

    Err(format!(
        "unable to resolve flake root (expected flake.nix under {})",
        cwd.display()
    ))
}

pub(crate) fn flake_ref_for_root(root: &Path) -> String {
    format!("path:{}", root.display())
}

pub(crate) fn nix_args_with_inputs(inputs: &InputRefs) -> Vec<OsString> {
    vec![
        OsString::from("--no-update-lock-file"),
        OsString::from("--override-input"),
        OsString::from("local"),
        OsString::from(inputs.facts_ref.clone()),
        OsString::from("--override-input"),
        OsString::from("secrets"),
        OsString::from(inputs.secrets_ref.clone()),
    ]
}

pub(crate) fn list_darwin_targets(root: &Path, inputs: &InputRefs) -> Result<Vec<String>, String> {
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg("--raw");
    command.arg(format!("{}#darwinConfigurations", flake_ref_for_root(root)));
    command.arg("--apply");
    command.arg(r#"x: builtins.concatStringsSep "\n" (builtins.attrNames x)"#);
    command.args(nix_args_with_inputs(inputs));

    let output = command
        .output()
        .map_err(|err| format!("failed to run nix eval: {}", err))?;
    if !output.status.success() {
        return Err("unable to evaluate darwinConfigurations".to_string());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect())
}

pub(crate) fn resolve_target(
    root: &Path,
    inputs: &InputRefs,
    host: &str,
    rice: Option<&str>,
) -> Result<String, String> {
    if host.is_empty() {
        return Err("host is required".to_string());
    }

    let targets = list_darwin_targets(root, inputs)?;
    if targets.is_empty() {
        return Err("no darwinConfigurations found".to_string());
    }

    if let Some(rice_name) = rice {
        let candidate = format!("{}-{}", host, rice_name);
        if targets.iter().any(|target| target == &candidate) {
            return Ok(candidate);
        }
    } else if targets.iter().any(|target| target == host) {
        return Ok(host.to_string());
    }

    Err(format!(
        "target not found for host '{}'{}",
        host,
        rice.map(|value| format!(" and rice '{}'", value)).unwrap_or_default()
    ))
}

pub(crate) fn explain_darwin_targets_error(inputs: &InputRefs, message: &str) -> String {
    if message != "no darwinConfigurations found" && message != "unable to evaluate darwinConfigurations" {
        return message.to_string();
    }

    let mut lines = vec![format!(
        "{} (check local/secrets inputs and STUB)",
        message
    )];
    lines.push(format!("facts input: {}", inputs.facts_ref));
    lines.push(format!("secrets input: {}", inputs.secrets_ref));

    if let Some(facts_dir) = &inputs.facts_dir {
        let stub = facts_dir.join("STUB");
        if stub.is_file() {
            lines.push(format!(
                "facts STUB present: {} (flake outputs are gated while it exists)",
                stub.display()
            ));
        }
    }

    lines.join("\n")
}

pub(crate) fn parse_target_args(
    args: &[String],
    value_options: &[&str],
) -> Result<ParsedTargetArgs, String> {
    let mut parsed = ParsedTargetArgs::default();
    let mut index = 0usize;

    while index < args.len() {
        let arg = &args[index];
        match arg.as_str() {
            "--host" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --host".to_string())?;
                parsed.host = Some(value.clone());
                index += 2;
            }
            "--rice" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "missing value for --rice".to_string())?;
                parsed.rice = Some(value.clone());
                index += 2;
            }
            "--" => {
                parsed.has_passthrough = true;
                parsed.passthrough = args[index + 1..].to_vec();
                break;
            }
            _ if arg.starts_with("--") => {
                if value_options.iter().any(|option| option == &arg.as_str()) {
                    let value = args
                        .get(index + 1)
                        .ok_or_else(|| format!("missing value for {}", arg))?;
                    parsed.args.push(arg.clone());
                    parsed.args.push(value.clone());
                    index += 2;
                } else {
                    parsed.args.push(arg.clone());
                    index += 1;
                }
            }
            _ => {
                if parsed.host.is_none() {
                    parsed.host = Some(arg.clone());
                } else {
                    parsed.args.push(arg.clone());
                }
                index += 1;
            }
        }
    }

    Ok(parsed)
}

pub(crate) fn require_host_argument(host: Option<&str>, command_name: &str) -> Result<String, String> {
    host.filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            format!(
                "host is required for {} (pass --host <host>, a positional host, or HOST=...)",
                command_name
            )
        })
}

pub(crate) fn resolve_pinned_darwin_rebuild_bin(flake_ref: &str) -> Result<String, String> {
    if let Ok(bin) = env::var("DARWIN_REBUILD_BIN") {
        if !bin.is_empty() {
            return Ok(bin);
        }
    }

    let output = Command::new("nix")
        .arg("build")
        .arg("--no-link")
        .arg("--print-out-paths")
        .arg(format!("{}#darwin-rebuild", flake_ref))
        .output()
        .map_err(|err| format!("failed to build pinned darwin-rebuild: {}", err))?;

    if !output.status.success() {
        return Err("failed to resolve pinned darwin-rebuild".to_string());
    }

    let out_path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let bin = format!("{}/bin/darwin-rebuild", out_path);
    if !Path::new(&bin).is_file() {
        return Err(format!("pinned darwin-rebuild not found at {}", bin));
    }
    Ok(bin)
}

pub(crate) fn list_updateable_root_flake_inputs(root: &Path) -> Result<Vec<String>, String> {
    let expr = r#"
      let
        lock = builtins.fromJSON (builtins.readFile ./flake.lock);
        rootInputs = lock.nodes.root.inputs or { };
        isUpdateable = name:
          let
            nodeName = rootInputs.${name};
            node = lock.nodes.${nodeName} or { };
            locked = node.locked or { };
            inputType = locked.type or "";
          in
          inputType != "" && inputType != "path";
        names = builtins.filter isUpdateable (builtins.attrNames rootInputs);
      in
      builtins.concatStringsSep "\n" names
    "#;

    let output = Command::new("nix")
        .current_dir(root)
        .arg("eval")
        .arg("--raw")
        .arg("--impure")
        .arg("--expr")
        .arg(expr)
        .output()
        .map_err(|err| format!("failed to list flake inputs: {}", err))?;

    if !output.status.success() {
        return Err("unable to determine updateable flake inputs".to_string());
    }

    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect())
}

pub(crate) fn require_writable_checkout(root: &Path, start_dir: &Path) -> Result<PathBuf, String> {
    let mut resolved = root.to_path_buf();
    if resolved.starts_with("/nix/store") {
        if start_dir.join("flake.nix").is_file()
            && start_dir.join("flake.lock").is_file()
            && is_writable(&start_dir.join("flake.nix"))
            && is_writable(&start_dir.join("flake.lock"))
        {
            log(&format!(
                "resolved store root for CLI; using writable checkout at {} for update",
                start_dir.display()
            ));
            resolved = start_dir.to_path_buf();
        }
    }

    if !resolved.join("flake.lock").is_file() {
        return Err(format!(
            "flake.lock not found under {} (update requires a writable checkout)",
            resolved.display()
        ));
    }
    if !is_writable(&resolved.join("flake.nix")) || !is_writable(&resolved.join("flake.lock")) {
        return Err(format!(
            "update requires a writable flake checkout (current root: {})",
            resolved.display()
        ));
    }
    Ok(resolved)
}

fn is_writable(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| !metadata.permissions().readonly())
        .unwrap_or(false)
}

pub(crate) fn render_bootstrap_facts(root: &Path, username: &str) -> Result<String, String> {
    let template = root.join("nix/scripts/bootstrap/facts-template.nix");
    let expr = format!(
        "let template = builtins.toPath {}; in import template {{ username = {}; }}",
        nix_string(template.to_string_lossy().as_ref()),
        nix_string(username),
    );
    let output = Command::new("nix")
        .arg("eval")
        .arg("--raw")
        .arg("--impure")
        .arg("--expr")
        .arg(expr)
        .output()
        .map_err(|err| format!("failed to render bootstrap facts template: {}", err))?;
    if !output.status.success() {
        return Err("failed to render bootstrap facts template".to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

pub(crate) fn evaluate_facts_schema(root: &Path, facts_file: &Path) -> Result<String, String> {
    let schema = root.join("nix/scripts/doctor/facts-schema.nix");
    let expr = format!(
        "let schema = builtins.toPath {}; in import schema {{ factsFile = {}; }}",
        nix_string(schema.to_string_lossy().as_ref()),
        nix_string(facts_file.to_string_lossy().as_ref()),
    );
    let output = Command::new("nix")
        .arg("eval")
        .arg("--raw")
        .arg("--impure")
        .arg("--expr")
        .arg(expr)
        .output()
        .map_err(|err| format!("failed to evaluate facts schema: {}", err))?;
    if !output.status.success() {
        return Err("unable to evaluate facts schema".to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

pub(crate) fn nix_string(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");
    format!("\"{}\"", escaped)
}

pub(crate) fn json_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

pub(crate) fn run_command_status(command: &mut Command) -> Result<ExitStatus, String> {
    command
        .status()
        .map_err(|err| format!("failed to run command: {}", err))
}

pub(crate) fn run_command_output(command: &mut Command) -> Result<std::process::Output, String> {
    command
        .output()
        .map_err(|err| format!("failed to run command: {}", err))
}

pub(crate) fn bash_command(script: &Path, args: &[String]) -> Command {
    let mut command = Command::new("bash");
    command.arg(script);
    command.args(args);
    command
}

pub(crate) fn sudo_preserve_env_vars() -> String {
    let mut vars = vec!["PATH".to_string()];
    for name in [
        "FACTS",
        "FACTS_DIR",
        "SECRETS",
        "SECRETS_DIR",
        "DARWIN_REBUILD_BIN",
        "DOTFILES_ROOT",
    ] {
        if env::var_os(name).is_some() {
            vars.push(name.to_string());
        }
    }
    vars.join(",")
}

pub(crate) fn ensure_file_mode(path: &Path, mode: u32) -> Result<(), String> {
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
        .map_err(|err| format!("failed to chmod {}: {}", path.display(), err))
}

pub(crate) fn ensure_dir_mode(path: &Path, mode: u32) -> Result<(), String> {
    if !path.is_dir() {
        fs::create_dir_all(path)
            .map_err(|err| format!("failed to create {}: {}", path.display(), err))?;
    }
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
        .map_err(|err| format!("failed to chmod {}: {}", path.display(), err))
}

pub(crate) fn git_tracked_files(root: &Path) -> Result<Vec<PathBuf>, String> {
    let output = Command::new("git")
        .current_dir(root)
        .arg("ls-files")
        .arg("-z")
        .output()
        .map_err(|err| format!("failed to enumerate tracked files: {}", err))?;
    if !output.status.success() {
        return Err("export-clean failed to enumerate tracked files".to_string());
    }
    let mut files = Vec::new();
    for chunk in output.stdout.split(|byte| *byte == 0) {
        if chunk.is_empty() {
            continue;
        }
        files.push(PathBuf::from(String::from_utf8_lossy(chunk).to_string()));
    }
    Ok(files)
}

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

#[cfg(test)]
mod tests {
    use super::{parse_target_args, resolve_inputs_from};
    use std::path::Path;

    #[test]
    fn parse_target_args_tracks_passthrough_and_values() {
        let args = vec![
            "--host".to_string(),
            "pro_mac".to_string(),
            "--action".to_string(),
            "build".to_string(),
            "--".to_string(),
            "--show-trace".to_string(),
        ];
        let parsed = parse_target_args(&args, &["--action"]).expect("parse");
        assert_eq!(parsed.host.as_deref(), Some("pro_mac"));
        assert_eq!(parsed.args, vec!["--action".to_string(), "build".to_string()]);
        assert!(parsed.has_passthrough);
        assert_eq!(parsed.passthrough, vec!["--show-trace".to_string()]);
    }

    #[test]
    fn resolve_inputs_defaults_to_home_config_dotfiles() {
        let home = Path::new("/tmp/home");
        let resolved = resolve_inputs_from(home, None, None, None, None).expect("resolve");
        assert_eq!(resolved.facts_ref, "path:/tmp/home/.config/dotfiles");
        assert_eq!(resolved.secrets_ref, "path:/tmp/home/.config/dotfiles");
    }

    #[test]
    fn resolve_inputs_rejects_mismatched_refs() {
        let home = Path::new("/tmp/home");
        let error = resolve_inputs_from(
            home,
            Some("/tmp/facts".to_string()),
            None,
            Some("path:/tmp/other".to_string()),
            None,
        )
        .expect_err("mismatch");
        assert!(error.contains("FACTS_DIR"));
    }
}
