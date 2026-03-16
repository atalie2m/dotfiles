use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Mode {
    Check,
    Apply,
}

#[derive(Clone, Debug)]
pub(crate) struct CliArgs {
    pub(crate) managed_dir: Option<PathBuf>,
    pub(crate) state_dir: Option<PathBuf>,
    pub(crate) mode: Mode,
    pub(crate) details: bool,
    pub(crate) diff_output: bool,
    pub(crate) profile_filters: Vec<String>,
}

#[derive(Clone, Debug)]
pub(crate) struct Context {
    pub(crate) managed_dir: PathBuf,
    pub(crate) state_dir: PathBuf,
    pub(crate) mode: Mode,
    pub(crate) details: bool,
    pub(crate) diff_output: bool,
    pub(crate) profile_filters: Vec<String>,
    pub(crate) code_bin: String,
    pub(crate) code_cli_retries: u32,
    pub(crate) vscode_data_home: PathBuf,
    pub(crate) user_data_home: PathBuf,
    pub(crate) profiles_home: PathBuf,
    pub(crate) global_storage_dir: PathBuf,
    pub(crate) storage_json_path: PathBuf,
    pub(crate) extensions_root: PathBuf,
    pub(crate) extensions_manifest_path: PathBuf,
}

#[derive(Default)]
pub(crate) struct Summary {
    pub(crate) selected_count: u32,
    pub(crate) checked: u32,
    pub(crate) in_sync: u32,
    pub(crate) needs_apply: u32,
    pub(crate) missing: u32,
    pub(crate) invalid: u32,
    pub(crate) applied: u32,
    pub(crate) errors: u32,
}
