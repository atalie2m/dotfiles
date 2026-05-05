[日本語版はこちら](ja/commands.md)

# Commands

Canonical command examples and current host names live here. Keep README and AI helper files aligned to this page instead of duplicating command surfaces elsewhere.

## Current hosts and packages

- Hosts: `own_mac` (default profile: `pro`), `work_mac` (default profile: `pro`)
- Profiles: `minimal`, `lite`, `pro`, `ultra`
- Example darwin targets: `own_mac`, `own_mac-minimal`, `own_mac-lite`, `own_mac-ultra`, `work_mac`, `work_mac-minimal`, `work_mac-lite`, `work_mac-ultra`
- Packages: `dotfiles`, `dotfiles-cli`, `dotfiles-sync-vscode`
- Templates: `web-dev`, `rust-dev`, `go-dev`, `python-research`, `data-pipeline`, `native-dev`, `embedded-dev`, `apple-dev`, `infra-nixos`, `infra-iac`, `kubernetes-dev`, `container-oci`, `model-hf`, `docs-dev`, `api-db`, `ai-coding`, `release-dev`

## Project templates

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
nix flake init -t github:atalie2m/dotfiles#rust-dev
nix flake init -t github:atalie2m/dotfiles#infra-iac
nix flake init -t github:atalie2m/dotfiles#python-research
```

After initializing a template, treat the project as a Git flake:

```bash
nix run .#...
nix build .#...
nix develop
nix flake check
```

Do not use unfiltered local path refs such as `path:$PWD#...`; they can copy
`.git/`, `target/`, `node_modules/`, and `.direnv/` into `/nix/store`.

## Operational CLI

These commands are Darwin-only and resolve `darwinConfigurations`.
`work_mac` applies its host policy after the selected profile and host overrides, so `--profile ultra` is still capped by the work boundary.

```bash
# Apply default profile for each host
nix run .#apply -- --host own_mac
nix run .#apply -- --host work_mac

# Build only
nix run .#apply -- --host own_mac --action build

# Switch profiles explicitly
nix run .#apply -- --host own_mac --profile ultra
nix run .#apply -- --host work_mac --profile lite
nix run .#apply -- --host work_mac --profile ultra
nix run .#apply -- --host own_mac --profile minimal

# Inspect effective group/tool toggles
nix run .#list-tools -- --host own_mac
nix run .#list-tools -- --host work_mac --profile ultra --format json

# Inspect cross-target toggle matrix
nix run .#matrix-tools
nix run .#matrix-tools -- --format json
nix run .#matrix-tools -- --full --format json

# Bootstrap local inputs
nix run .#bootstrap
nix run .#bootstrap -- --host own_mac --apply
nix run .#bootstrap -- --host own_mac --yes

# Health checks
nix run .#doctor
nix run .#doctor -- --host own_mac
nix run .#doctor -- --host work_mac --strict
nix run .#doctor -- --json

# Update flake inputs and run checks/builds
UPDATE_SKIP_BUILD=1 nix run .#update
nix run .#update -- --host own_mac
UPDATE_ALL=1 nix run .#update -- --host own_mac
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host own_mac

# Refresh the installed dotfiles CLI/runtime from this checkout
nix run .#self-update -- --host own_mac
nix run .#self-update -- --host own_mac --profile ultra

# Validate the target without changing user or Home Manager profiles
nix run .#self-update -- --host own_mac --action build --no-user-profile
```

`self-update` is the one-shot command for changes to the dotfiles Rust CLI,
including the Codex Slack notification runtime. It upgrades an existing
`dotfiles` entry in the default user Nix profile when present, then runs the
canonical Darwin/Home Manager apply path for the selected target. The second
step is what refreshes the `dotfiles` binary normally found first in `PATH` at
`/etc/profiles/per-user/$USER/bin/dotfiles`. Use `--no-user-profile` if the
ad-hoc user profile entry is not part of the host setup you want to maintain.

## Nix store cleanup

`gc` is hostless and does not resolve `darwinConfigurations`.

```bash
nix run .#gc
nix run .#gc -- --apply
nix run .#gc -- --apply --delete-older-than 14d
nix run .#gc -- --apply --store-only
```

`--apply` uses non-interactive `sudo` for system and root profile history cleanup. Run `sudo -v` first if your sudo timestamp is not already active.

If an unfiltered path-flake run bloated the store, inspect collectable paths
first and then clean old generations:

```bash
nix store gc --dry-run
sudo nix-collect-garbage -d
```

## Runtime sync

