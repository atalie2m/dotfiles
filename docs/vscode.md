# VS Code Profiles

This repository manages one VS Code installation and reconciles native VS Code profiles into writable runtime state.
It no longer uses isolated per-instance runtime directories.

The VS Code application itself is not installed by Nix in this setup.
Install Visual Studio Code.app separately, or set `VSCODE_CODE_BIN` to the `code` CLI path.

## Managed layout

Profiles live under `apps/vscode/<name>/`:

- `apps/vscode/_default/`
  - Shared layer applied to every managed profile.
  - Not a runtime profile by itself.
- `apps/vscode/native/`
  - Managed as a custom native profile with display name `Native`.
- `apps/vscode/<name>/`
  - Any other directory maps to a native custom profile.
  - The display name is derived from the directory name (`data-science` -> `Data Science`, `web` -> `Web`).

Note: VS Code's built-in `Default` profile is intentionally unmanaged. It is left as-is by `sync vscode`, so existing extensions/settings there are preserved.

## Stock Darwin rices and VS Code

Only the **`ultra`** rice turns on the VS Code Home Manager module (`tools.editor.vscode.enable`) and activation-time `sync vscode --apply` (`tools.editor.vscode.sync.enable`). The other stock rices (`base`, `darwin`, `dev`, `pro`, `partial`) do not; VS Code is still optional on the machine, but dotfiles will not install `dotfiles-sync-vscode` into the profile or reconcile profiles during activation unless you enable those options in your own config. You can always run `nix run .#dotfiles -- sync vscode --apply` by hand.

### Bulk extension install: source of truth

Ultra is meant to carry a large, repo-owned extension set. **What gets installed or removed is whatever is listed under `apps/vscode/`**, not an ad hoc list elsewhere:

- `apps/vscode/_default/extensions.txt` — shared extension IDs merged into every managed profile
- `apps/vscode/<profile>/extensions.txt` — extra IDs for that profile (for example `native/`, `web/`, `data-science/`, `writing/`)

Effective repo-owned extensions per profile are the union of `_default` and that profile's file, unique by extension ID (see Effective extensions below). Adding or removing lines there changes the next apply.

If you want fully independent profile management, keep files under `apps/vscode/_default/` empty and define all settings/extensions/default-disabled entries per profile.

Supported files:

- `settings.json`
- `extensions.txt`
- `default-disabled-extensions.txt`

`default-disabled-extensions.txt` is bootstrap-only input.
It is applied through `sync vscode --apply`, not at launch time.

## Runtime model

`sync vscode` builds the desired profile state from the repo and writes it into VS Code's native profile storage.
The CLI entrypoint dispatches to the Rust engine (`dotfiles-sync-vscode`) only.

- Effective settings:
  - `_default/settings.json` recursively merged with `<profile>/settings.json`
- Effective extensions:
  - `_default/extensions.txt` plus `<profile>/extensions.txt`, unique by extension ID
- Runtime ownership:
  - The repo owns the effective managed profile settings file
  - The repo owns the effective extension IDs
- Mutable drift:
  - Managed settings files converge on apply
  - User-added extensions are preserved
  - Removed repo-owned settings and extensions are deleted on the next apply

To support that mutable model, sync keeps minimal local state per profile under the VS Code sync state directory.
That state records:

- previously owned extension IDs
- which default-disabled extension IDs have already been bootstrapped for the current profile

State schema notes:

- current schema version is `4`
- older or malformed state files are treated as `needs-apply`
- apply rewrites state in the current schema

## Runtime locations

On macOS:

- Custom profile settings live in `~/Library/Application Support/Code/User/profiles/<profile-id>/settings.json`
- `native` is managed as a custom profile under the same path, using its own profile id:
  - `~/Library/Application Support/Code/User/profiles/<native-profile-id>/settings.json`
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

`sync vscode --apply` is also run during Home Manager activation when both
`tools.editor.vscode.enable = true` and `tools.editor.vscode.sync.enable = true`.
In the stock capability bundles, only **`ultra`** sets both; keep `tools.editor.vscode.sync.enable = false`
(or leave the module disabled) if you want VS Code on disk but no automatic activation-time reconciliation.

## Manual switching

Profile selection stays manual.
Switch profiles in the VS Code UI, or launch with upstream profile support such as:

```bash
code --profile "Web"
code --profile "Data Science"
```

`sync vscode` manages the underlying profile contents; it does not pick the active profile for you.

## Bootstrap-only default-disabled extensions

If you want an extension installed by dotfiles but disabled by default when the profile is first bootstrapped, add:

- `apps/vscode/_default/default-disabled-extensions.txt`
- `apps/vscode/<profile>/default-disabled-extensions.txt`

Those files are merged and de-duplicated during `sync vscode --apply`.
The seed is bootstrap-only:

- a newly listed extension ID is added once to the profile's disabled extension state
- if the same extension was explicitly enabled by the user later in VS Code, future applies do not force it back off
- if you add a new extension ID to `default-disabled-extensions.txt` later, the next apply seeds only that new ID

This is part of sync state, not launch behavior.
Start VS Code normally with the upstream profile selector:

```bash
code --profile "Web"
code --profile "Data Science"
```

## Mutable behavior and precedence

The mutable model is controlled only by `sync vscode --apply`:

- repo-owned extensions from `extensions.txt` are installed or uninstalled
- managed profile settings from `settings.json` are rewritten as fully repo-owned files
- user-added extension IDs that are not repo-owned are preserved
- default-disabled extension IDs are bootstrapped once from `default-disabled-extensions.txt`

That means:

- adding an extension in the VS Code UI does not make sync remove it unless dotfiles later takes ownership of it
- manual settings changes inside a managed profile are overwritten on the next apply
- disabling or enabling an extension in the VS Code UI does not change repo state
- enabling an extension that was previously bootstrapped from `default-disabled-extensions.txt` is preserved on future applies
- there is no launch helper and no launch-time disable flag in this model

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
