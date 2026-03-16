use std::fs;
use std::path::Path;

use crate::domain::model::{StateFile, StateLists, StateLoad};
use crate::infra::json::write_json_atomically;
use crate::STATE_VERSION;

pub(crate) fn write_state_file(
    state_file: &Path,
    profile_dir_name: &str,
    profile_name: &str,
    owned_extensions: &[String],
    bootstrapped_default_disabled_extensions: &[String],
) -> Result<(), String> {
    let state = StateFile {
        version: STATE_VERSION,
        profile_dir_name: profile_dir_name.to_string(),
        profile_name: profile_name.to_string(),
        owned_extensions: owned_extensions.to_vec(),
        bootstrapped_default_disabled_extensions: bootstrapped_default_disabled_extensions.to_vec(),
    };

    let value = serde_json::to_value(state)
        .map_err(|err| format!("failed to encode state file JSON: {}", err))?;
    write_json_atomically(&value, state_file)
}

pub(crate) fn load_state_lists(
    state_file: &Path,
    profile_dir_name: &str,
    profile_name: &str,
) -> Result<StateLoad, String> {
    if !state_file.is_file() {
        return Ok(StateLoad::Missing);
    }

    let state_text = fs::read_to_string(state_file)
        .map_err(|err| format!("failed to read state file {}: {}", state_file.display(), err))?;

    let parsed: StateFile = match serde_json::from_str(&state_text) {
        Ok(state) => state,
        Err(_) => return Ok(StateLoad::Invalid),
    };

    if parsed.version != STATE_VERSION
        || parsed.profile_dir_name != profile_dir_name
        || parsed.profile_name != profile_name
    {
        return Ok(StateLoad::Invalid);
    }

    Ok(StateLoad::Loaded(StateLists {
        owned_extensions: parsed.owned_extensions,
        bootstrapped_default_disabled_extensions: parsed.bootstrapped_default_disabled_extensions,
    }))
}
