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
- `launch-disabled-extensions.txt`

`launch-disabled-extensions.txt` is launch-only input.
It does not affect `sync vscode` state and is only used by the launch helper.

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

## Launch-only disabled extensions

If you want an extension installed but disabled only at launch time for a specific managed profile, add:

- `apps/vscode/_default/launch-disabled-extensions.txt`
- `apps/vscode/<profile>/launch-disabled-extensions.txt`

Those files are merged and de-duplicated at launch time.
They do not uninstall extensions and are not part of sync drift management.

Launch with the helper:

```bash
nix run .#dotfiles -- vscode launch --profile web
nix run .#dotfiles -- vscode launch --profile native
nix run .#dotfiles -- vscode launch --profile web -- path/to/project
nix run .#dotfiles -- vscode launch --profile web --print-command
```

Behavior:

- `native` launches the built-in Default profile
- any other managed dir name launches the matching native custom profile
- launch-disabled extensions are passed as repeated `--disable-extension <id>` flags
- `sync vscode --apply` does not read `launch-disabled-extensions.txt`
- a normal VS Code launch from Dock, Spotlight, or `code --profile ...` does not read `launch-disabled-extensions.txt`

## Mutable behavior and precedence

The mutable model has two different control planes:

- `sync vscode --apply`
  - installs or uninstalls repo-owned extensions from `extensions.txt`
  - reconciles repo-owned top-level settings keys from `settings.json`
  - preserves user-added extension IDs that are not repo-owned
  - preserves user-added settings keys that are not repo-owned
- `vscode launch --profile ...`
  - does not install or uninstall anything
  - does not rewrite settings
  - only adds launch-time `--disable-extension <id>` flags

That means:

- adding an extension in the VS Code UI does not make `vscode launch` remove it
- disabling or enabling an extension in the VS Code UI does not change repo state
- if an extension is listed in `launch-disabled-extensions.txt`, every `vscode launch` session disables it again for that launch
- if you start VS Code outside the launch helper, launch-disabled extensions are not forced off

## When a user-added extension is removed

User-added extensions stay installed unless they become repo-owned and are later removed from the repo.

Examples:

- you install `foo.bar` manually in VS Code
  - `sync vscode --apply` keeps it, because dotfiles does not own it
- you later add `foo.bar` to `apps/vscode/_default/extensions.txt`
  - now dotfiles owns it
- you later remove `foo.bar` from the repo and run `sync vscode --apply`
  - dotfiles uninstalls it, because it was previously owned and is no longer desired

The same ownership rule applies per profile.
An extension added only to `apps/vscode/web/extensions.txt` is owned only for the `Web` profile.
