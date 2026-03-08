# VS Code Profiles

This repository manages one VS Code installation and reconciles native VS Code profiles into writable runtime state.
It no longer uses isolated per-instance runtime directories.

## Managed layout

Profiles live under `apps/vscode/<name>/`:

- `apps/vscode/_default/`
  - Shared layer applied to every managed profile.
  - Not a runtime profile by itself.
- `apps/vscode/native/`
  - Maps to VS Code's built-in Default profile.
- `apps/vscode/<name>/`
  - Any other directory maps to a native custom profile.
  - The display name is derived from the directory name (`python` -> `Python`, `web` -> `Web`).

Supported files:

- `settings.json`
- `extensions.txt`

Legacy per-profile extension disable lists are not supported by native profile sync.
Remove those files if they still exist in a managed profile.

## Runtime model

`sync vscode` builds the desired profile state from the repo and writes it into VS Code's native profile storage.

- Effective settings:
  - `_default/settings.json` recursively merged with `<profile>/settings.json`
- Effective extensions:
  - `_default/extensions.txt` plus `<profile>/extensions.txt`, unique by extension ID
- Runtime ownership:
  - The repo owns the effective settings' top-level keys
  - The repo owns the effective extension IDs
- Mutable drift:
  - Owned keys and owned extensions converge on apply
  - User-added settings keys and user-added extensions are preserved
  - Removed repo-owned keys and extensions are deleted on the next apply

To support that mutable model, sync keeps minimal local state per profile under the VS Code sync state directory.
That state records the previously owned top-level settings keys and extension IDs so apply can remove repo-owned items that were deleted from `apps/vscode/`.

## Runtime locations

On macOS:

- `native` settings live in `~/Library/Application Support/Code/User/settings.json`
- custom profile settings live in `~/Library/Application Support/Code/User/profiles/<profile-id>/settings.json`
- sync state defaults to `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode`

`sync vscode` bootstraps custom profiles as needed and updates VS Code's profile registry before writing managed state.

## Commands

Use the public sync entrypoint:

```bash
# Check all managed profiles
nix run .#dotfiles -- sync vscode --check

# Check with details or projected diffs
nix run .#dotfiles -- sync vscode --check --details
nix run .#dotfiles -- sync vscode --check --details --diff

# Apply all managed profiles
nix run .#dotfiles -- sync vscode --apply

# Restrict to one repo profile directory
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native

# Override source or state locations
nix run .#dotfiles -- sync vscode --apply --managed-dir /path/to/apps/vscode
nix run .#dotfiles -- sync vscode --apply --state-dir /path/to/state
```

Flags:

- `--check`
- `--apply`
- `--details`
- `--diff`
- `--profile <name>`
- `--managed-dir <path>`
- `--state-dir <path>`

`sync vscode --apply` is also run during Home Manager activation when VS Code is enabled.

## Manual switching

Profile selection stays manual.
Switch profiles in the VS Code UI, or launch with upstream profile support such as:

```bash
code --profile "Web"
code --profile "Python"
```

`sync vscode` manages the underlying profile contents; it does not pick the active profile for you.
