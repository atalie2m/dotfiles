use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ProfileStatus {
    InSync,
    NeedsApply,
    Missing,
    Invalid,
}

impl ProfileStatus {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::InSync => "in-sync",
            Self::NeedsApply => "needs-apply",
            Self::Missing => "missing",
            Self::Invalid => "invalid",
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct ProfilePlan {
    pub(crate) profile_dir_name: String,
    pub(crate) profile_name: String,
    pub(crate) desired_settings: Map<String, Value>,
    pub(crate) desired_extensions: Vec<String>,
    pub(crate) desired_default_disabled: Vec<String>,
    pub(crate) state_file: PathBuf,
    pub(crate) settings_path: PathBuf,
    pub(crate) extensions_manifest: PathBuf,
    pub(crate) runtime_dir: PathBuf,
}

#[derive(Clone, Debug)]
pub(crate) struct ProfileEvaluation {
    pub(crate) status: ProfileStatus,
    pub(crate) reason: String,
    pub(crate) settings_diff_expected: Option<Value>,
    pub(crate) settings_diff_actual: Option<Value>,
    pub(crate) extensions_add: Vec<String>,
    pub(crate) extensions_remove: Vec<String>,
}

#[derive(Clone, Default, Debug)]
pub(crate) struct StateLists {
    pub(crate) owned_extensions: Vec<String>,
    pub(crate) bootstrapped_default_disabled_extensions: Vec<String>,
}

#[derive(Clone, Debug)]
pub(crate) enum StateLoad {
    Missing,
    Invalid,
    Loaded(StateLists),
}

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct StateFile {
    pub(crate) version: u32,
    #[serde(rename = "profileDirName")]
    pub(crate) profile_dir_name: String,
    #[serde(rename = "profileName")]
    pub(crate) profile_name: String,
    #[serde(rename = "ownedExtensions")]
    pub(crate) owned_extensions: Vec<String>,
    #[serde(rename = "bootstrappedDefaultDisabledExtensions")]
    pub(crate) bootstrapped_default_disabled_extensions: Vec<String>,
}