```bash
# Apply Doom Emacs bootstrap/sync and Neovim config sync together
nix run .#sync
nix run .#sync -- --check
nix run .#sync -- --check --details --diff

# Shell entrypoints
nix run .#dotfiles -- sync shell --check
nix run .#dotfiles -- sync shell --check --details --diff
nix run .#dotfiles -- sync shell --apply

# Doom Emacs config
nix run .#dotfiles -- sync emacs --check
nix run .#dotfiles -- sync emacs --check --details --diff
nix run .#dotfiles -- sync emacs --apply
nix run .#dotfiles -- sync emacs --apply --bootstrap
nix run .#dotfiles -- sync emacs --check --config-only
nix run .#dotfiles -- sync emacs --adopt --item config

# Neovim config and Lazy lock state
nix run .#dotfiles -- sync neovim --check
nix run .#dotfiles -- sync neovim --check --details --diff
nix run .#dotfiles -- sync neovim --apply
nix run .#dotfiles -- sync neovim --adopt

# VS Code native profiles
nix run .#dotfiles -- sync vscode --check
nix run .#dotfiles -- sync vscode --check --details --diff
nix run .#dotfiles -- sync vscode --apply
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native
```

## Codex Slack notifications

`dotfiles agent-notify codex` is the canonical Rust command for Codex Slack
notifications. `scripts/codex-slack-notification` is only a compatibility shim
that delegates to `dotfiles agent-notify codex` for existing hook configs.
Stock profile ownership is `ultra`-only through
`tools.aiCodingAgent.codex.slackNotifications.enable`; `pro` does not enable
the notification runtime by default.
Prefer Bot User OAuth token mode for Slack thread support; the incoming webhook
is a fallback for one-off replies only.

The Rust implementation uses a generic agent-event core. The Codex adapter
parses Codex hook stdin, transcript records, titles, questions, approvals, and
completion events into typed events. The Slack sink receives only titles, body,
thread key, and event kind; it owns Bot API / webhook posting, thread state,
fallback, and error logging.

```bash
# Store Slack credentials locally, outside Git
mkdir -p ~/.config/dotfiles/files/agent-notifications
printf '%s\n' 'xoxb-...' \
  > ~/.config/dotfiles/files/agent-notifications/slack-bot-token
printf '%s\n' 'C0123456789' \
  > ~/.config/dotfiles/files/agent-notifications/slack-channel-id
chmod 0600 \
  ~/.config/dotfiles/files/agent-notifications/slack-bot-token \
  ~/.config/dotfiles/files/agent-notifications/slack-channel-id

# Optional fallback when bot token mode is unavailable
printf '%s\n' 'https://hooks.slack.com/services/...' \
  > ~/.config/dotfiles/files/agent-notifications/slack-webhook-url
chmod 0600 ~/.config/dotfiles/files/agent-notifications/slack-webhook-url

# Preview the Slack payload without posting
dotfiles agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/path/to/project",
  "last_assistant_message": "Dry-run notification."
}
JSON

# Send a one-off setup test notification
dotfiles agent-notify test

# Update only the Codex Slack notification runtime; no Darwin switch.
nix run .#codex-slack-update
```

The old `~/.config/dotfiles/files/codex/slack-*` credential files are still read
as fallback inputs, so existing local secrets do not need to move immediately.

`codex-slack-update` installs or upgrades the `dotfiles` entry in the default
user Nix profile only. `scripts/codex-slack-notification` prefers
`$HOME/.nix-profile/bin/dotfiles` when it exists, so Codex Slack hook fixes can
be rolled out without running a full Darwin/Home Manager switch. Use
`nix run .#self-update -- --host <host>` only when the broader installed
dotfiles runtime should converge too.

Add the hooks to `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true

# Fallback turn-completion hook. The transcript watcher owns normal completion
# delivery when SessionStart provided a transcript path.
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "/path/to/dotfiles/scripts/codex-slack-notification"
timeout = 10
statusMessage = "Sending Codex Slack notification"

# Start a lightweight transcript watcher. It creates the Slack parent from the
# Codex-generated title when available, catches Plan Mode request_user_input
# questions before the answer is submitted, skips auto-resolved request_user_input
# records outside Plan Mode, and sends completion replies from that exact Codex
# transcript.
[[hooks.SessionStart]]
[[hooks.SessionStart.hooks]]
type = "command"
command = "/path/to/dotfiles/scripts/codex-slack-notification --spawn-watcher"
timeout = 5
statusMessage = "Starting Codex Slack transcript watcher"

# Notify when Codex is waiting for an approval or permission answer.
[[hooks.PermissionRequest]]
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "/path/to/dotfiles/scripts/codex-slack-notification"
timeout = 10
```

