use serde::Deserialize;
use std::collections::BTreeMap;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{self, Command, ExitStatus};

pub const SCRIPT_LABEL: &str = "dotfiles";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InputRefs {
    pub facts_dir: Option<PathBuf>,
    pub secrets_dir: Option<PathBuf>,
    pub facts_ref: String,
    pub secrets_ref: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct TargetsManifest {
    pub hosts: BTreeMap<String, HostTargetsManifest>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct HostTargetsManifest {
    #[serde(rename = "defaultRice")]
    pub default_rice: String,
    #[serde(rename = "buildTarget")]
    pub build_target: String,
    #[serde(rename = "supportedRices")]
    pub supported_rices: Vec<String>,
    #[serde(rename = "machineKey")]
    pub machine_key: String,
    pub system: String,
    #[serde(rename = "targetsByRice")]
    pub targets_by_rice: BTreeMap<String, String>,
}

pub fn log(message: &str) {
    eprintln!("{}: {}", SCRIPT_LABEL, message);
}

pub fn die(message: &str) -> ! {
    log(message);
    process::exit(1);
}

pub fn exit_with_status(status: ExitStatus) -> ! {
    process::exit(status.code().unwrap_or(1));
}

pub fn path_ref_to_dir(reference: &str) -> Option<PathBuf> {
    reference.strip_prefix("path:").map(PathBuf::from)
}

pub fn resolve_inputs() -> Result<InputRefs, String> {
    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    resolve_inputs_from(
        Path::new(&home),
        env::var("FACTS_DIR").ok(),
        env::var("SECRETS_DIR").ok(),
        env::var("FACTS").ok(),
        env::var("SECRETS").ok(),
    )
}

pub fn resolve_inputs_from(
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

pub fn require_input_directories(
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

pub fn ensure_inputs_dirs(facts_dir: &Path, secrets_dir: &Path) -> Result<(), String> {
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

pub fn repo_root() -> Result<PathBuf, String> {
    if let Ok(root) = env::var("DOTFILES_ROOT") {
        let path = PathBuf::from(&root);
        if !path.is_dir() {
            return Err(format!(
                "DOTFILES_ROOT is not a readable directory: {}",
                root
            ));
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
    for ancestor in cwd.ancestors() {
        if ancestor.join("flake.nix").is_file() {
            return Ok(ancestor.to_path_buf());
        }
    }

    let exe =
        env::current_exe().map_err(|err| format!("failed to resolve executable path: {}", err))?;
    for ancestor in exe.ancestors() {
        if ancestor.join("flake.nix").is_file() {
            return Ok(ancestor.to_path_buf());
        }
    }

    Err(format!(
        "unable to resolve flake root (expected flake.nix under {})",
        cwd.display()
    ))
}

pub fn flake_ref_for_root(root: &Path) -> String {
    format!("path:{}", root.display())
}

pub fn nix_args_with_inputs(inputs: &InputRefs) -> Vec<OsString> {
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

pub fn list_darwin_targets(root: &Path, inputs: &InputRefs) -> Result<Vec<String>, String> {
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

pub fn load_targets_manifest(root: &Path, inputs: &InputRefs) -> Result<TargetsManifest, String> {
    let manifest_script = root.join("nix/scripts/targets-manifest.nix");

    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg("--json");
    command.arg(format!("{}#darwinConfigurations", flake_ref_for_root(root)));
    command.arg("--impure");
    command.arg("--apply");
    command.arg(format!(
        "targets: (import {} {{ }}).json targets",
        manifest_script.display()
    ));
    command.args(nix_args_with_inputs(inputs));

    let output = command
        .output()
        .map_err(|err| format!("failed to run nix eval: {}", err))?;
    if !output.status.success() {
        return Err("unable to evaluate darwinConfigurations".to_string());
    }

    let manifest: TargetsManifest = serde_json::from_slice(&output.stdout)
        .map_err(|err| format!("failed to parse darwin target manifest: {}", err))?;

    if manifest.hosts.is_empty() {
        return Err("no darwinConfigurations found".to_string());
    }

    Ok(manifest)
}

pub fn resolve_target(
    root: &Path,
    inputs: &InputRefs,
    host: &str,
    rice: Option<&str>,
) -> Result<String, String> {
    if host.is_empty() {
        return Err("host is required".to_string());
    }

    let manifest = load_targets_manifest(root, inputs)?;
    resolve_target_from_manifest(&manifest, host, rice)
}

pub fn explain_darwin_targets_error(inputs: &InputRefs, message: &str) -> String {
    if message != "no darwinConfigurations found"
        && message != "unable to evaluate darwinConfigurations"
    {
        return message.to_string();
    }

    let mut lines = vec![format!("{} (check local/secrets inputs)", message)];
    lines.push(format!("facts input: {}", inputs.facts_ref));
    lines.push(format!("secrets input: {}", inputs.secrets_ref));

    lines.join("\n")
}

fn resolve_target_from_manifest(
    manifest: &TargetsManifest,
    host: &str,
    rice: Option<&str>,
) -> Result<String, String> {
    let missing_message = || {
        format!(
            "target not found for host '{}'{}",
            host,
            rice.map(|value| format!(" and rice '{}'", value))
                .unwrap_or_default()
        )
    };

    let host_manifest = manifest.hosts.get(host).ok_or_else(missing_message)?;

    match rice {
        Some(rice_name) => host_manifest
            .targets_by_rice
            .get(rice_name)
            .cloned()
            .ok_or_else(missing_message),
        None => Ok(host_manifest.build_target.clone()),
    }
}

pub fn require_host_argument(host: Option<&str>, command_name: &str) -> Result<String, String> {
    host.filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            format!(
                "host is required for {} (pass --host <host>, a positional host, or HOST=...)",
                command_name
            )
        })
}

pub fn resolve_pinned_darwin_rebuild_bin(flake_ref: &str) -> Result<String, String> {
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

pub fn list_updateable_root_flake_inputs(root: &Path) -> Result<Vec<String>, String> {
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

pub fn require_writable_checkout(root: &Path, start_dir: &Path) -> Result<PathBuf, String> {
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

pub fn render_bootstrap_facts(root: &Path, username: &str) -> Result<String, String> {
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

pub fn evaluate_facts_schema(root: &Path, facts_file: &Path) -> Result<String, String> {
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

pub fn nix_string(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");
    format!("\"{}\"", escaped)
}

pub fn json_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

pub fn run_command_status(command: &mut Command) -> Result<ExitStatus, String> {
    command
        .status()
        .map_err(|err| format!("failed to run command: {}", err))
}

pub fn run_command_output(command: &mut Command) -> Result<std::process::Output, String> {
    command
        .output()
        .map_err(|err| format!("failed to run command: {}", err))
}

pub fn bash_command(script: &Path, args: &[String]) -> Command {
    let mut command = Command::new("bash");
    command.arg(script);
    command.args(args);
    command
}

pub fn sudo_preserve_env_vars() -> String {
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

pub fn ensure_file_mode(path: &Path, mode: u32) -> Result<(), String> {
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
        .map_err(|err| format!("failed to chmod {}: {}", path.display(), err))
}

pub fn ensure_dir_mode(path: &Path, mode: u32) -> Result<(), String> {
    if !path.is_dir() {
        fs::create_dir_all(path)
            .map_err(|err| format!("failed to create {}: {}", path.display(), err))?;
    }
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
        .map_err(|err| format!("failed to chmod {}: {}", path.display(), err))
}

pub fn git_tracked_files(root: &Path) -> Result<Vec<PathBuf>, String> {
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

pub fn find_in_path(name: &str) -> Option<PathBuf> {
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

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

#[cfg(test)]
mod tests {
    use super::{
        resolve_inputs_from, resolve_target_from_manifest, HostTargetsManifest, TargetsManifest,
    };
    use std::collections::BTreeMap;
    use std::path::Path;

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

    #[test]
    fn resolve_target_uses_build_target_for_default_host() {
        let manifest = TargetsManifest {
            hosts: BTreeMap::from([(
                "pro_mac".to_string(),
                HostTargetsManifest {
                    default_rice: "pro".to_string(),
                    build_target: "pro_mac".to_string(),
                    supported_rices: vec!["base".to_string(), "pro".to_string()],
                    machine_key: "pro_mac".to_string(),
                    system: "aarch64-darwin".to_string(),
                    targets_by_rice: BTreeMap::from([
                        ("base".to_string(), "pro_mac-base".to_string()),
                        ("pro".to_string(), "pro_mac".to_string()),
                    ]),
                },
            )]),
        };

        let resolved = resolve_target_from_manifest(&manifest, "pro_mac", None).expect("resolve");
        assert_eq!(resolved, "pro_mac");
    }

    #[test]
    fn resolve_target_uses_targets_by_rice_for_explicit_rice() {
        let manifest = TargetsManifest {
            hosts: BTreeMap::from([(
                "ultra_mac".to_string(),
                HostTargetsManifest {
                    default_rice: "ultra".to_string(),
                    build_target: "ultra_mac".to_string(),
                    supported_rices: vec!["base".to_string(), "ultra".to_string()],
                    machine_key: "ultra_mac".to_string(),
                    system: "aarch64-darwin".to_string(),
                    targets_by_rice: BTreeMap::from([
                        ("base".to_string(), "ultra_mac-base".to_string()),
                        ("ultra".to_string(), "ultra_mac".to_string()),
                    ]),
                },
            )]),
        };

        let resolved =
            resolve_target_from_manifest(&manifest, "ultra_mac", Some("base")).expect("resolve");
        assert_eq!(resolved, "ultra_mac-base");
    }

    #[test]
    fn resolve_target_reports_missing_host_or_rice() {
        let empty_manifest = TargetsManifest {
            hosts: BTreeMap::new(),
        };
        let missing_host =
            resolve_target_from_manifest(&empty_manifest, "ghost_mac", None).expect_err("err");
        assert_eq!(missing_host, "target not found for host 'ghost_mac'");

        let manifest = TargetsManifest {
            hosts: BTreeMap::from([(
                "minimal_mac".to_string(),
                HostTargetsManifest {
                    default_rice: "base".to_string(),
                    build_target: "minimal_mac".to_string(),
                    supported_rices: vec!["base".to_string()],
                    machine_key: "minimal_mac".to_string(),
                    system: "aarch64-darwin".to_string(),
                    targets_by_rice: BTreeMap::from([(
                        "base".to_string(),
                        "minimal_mac".to_string(),
                    )]),
                },
            )]),
        };
        let missing_rice =
            resolve_target_from_manifest(&manifest, "minimal_mac", Some("ultra")).expect_err("err");
        assert_eq!(
            missing_rice,
            "target not found for host 'minimal_mac' and rice 'ultra'"
        );
    }
}
