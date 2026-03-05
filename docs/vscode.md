# VS Code Instances (Directory Profiles)

This repository runs multiple isolated VS Code instances using the upstream
CLI flags:

- `--user-data-dir` (settings, UI state, keychain integration, etc.)
- `--extensions-dir` (installed extensions)

This avoids brittle macOS app-bundle modifications (Info.plist patching,
helper renames, re-signing).

## Profile Layout

Profiles live in `apps/vscode/<name>/`:

- `apps/vscode/_default/` (baseline)
- `apps/vscode/python/`
- `apps/vscode/web/`
- ...

Supported files:

- `settings.json` (optional)
- `extensions.txt` (optional)
- `extensions-disabled.txt` (optional)
  - IDs listed here are installed (if missing) but always launched disabled via
    `--disable-extension <id>`.
- `icon.icns` (optional, macOS launcher icon)

Example:

```text
apps/vscode/python/extensions.txt
  ms-python.python
  ms-toolsai.jupyter

apps/vscode/python/extensions-disabled.txt
  github.copilot-chat
```

## Generated Commands

For each profile `name`:

- `code-<name>`
  - Launches the instance with its own dirs under:
    - `${VSCODE_INSTANCES_BASE}/<name>/user-data`
    - `${VSCODE_INSTANCES_BASE}/<name>/extensions`
  - Auto-runs bootstrap when the baseline changes.
  - Always passes `--disable-extension` for each entry in
    `extensions-disabled.txt` (so even if you enabled it last session, it will
    be disabled again on next launch).
- `code-<name>-bootstrap`
  - Seeds/updates `${user-data}/User/settings.json` and installs baseline
    extensions (incremental; does not remove user-installed extensions).
- `code-<name>-reset`
  - Moves the instance directory to a timestamped backup and re-runs bootstrap.

Notes:

- The "disabled" behavior is enforced at launch time (by CLI flags). It is not
  written into VS Code's internal state DB.
- For debugging, you can skip auto-bootstrap with `VSCODE_SKIP_BOOTSTRAP=1`.
- To force baseline extensions to re-install, use `VSCODE_FORCE_EXTENSIONS=1`
  with `code-<name>-bootstrap`.

## Settings Merge Rules

During bootstrap, settings are merged:

- Baseline (`_default/settings.json` + `<name>/settings.json`) first
- Existing `${user-data}/User/settings.json` second (user wins)

Exception: instance identity keys are always taken from the baseline to avoid
drift (e.g., window title badges and bar colors).

## macOS App Launchers

On macOS, lightweight `.app` launchers are created under:

- `~/Applications/VS Code Instances/`

These are simple wrappers around `code-<name>` (no upstream VS Code.app
modification). As a result, Dock/menubar app identity may still show as "Code",
but the instance is visually identified via the window title badge and bar
colors.

## Runtime Script

Operational behavior for `bootstrap`, `launch`, and `reset` lives in:

- `nix/scripts/vscode-instances.sh`

The Nix module (`nix/denix/modules/tools/editor/vscode.nix`) is responsible for
declarative instance data and thin command wiring only.