`Stop`, `SessionStart`, and `PermissionRequest` are Codex lifecycle event names.
`SessionStart` starts the transcript watcher. The watcher reads from the start
of the session transcript, creates the Slack parent when Codex emits
`thread_name_updated`, and formats it as `Codex: <title> (<repo>)`. If no title
event is available, the first reply derives a short title from the first user
prompt before falling back to `Codex: <repo>`; a later title event updates the
parent with `chat.update`. Plan Mode `request_user_input` questions and
transcript `task_complete` records are posted as replies from the watcher that
belongs to that exact Codex session. `request_user_input` records that Codex
auto-resolves outside Plan Mode are ignored. `Stop` remains as a fallback for
turn-completion payloads that arrive outside the watcher path, and labels
question-like final messages as `Codex needs input`. `PreToolUse`,
`UserPromptSubmit`, and successful `PostToolUse` events are intentionally not
enabled by default to avoid Slack noise and Codex-internal helper prompts.
Leave `statusMessage` unset on `PermissionRequest`: Codex renders it before the
helper can inspect the payload, so auto-resolved permission events can otherwise
create UI noise even when no Slack message is sent.

The helper still supports `PostToolUse` failure payloads, but keep that hook
opt-in. Codex runs `PostToolUse` after every matched tool call, so even a silent
helper adds per-tool hook overhead, and a `statusMessage` appears on successful
tool calls too.
Secret storage details live in
[`docs/secrets-local.md`](secrets-local.md#codex-slack-notifications).

Slack messages omit the full `cwd` and event context by default so compact views
stay readable. Set `AGENT_NOTIFICATIONS_INCLUDE_CONTEXT=1` for debugging if that
context is needed. The legacy `CODEX_SLACK_INCLUDE_CONTEXT=1` name is still
accepted.

When `slack-bot-token` and `slack-channel-id` exist, the helper uses
`chat.postMessage` and stores the agent notification state in:

```text
~/.local/state/dotfiles/agent-notifications/slack-threads.json
~/.local/state/dotfiles/agent-notifications/codex-dedupe.json
~/.local/state/dotfiles/agent-notifications/slack.log
```

If the new state files do not exist, the Rust command reads the old
`~/.local/state/dotfiles/codex-slack-*` files once as fallback state and writes
future updates to the new `agent-notifications` paths.

Thread replies for actionable or terminal events include `<!channel>` by
default, but stay inside the Slack thread. Override the mention with
`AGENT_NOTIFICATIONS_REPLY_MENTION`, disable it with
`AGENT_NOTIFICATIONS_REPLY_MENTION=`, or limit event names with comma-separated
`AGENT_NOTIFICATIONS_REPLY_MENTION_EVENTS`. Set
`AGENT_NOTIFICATIONS_REPLY_BROADCAST=1` only when you intentionally want replies
to be reposted into the channel timeline. Legacy `CODEX_SLACK_*` names remain
fallbacks for those settings.

If setup testing returns `channel_not_found`, the Bot User OAuth token is valid
but the bot cannot see the target channel. Invite the Slack app or bot user to
that channel, add `chat:write.public` for public-channel posting without an
invite, or use a channel ID from the same workspace installation. Incoming
webhook fallback can keep notifications flowing, but it cannot create or update
the local `thread_ts` map; an empty `slack-threads.json` means thread mode has
not successfully posted through `chat.postMessage` yet.

When bot token and channel id are configured, the helper tries threaded Bot API
posting first. If Bot API posting fails, actionable and completion notifications
fall back to the incoming webhook; thread-parent events are skipped because a
webhook message cannot maintain the Codex-to-Slack thread map. Those Bot or
webhook failures are recorded in
`~/.local/state/dotfiles/agent-notifications/slack.log` without credential
values. Set `AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1` only when
you prefer hard failure over unthreaded best-effort notifications.

## Doom Emacs

`tools.editor.emacs.enable = true` installs the GUI Emacs app through Homebrew, installs the Doom/Meow sync tooling, and keeps `doom-meow` available under `~/.config/doom/modules/editor/meow`. Doom config files are writable runtime state reconciled by `sync emacs`; plain `sync emacs --check` and `sync emacs --apply` also verify that `${EMACSDIR:-~/.emacs.d}/bin/doom` is executable. Use `--config-only` only for tests or maintenance that intentionally reconciles the three config files without checking Doom runtime readiness.

`sync emacs --apply --bootstrap` first writes `~/.config/doom/{init,packages,config}.el` from the repo, then installs Doom non-interactively when `${EMACSDIR:-~/.emacs.d}/bin/doom` is missing or runs `doom sync` when it is already present. If `${EMACSDIR:-~/.emacs.d}` exists but is not a Doom checkout, the bootstrapper moves it to a timestamped `.pre-doom.*` backup before cloning Doom.

`tools.editor.emacs.bootstrap.enable = true` keeps the activation-time `dotfiles-doom bootstrap` path, backed by the same CLI behavior. The `ultra` profile enables both `tools.editor.emacs.sync.enable` and `tools.editor.emacs.bootstrap.enable`; `pro` installs Emacs without setup.

```bash
dotfiles-doom bootstrap
dotfiles-doom sync
dotfiles-doom doctor
```

## Neovim and Goneovim

`tools.editor.neovim.enable = true` installs Neovim. `tools.editor.neovim.sync.enable = true` wires the repo-managed LazyVim config from `apps/neovim/` and installs the external runtime helpers that config expects, including file pickers, LazyGit, Tree-sitter CLI, configured language servers and formatters, and document/image preview converters; `ultra` enables that setup and `pro` leaves it disabled. `tools.editor.goneovim.enable = true` installs the Goneovim GUI from the upstream Darwin release. This deliberately avoids the Homebrew cask because that cask depends on Homebrew `neovim`, is marked deprecated for macOS Gatekeeper validation, and is scheduled for disablement on 2026-09-01.

`nix run .#sync` is a convenience app for the personal editor setup. With no arguments it runs `sync emacs --apply --bootstrap` and then `sync neovim --apply`. Extra arguments are forwarded to both editor sync engines, so shared inspection flags such as `--check`, `--details`, and `--diff` work on both.

## Runtime overrides

- `HOME` is required for `nix run .#dotfiles -- sync shell ...`, `nix run .#dotfiles -- sync emacs ...`, `nix run .#dotfiles -- sync neovim ...`, and `nix run .#dotfiles -- sync vscode ...`, and it is also required whenever a command needs repo-default user-scoped paths.
- `DOTFILES_ROOT` overrides flake-root discovery for the Rust CLI and shell wrappers.
- `DOTFILES_PROFILE_DIRS` prepends colon-separated profile directories to shell profile discovery before `/etc/profiles/per-user/$USER` and `$HOME/.nix-profile`.
- `DOOMDIR` overrides the runtime Doom config directory for `sync emacs`; otherwise it defaults to `~/.config/doom`. Use `--doom-dir` for one command.
- `EMACSDIR` overrides the Doom checkout directory for `sync emacs`; otherwise it defaults to `~/.emacs.d`. Use `--emacs-dir` for one command.
- `FACTS_DIR` / `SECRETS_DIR` default to `~/.config/dotfiles`; `FACTS` / `SECRETS` default to `path:$FACTS_DIR` / `path:$SECRETS_DIR`.
- `DARWIN_REBUILD_BIN` overrides the pinned `darwin-rebuild` path used by `apply`.
- `DOTFILES_SYNC_VSCODE_BIN` overrides the `sync vscode` engine path.
- `XDG_CONFIG_HOME` and `XDG_STATE_HOME` affect the default Neovim runtime paths used by `sync neovim`; override them directly with `--runtime-dir` and `--state-dir` when testing.
- `VSCODE_CODE_BIN` overrides the `code` CLI path; `VSCODE_DATA_HOME`, `VSCODE_EXTENSIONS_DIR`, and `VSCODE_CODE_RETRIES` override VS Code runtime locations and retry behavior.
- `SOPS_AGE_KEY_FILE` overrides the bootstrap / doctor age-key location; otherwise those commands default to `~/.config/sops/age/keys.txt` when `HOME` is available.

Notes:

- `scripts/*.sh` are thin shell wrappers over the Rust CLI.
- `gc` first removes repo-local `result` / `result-*` symlinks that point into `/nix/store`, prunes stale legacy Home Manager profile links when the current Home Manager gcroot has superseded them, wipes non-current system, user, Home Manager, and root profile generations, then runs `nix store gc`. Without `--apply`, it reports the plan and runs safe dry-run checks. With `--apply`, it deletes all non-current profile generations by default; use `--delete-older-than <age>` to keep recent generations, or `--store-only` to skip profile history wiping.
- `sync neovim` compares `apps/neovim` against `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` and treats `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lazy-lock.json` as the effective Lazy lock when it exists.
- `dotfiles-sync-vscode` is packaged separately; `dotfiles` dispatches `sync vscode` to that binary.
- `ultra` runs VS Code, Neovim, and Emacs setup/sync during activation. `pro` installs editor tooling but leaves setup/sync disabled. Visual Studio Code.app itself is installed manually. Extension IDs to install live under `apps/vscode/` (`_default/extensions.txt` and per-profile `extensions.txt`).

## Checks and development

```bash
nix fmt
nix run .#format
nix flake check \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles
nix develop
```

## Clean export

`export-clean` is tracked-only and requires Git to access a trusted worktree. It fails closed if Git is unavailable or refuses the repository.

```bash
nix run .#dotfiles -- export-clean --format tar --output /tmp/dotfiles-clean.tar
nix run .#export-clean -- --format dir --output /tmp/dotfiles-clean
```

## Manual rebuild

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```
