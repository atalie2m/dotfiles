pub(crate) mod apply;
pub(crate) mod bootstrap;
pub(crate) mod doctor;
pub(crate) mod export_clean;
pub(crate) mod sync;
pub(crate) mod tools;
pub(crate) mod update;

use clap::error::ErrorKind;
use clap::{Args, Parser, Subcommand, ValueEnum};
use dotfiles_core::support::{nix_args_with_inputs, run_command_output, InputRefs};
use std::process;
use std::process::Command;

#[derive(Clone)]
pub(crate) struct CheckRecord {
    pub(crate) name: String,
    pub(crate) status: String,
    pub(crate) message: String,
}

impl CheckRecord {
    pub(crate) fn new(name: &str, status: &str, message: impl Into<String>) -> Self {
        Self {
            name: name.to_string(),
            status: status.to_string(),
            message: message.into(),
        }
    }
}

#[derive(Parser)]
#[command(
    name = "dotfiles",
    about = "Unified dotfiles CLI",
    disable_version_flag = true,
    arg_required_else_help = true
)]
struct Cli {
    #[command(subcommand)]
    command: RootCommand,
}

#[derive(Subcommand)]
enum RootCommand {
    Apply(ApplyArgs),
    Update(UpdateArgs),
    Doctor(DoctorArgs),
    Bootstrap(BootstrapArgs),
    ExportClean(ExportCleanArgs),
    #[command(name = "list-tools")]
    ListTools(ListToolsArgs),
    #[command(name = "matrix-tools")]
    MatrixTools(MatrixToolsArgs),
    Sync(SyncArgs),
}

#[derive(Args, Clone, Debug, Default)]
pub(crate) struct TargetSelector {
    #[arg(long)]
    pub(crate) host: Option<String>,
    #[arg(long)]
    pub(crate) profile: Option<String>,
    #[arg(value_name = "host", hide = true)]
    pub(crate) host_positional: Option<String>,
}

impl TargetSelector {
    pub(crate) fn host_value(&self) -> Option<&str> {
        self.host.as_deref().or(self.host_positional.as_deref())
    }

    pub(crate) fn profile_value(&self) -> Option<&str> {
        self.profile.as_deref()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum ApplyAction {
    Switch,
    Build,
}

impl ApplyAction {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Switch => "switch",
            Self::Build => "build",
        }
    }
}

#[derive(Args, Clone, Debug)]
pub(crate) struct ApplyArgs {
    #[command(flatten)]
    pub(crate) target: TargetSelector,
    #[arg(long, value_enum, default_value_t = ApplyAction::Switch)]
    pub(crate) action: ApplyAction,
    #[arg(long)]
    pub(crate) no_sudo: bool,
    #[arg(last = true)]
    pub(crate) passthrough: Vec<String>,
}

#[derive(Args, Clone, Debug)]
pub(crate) struct UpdateArgs {
    #[command(flatten)]
    pub(crate) target: TargetSelector,
}

#[derive(Args, Clone, Debug)]
pub(crate) struct DoctorArgs {
    #[command(flatten)]
    pub(crate) target: TargetSelector,
    #[arg(long)]
    pub(crate) strict: bool,
    #[arg(long)]
    pub(crate) json: bool,
}

#[derive(Args, Clone, Debug)]
pub(crate) struct BootstrapArgs {
    #[command(flatten)]
    pub(crate) target: TargetSelector,
    #[arg(long)]
    pub(crate) apply: bool,
    #[arg(long)]
    pub(crate) yes: bool,
    #[arg(long)]
    pub(crate) no_sudo: bool,
    #[arg(long)]
    pub(crate) strict: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum ExportFormat {
    Dir,
    Tar,
}

#[derive(Args, Clone, Debug)]
pub(crate) struct ExportCleanArgs {
    #[arg(long)]
    pub(crate) output: std::path::PathBuf,
    #[arg(long, value_enum, default_value_t = ExportFormat::Dir)]
    pub(crate) format: ExportFormat,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum OutputFormat {
    Json,
    Text,
}

impl OutputFormat {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Json => "json",
            Self::Text => "text",
        }
    }
}

#[derive(Args, Clone, Debug)]
pub(crate) struct ListToolsArgs {
    #[command(flatten)]
    pub(crate) target: TargetSelector,
    #[arg(long, value_enum, default_value_t = OutputFormat::Text)]
    pub(crate) format: OutputFormat,
}

#[derive(Args, Clone, Debug)]
pub(crate) struct MatrixToolsArgs {
    #[arg(long, value_enum, default_value_t = OutputFormat::Text)]
    pub(crate) format: OutputFormat,
    #[arg(long)]
    pub(crate) full: bool,
}

#[derive(Args, Clone, Debug)]
#[command(arg_required_else_help = true, trailing_var_arg = true)]
pub(crate) struct SyncArgs {
    #[arg(value_enum)]
    pub(crate) surface: SyncSurface,
    #[arg(allow_hyphen_values = true)]
    pub(crate) args: Vec<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum SyncSurface {
    Emacs,
    #[value(alias = "nvim")]
    Neovim,
    Shell,
    Vscode,
}

pub(crate) fn run(args: Vec<String>) -> Result<(), String> {
    let cli = parse_or_display(Cli::try_parse_from(
        std::iter::once("dotfiles".to_string()).chain(args),
    ))?;

    match cli.command {
        RootCommand::Apply(args) => apply::command_apply(&args),
        RootCommand::Update(args) => update::command_update(&args),
        RootCommand::Doctor(args) => doctor::command_doctor(&args),
        RootCommand::Bootstrap(args) => bootstrap::command_bootstrap(&args),
        RootCommand::ExportClean(args) => export_clean::command_export_clean(&args),
        RootCommand::ListTools(args) => tools::command_list_tools(&args),
        RootCommand::MatrixTools(args) => tools::command_matrix_tools(&args),
        RootCommand::Sync(args) => sync::command_sync(&args),
    }
}

pub(crate) fn parse_or_display<T>(result: Result<T, clap::Error>) -> Result<T, String> {
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

pub(crate) fn atty_stdin() -> bool {
    std::io::IsTerminal::is_terminal(&std::io::stdin())
}

pub(crate) fn is_effective_root() -> bool {
    let mut id = std::process::Command::new("id");
    id.arg("-u");
    dotfiles_core::support::run_command_output(&mut id)
        .ok()
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .as_deref()
        == Some("0")
}

pub(crate) fn eval_target_bool(
    flake_ref: &str,
    inputs: &InputRefs,
    target: &str,
    option_path: &str,
) -> Result<Option<bool>, String> {
    let mut command = Command::new("nix");
    command.arg("eval");
    command.arg("--raw");
    command.arg(format!(
        "{}#darwinConfigurations.{}.config.{}",
        flake_ref, target, option_path
    ));
    command.arg("--apply");
    command.arg(r#"x: if x then "true" else "false""#);
    command.args(nix_args_with_inputs(inputs));
    let output = run_command_output(&mut command)?;
    if !output.status.success() {
        return Ok(None);
    }
    match String::from_utf8_lossy(&output.stdout).trim() {
        "true" => Ok(Some(true)),
        "false" => Ok(Some(false)),
        _ => Ok(None),
    }
}
