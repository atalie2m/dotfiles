[日本語版はこちら](docs/ja/README.md)

## Flake templates

This repository publishes project development templates that you can use via Nix flakes:

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
nix flake init -t github:atalie2m/dotfiles#rust-dev
nix flake init -t github:atalie2m/dotfiles#infra-iac
```

The templates share `flake-parts`, `treefmt-nix`, `git-hooks.nix`, `devenv`, `process-compose`, `direnv`/`nix-direnv`, `just`, common format/lint hooks, and security tooling. Project-specific examples include:

- `web-dev`: Node.js 22/corepack, pnpm, bun, deno, TypeScript, Workers/Netlify/Supabase tooling, redocly, project-pinned npm CLIs for Vite/Vitest/Storybook/Nx/OpenAPI/GraphQL/Drizzle/Vercel/Surge, AWS CLI v2, jq/yq, mkcert, and local service helpers.
- `rust-dev`: `rust-overlay` stable toolchain, rust-analyzer, cargo QA/release tools, C build deps, sqlite/protobuf.
- Additional templates: `go-dev`, `python-research`, `data-pipeline`, `native-dev`, `embedded-dev`, `apple-dev`, `infra-nixos`, `infra-iac`, `kubernetes-dev`, `container-oci`, `model-hf`, `docs-dev`, `api-db`, `ai-coding`, `release-dev`.

`web-dev`, `rust-dev`, and `go-dev` also include an `enabledProfiles` selector
for optional layers such as `api-db`, `docs`, `release`, `container-oci`,
`kubernetes`, `infra-iac`, `ai-coding`, `model-hf`, and `native-debug`.
Standalone templates remain available for repos where those layers are the main
purpose.

## Template source hygiene

Template-derived projects should be operated as Git flakes. From the repository
root, use `nix run .#...`, `nix build .#...`, `nix develop`, and
`nix flake check`; do not use unfiltered local path refs such as
`nix run path:$PWD#...` or `nix build path:$PWD#...`. `path:` refs can copy the
whole worktree into the Nix store, including `.git/`, `target/`,
`node_modules/`, and `.direnv/`.

Every template ships an `AGENTS.md`, `.gitignore`, a source evaluation
guard, and `checks.flake-source-hygiene`. Keep those in place, and use explicit
source filters such as `lib.cleanSourceWith`, `builtins.path`, or
`nix-gitignore` if a package or check consumes local project source.

# dotfiles

## Prerequisites

- Nix(Lix or Determinate's vanilla)

## Git Operating Model

This repository uses trunk-based development with PR-centered change
governance:

- `main`: normal protected integration line.
- `maint/<series>`: protected maintenance lines, only when needed.
- `stabilize/<train>`: short-lived hardening lines with an expiry.
- `svc/<principal-id>/**`: confinement namespace for an approved service
  principal.
- `dependabot/**`, `dependabot-*`, `dependabot_*`: vendor-controlled
  Dependabot refs.
- `gh-readonly-queue/**`: GitHub merge queue internals.
- everything else: human work branch with no naming convention.

Pull Requests are the change objects. Branch names are not authority; they are
not provenance, ownership, run IDs, dates, environments, producers, policy
lanes, issue types, or release targets. See
[`docs/git-branch-strategy.md`](docs/git-branch-strategy.md).

Do not install a general unattended task-agent credential for this repository.
Merge records desired userland configuration, but local activation remains a
deliberate operator action.

## Host Profiles

This flake uses self-contained catalogs for host/profile target management:

- `nix/catalog/darwin/{hosts.nix,bundles.nix,default.nix}`
- `nix/catalog/linux/{hosts.nix,profiles.nix,default.nix}`
- `nix/catalog/shared/{bundles.nix}` for portable profile bundles reused across platforms

Shared modules, tool catalogs, and operational scripts live alongside that catalog:

- `nix/modules/{shared,tools}`
- `nix/catalog/tools/{nixpkgs.nix,homebrew-ownership.nix}`
- `scripts/` for thin shell entrypoints and smoke tests
- `nix/scripts/` for Nix expressions used by the CLI

See [`docs/architecture.md`](docs/architecture.md) for the current responsibility split.
See [`docs/architecture-reset.md`](docs/architecture-reset.md) for the reset rationale, before/after changes, and design intent.

Operational note: the supported root flake API is Darwin-first and now also exposes a bounded Linux Home Manager target for the shared development workbench. The Linux target owns only interactive userland inside the LXC; `domus-ops` remains responsible for the LXC substrate, storage, Tailscale, SSH, observability, and lifecycle.

- Darwin hosts: `own_mac` (default profile: `pro`), `work_mac` (default profile: `pro`).
- Darwin profiles: `minimal`, `lite`, `pro`, `ultra`.
  - `minimal`: absolute essentials, currently Nix settings plus Git.
  - `lite`: practical daily baseline with shells, core CLI tools, navigation/search, Git, secrets basics, and macOS integrations.
  - `pro`: full global tool catalog and editor installation, with editor setup/sync disabled.
  - `ultra`: `pro` plus VS Code, Neovim, and Emacs setup/sync, and Codex Slack notifications.
- Linux Home Manager target: `linux_workbench` (default profile: `workbench`), plus `linux_workbench-minimal`.

Canonical host names and CLI examples live in [`docs/commands.md`](docs/commands.md).

Manual attribute examples:
`own_mac`, `own_mac-minimal`, `own_mac-lite`, `own_mac-ultra`, `work_mac`, `work_mac-minimal`, `work_mac-lite`, `work_mac-ultra`, `linux_workbench`, `linux_workbench-minimal`.

When `--profile` is provided, the CLI resolves only `host-profile` (no implicit fallback to `host`).
For `work_mac`, the selected profile is capped by the work policy after profile and host overrides merge. For example, `work_mac --profile ultra` means "ultra with the work policy forced off," not a separate `works` profile.

The Linux workbench target derives username, home directory, and machine values
from local facts through `myconfig.hostContext`; the target key does not need to
match the live LXC hostname. Build it with
`nix build .#homeConfigurations.linux_workbench.activationPackage` and switch on
the LXC with `home-manager switch --flake .#linux_workbench`. Codex CLI is not
managed by this profile; use `codex --version` after switch to verify the
standalone upstream installer remains first on the live host.

## Application Source Policy

Application/tool sourcing priority is:

- Detailed policy: [`docs/homebrew-policy.md`](docs/homebrew-policy.md)

1. Use Nix packages by default for CLI tools and libraries.
2. Use Homebrew for macOS-specific or intentionally latest-first software, preferably through catalog-backed `myconfig.tools` toggles.
3. Use `tools.system.brewNix` only when native Homebrew integration is the wrong fit and a pinned cask path is needed.
4. Homebrew backend lists are internal implementation detail; `flake check` validates the unified ownership registry, duplicate item claims, cross-source overlaps, and unregistered items.

`Claude Code` is managed as a latest-first Homebrew cask through the
catalog-backed `tools.aiCodingAgent.claudeCode` toggle. Enabling it adds the
`claude-code@latest` cask to the nix-darwin Homebrew activation.
`Herdr` is managed through the catalog-backed
`tools.aiCodingAgent.herdr` toggle and installs the upstream Nix flake package
pinned by this repository.
`ultra` also enables `tools.aiCodingAgent.headroom`, which installs
telemetry-off `uv` wrappers for Headroom's PyPI runtime:
`headroom`, `headroom-codex`, and `headroom-claude`.

## Agent Slack Notifications

`dotfiles agent-notify codex` posts Codex lifecycle notifications to Slack
without storing Slack credentials in Git or in `~/.codex/config.toml`.
`scripts/codex-slack-notification` remains as a compatibility shim for existing
Codex hook configs, but the implementation now lives in the Rust control plane.
The stock profile toggle for this runtime is
`tools.aiCodingAgent.codex.slackNotifications.enable`; it is enabled by
`ultra`, not `pro`.
Store a Bot User OAuth token and channel ID under
`~/.config/dotfiles/files/agent-notifications/` to link each Codex thread to a
Slack thread. The old `~/.config/dotfiles/files/codex/` credential files remain
as fallback inputs.
For notification-runtime-only updates, use `nix run .#agent-notifications-update`.
That refreshes the user-profile `dotfiles` binary preferred by
`scripts/codex-slack-notification` without running a Darwin/Home Manager switch.

The Rust implementation keeps Codex-specific parsing in the Codex adapter and
keeps Slack as a generic sink. The adapter turns hook and transcript records
into typed agent events, while the Slack sink owns formatting, Bot API and
webhook transport, thread state, fallback, and error logging. A lightweight
transcript watcher creates or updates the Slack parent from Codex
`thread_name_updated`, catches Plan Mode `request_user_input`, and posts
completion replies from the exact session transcript. `request_user_input`
records that Codex auto-resolves outside Plan Mode are skipped. The watcher also
follows Codex `guardian_assessment` records for approval waits, delays pending
approvals through the auto-review window, and skips requests approved
automatically. Actionable replies mention `<!channel>` by default but stay
inside the Slack thread.

Setup and test commands live in [`docs/commands.md`](docs/commands.md#codex-slack-notifications).
Secret storage details live in [`docs/secrets-local.md`](docs/secrets-local.md#codex-slack-notifications).

## Repository-Scoped Toolchain Policy

1. `terraform`, `opentofu`, `nodejs`, and `go` must be pinned per repository via that repo's own `flake.nix` / devShell.
2. Stock host profiles and overrides do not expose global opt-in toggles for `go`, `nodejs`, `opentofu`, or `terraform`; keep them in project templates/devShells so one machine-wide version does not leak across repos.
3. `bun` is the only project-pinned toolchain exception that may be enabled explicitly with `myconfig.tools.dev.bun.enable = true`; do not add it back to stock profiles.
4. The `work_mac` policy allows the `dev` group on the premise that project-pinned toolchains are not exposed through stock profiles or host opt-ins, except for the explicit `bun` exception.
5. Terraform remains unfree. Repository flakes that need it must set their own unfree allow-list; `allowAll` remains disabled here.
6. For Terraform/OpenTofu repos, set `nixpkgs.config.allowUnfreePredicate` in that repo's flake and include `pkgs.terraform` / `pkgs.opentofu` in the devShell.

Example (`flake.nix` for a Terraform repo):

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs = { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.terraform pkgs.opentofu ];
      };
    };
}
```

## Tool Catalog (myconfig.tools)

Group toggles such as `tools.dev.enable` are bundle switches, not just namespaces. Enabling a group fans out to the catalog-owned tool toggles under that group.
Use `list-tools` for single host/profile inspection and `matrix-tools` for cross-target matrices. `matrix-tools` shows group-level toggles by default and can expand to deeper toggles with `--full`; see [`docs/tool-catalog.md`](docs/tool-catalog.md) for catalog scope and [`docs/commands.md`](docs/commands.md) for CLI examples.

Manual evaluation (JSON):

```bash
nix eval --json .#darwinConfigurations.work_mac-ultra.config.myconfig.tools
```

## Work Host Policy

`nix/catalog/darwin/work-policy.nix` is the allow boundary for `work_mac`.
The helper applies after selected profile data and host positive overrides, and emits `mkForce false` overrides for disallowed groups/tools and editor sync/bootstrap toggles.
Registry-owned Homebrew and brew-nix payloads are filtered against the final
owner toggles, so a policy-denied cask/formula is not left in the install plan
as a direct store or Homebrew target.

- Denied personal or high-surface groups include `aiLlm.*`, `aiCodingAgent.*`, `modelHfPersonal.*`, `backupRecovery.*`, `observability.*`, `securityPersonal.*`, and `terminalVisual.*`.
- `downloadArchive` and `passwordSecrets` are allowed groups with specific extras denied (`ffmpeg`, `p7zip`, `pigz`, `zstd`, `op`, YubiKey age plugin, and ssh-to-age).
- `system` is allowed so core macOS integration can still run, but app/dev extras such as `latestApp`, `xcodesApp`, `swiftgen`, `sourcery`, `periphery`, and `carthage` are denied. Treat group allow-lists as group boundaries, not a complete tool-level whitelist.
- GUI terminal/editor app installs (`alacritty`, `ghostty`, `wezterm`, `rio`, `emacs-plus-app`, `goneovim`) are denied on work hosts; use company-approved apps or unmanaged local state instead.
- Remote desktop, screen sharing, VPN/tunnel, packet-inspection, and security-sensitive app casks are denied by payload name as well, so direct Homebrew/brew-nix additions such as TeamViewer, AnyDesk, RustDesk, Parsec, Wireshark, Burp Suite, Tailscale, or ngrok do not land on `work_mac`.

## VS Code Profiles

This repo targets a single VS Code app with native VS Code profiles.
The declarative source stays under `apps/vscode/<name>/`, and runtime materialization happens through `sync vscode`.

- `apps/vscode/_default/` is the shared layer applied to every managed profile.
- `apps/vscode/native/` is managed as a native profile (`Native`).
- `apps/vscode/<name>/` for any other name maps to a native custom profile with that display name.
- Supported inputs are `settings.json`, `extensions.txt`, and bootstrap-only `default-disabled-extensions.txt`.
- `tools.editor.vscode.enable` installs `dotfiles-sync-vscode` into Home Manager. Visual Studio Code.app is installed manually.
- `sync emacs`, `sync neovim`, and `sync shell` use Rust engines in `dotfiles-core`; `sync vscode` uses the dedicated Rust engine (`dotfiles-sync-vscode`).
- **Stock `ultra` behavior:** the `ultra` profile enables activation-time VS Code profile sync. The `pro` profile installs the sync surface but leaves setup/sync disabled.
- **Extension bulk install:** repo-owned extension IDs live under `apps/vscode/` — chiefly `_default/extensions.txt` plus each profile's `extensions.txt` (for example `web/`, `native/`). That directory is the source of truth for what sync installs or uninstalls.
- VS Code built-in extensions are intentionally omitted from `extensions.txt`; they track the app bundle version and should not be installed from Marketplace during sync.
- `sync vscode --apply` reconciles fully repo-owned managed profile settings plus those repo-owned extensions into writable VS Code profile state when you invoke the CLI.
- `default-disabled-extensions.txt` is seeded once into the profile's extension enablement state; users can later enable those extensions in the VS Code UI and sync will not force them back off.
- Drift management is mutable by design: managed profile settings are fully repo-owned, while repo-owned extensions converge without adopting user-added extensions.

See `docs/vscode.md` for the runtime model and CLI.
See [`docs/reconciled-surfaces.md`](docs/reconciled-surfaces.md) for mutable vs immutable boundary details across shell, editor, VS Code, and system app surfaces.

## Mutable Editor Tooling

- Emacs app wiring is Nix-first, while package state stays mutable. `sync emacs` reconciles `apps/emacs/config/{early-init,init}.el` with writable files under `${EMACSDIR:-~/.emacs.d}`. The repo-managed config is a vanilla Emacs setup centered on Meow, Elpaca, Vertico/Consult/Orderless/Embark, Corfu/Cape/Eglot, Dired, Org visual packages, Popper, Dashboard, and Magit. The `ultra` profile runs activation-time Emacs sync; `pro` installs Emacs without setup.
- Neovim installation is separate from config setup. `tools.editor.neovim.enable` installs Neovim, while `tools.editor.neovim.sync.enable` wires the repo-managed LazyVim config from `apps/neovim/` and installs the external runtime helpers that config expects. The `ultra` profile enables that setup; `pro` only installs the editor.
- VS Code profile definitions are declarative, but runtime state stays writable; managed profile settings are fully repo-owned and manual settings changes are overwritten on apply, while user-added extensions remain outside repo ownership.
- This repo treats those editor runtimes as a convenience boundary: config and declared runtime helpers are pinned here, while plugin/login/UI state is not.

## Terminal Compatibility

Any modern terminal works with the current Zsh setup. Terminal.app profile sync has been removed from this repo, so Terminal.app is just an unmanaged fallback.

**Recommended terminals:**

- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

## Zsh Stack

The default Zsh prompt is Pure. Zsh has a managed profile switch at `tools.shell.zsh.profile`:

- `stable`: `fzf-tab`, `zsh-autosuggestions`, `fast-syntax-highlighting`, `zsh-vi-mode`, `zsh-autopair`, `zsh-completions`, `carapace`, and `nix-zsh-completions`.
- `autocomplete`: uses `zsh-autocomplete` as the completion UI and disables `fzf-tab` as the Tab owner.
- `debug`: loads the stable profile plus `zprof`, `bindkey`, and `zinit` timing/report output.

Mosh sessions keep SSH bootstrap metadata, but the Pure prompt hides the remote `user@host` prefix for Mosh only.

`lite`, `pro`, and `ultra` carry the daily shell stack; `minimal` keeps only the absolute essentials:

- `fzf` keybindings: `CTRL-T` for file insert, `ALT-C` for directory jump
- `fzf-tab` on `TAB`
- `Atuin`-backed contextual history on `CTRL-R`: current directory first, then workspace, parent directories, and global history
- terminal tab titles show the current directory at prompts and the running command during execution
- `CTRL-X CTRL-E` edits the current command line in `$VISUAL` / `$EDITOR`
- `zoxide` via `z` and `zi`
- `direnv` + `nix-direnv`
- `delta` for Git paging
- profile groups such as `shellUx`, `filesNavigation`, `gitPersonal`, `nixOperator`, `observability`, `network`, `xorg`, `dataPersonal`, `securityPersonal`, `passwordSecrets`, `aiLlm`, `backupRecovery`, and `presentation`

`tools.profileDefaults` writes repo-owned defaults for `fzf`, `direnv`,
`gh-dash`, `yazi`, `zellij`, `k9s`, `television`, terminal apps,
observability tools, preview tools, and search tools when their catalog toggles
are enabled.
The stock catalog also installs workflow helpers such as `ghq`, `roots`,
`ast-grep`, `sad`, `git-sizer`, `git-town`, `kondo`, `typos`, `taplo`, `actionlint`,
`shellcheck`, `shfmt`, `yamllint`, `deadnix`, `statix`, `nix-diff`, `lychee`,
`jless`, `mprocs`, and X.Org utilities such as `luit`, `xauth`, and `xprop`.
Git config sets `ghq.root` to `~/src`, so `ghq get` places repositories under
paths such as `~/src/github.com/<owner>/<repo>`. The repo-capsule `.bare` plus
linked-worktree layout is an operator workflow layered on top of that root, not
something `ghq` enforces.

### Shell sync (writable entrypoints)

Shell sync is a small, stateless writable-entrypoint manager.
Runtime sync operations are implemented through `nix run .#dotfiles -- sync shell`; `scripts/sync.sh` is only a thin shell wrapper over the Rust `dotfiles` CLI.
Its job is to keep writable shell entrypoints in place and update only repo-managed blocks/files.
Shared shell helpers are shipped separately as `apps/shell/common.sh` and linked to `~/.config/shell/common.sh`; the repo's `scripts/` directory is also added to `PATH` when shell tooling is enabled. Home Manager session PATH also includes the active user profile bins so non-interactive remote commands, such as SSH-started `mosh-server`, can resolve profile-installed tools. Both are declarative Home Manager content, not part of runtime sync state.

- Desired source:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
- Local targets:
  - `~/.nix/.zshrc` (managed block only; runtime ZDOTDIR entrypoint)
  - `~/.bashrc` (managed block only; runtime bash entrypoint)
- Local extension points:
  - zsh: `~/.config/shell/zsh.local.sh`
  - bash: `~/.config/shell/bash.local.sh`
- `sync shell` manages only the declared targets above.
- `sync shell --apply` automatically normalizes common entrypoint shapes:
  - missing files
  - writable regular files
  - `/nix/store/...` symlinks
  - readable non-store symlinks, which are materialized back into writable regular files
- Content outside the managed markers is preserved.
- Shell sync does not keep machine-local `lastApplied` state and does not adopt local changes back into the repo.
- Managed macOS login-shell switching supports `zsh` and `bash`.

Managed block markers:

```bash
# >>> dotfiles-managed:bashrc >>>
# ... managed content ...
# <<< dotfiles-managed:bashrc <<<
```

Workflow:

```bash
# 1) Check whether any target needs apply
nix run .#dotfiles -- sync shell --check

# Optional: show details or a managed-content diff
nix run .#dotfiles -- sync shell --check --details
nix run .#dotfiles -- sync shell --check --details --diff

# 2) Repair or create writable entrypoints in place
nix run .#dotfiles -- sync shell --apply

# Optional: restrict to one shell group or one target
nix run .#dotfiles -- sync shell --apply --group zsh
nix run .#dotfiles -- sync shell --check --item bash-rc

```

`nix run .#apply -- --host <host>` triggers shell reconciliation during Home Manager activation by running `sync shell --apply` for the enabled shell groups.

Shell entrypoint writeability regression tests (isolated + auto cleanup):

```bash
scripts/tests/shell-zsh-writeability-test.sh
```

These test scripts use a temporary `HOME` and remove all test files on exit.

Additional sync tests:

```bash
scripts/tests/sync-cli-common-parse-test.sh
scripts/tests/sync-shell-smoke-test.sh
scripts/tests/sync-emacs-smoke-test.sh
scripts/tests/sync-neovim-smoke-test.sh
scripts/tests/sync-vscode-smoke-test.sh
scripts/tests/work-policy-test.sh
```

## Local Facts + Secrets (Override Inputs)

This repo no longer uses Git clean/smudge filters. Machine-specific facts and secrets live outside Git and are injected at build time using flake overrides.
Both inputs default to `~/.config/dotfiles/` (store `facts.nix` and `secrets.nix` side-by-side).

Default layout:

```
~/.config/dotfiles/
├── facts.nix
├── runtime.nix    # generated by apply
├── secrets.nix
├── .sops.yaml
└── files/
    └── ai.env.sops.yaml
```

### Facts (non-secret)

- Create `~/.config/dotfiles/facts.nix`
- Required: `user.username`
- Recommended for Git identity: `user.git.fullName`, `user.git.email`
- Optional for Git signing: `user.git.signingKey` (OpenPGP key ID or fingerprint; not a secret). When set, the Git module enables OpenPGP signing and pins `gpg.program` to the Nix-managed GnuPG binary.
- Optional overrides: `user.homeDirectory` (auto-derived) and `machines.<host>.homeDirectory` (per-host override when you truly need it).
- Optional host input metadata: `machines.<host>.keyboardType = "ansi" | "jis"` for input-device-specific Karabiner behavior.
- Platform is no longer a raw facts input. Host declarations own `system`, and modules derive `os`/`arch` from `myconfig.hostContext`.

Example `facts.nix`:

```nix
{
  user = {
    username = "yourname";

    git = {
      # Recommended (used by Git module)
      fullName = "Your Name";
      email = "you@example.com";
      # signingKey = "OPENPGP_KEY_ID_OR_FINGERPRINT";
    };

    # Optional overrides
    # homeDirectory = "/path/to/home/yourname";

    stateVersion = {
      home = "25.11";
      darwin = 6;
    };
  };

  machines = {
    own_mac = {
      computerName = "Your Mac";
      localHostName = "your-mac";
      hostName = "your-mac";
      keyboardType = "ansi";
    };

    # Optional if you also use the work_mac target:
    # work_mac = {
    #   computerName = "Your Mac";
    #   localHostName = "your-mac";
    #   hostName = "your-mac";
    #   keyboardType = "jis";
    # };
  };
}
```

These machine values are used to set macOS system naming via `tools.system.hostnames`.
`runtime.nix` is generated by `apply` for non-secret machine observations such as whether the active developer directory is a full Xcode.app.

### Secrets (confidential)

- Create `~/.config/dotfiles/secrets.nix`
- Store encrypted files under `~/.config/dotfiles/files/` (sops+age recommended)
- Define `secrets.nix` and encrypted files (sops+age recommended)
- Detailed setup notes: [`docs/secrets-local.md`](docs/secrets-local.md)

Example `secrets.nix`:

```nix
{
  files = {
    aiEnv = {
      sopsFile = ./files/ai.env.sops.yaml;
      targetPath = ".config/dotfiles/ai.env";
      mode = "0600";
    };
  };
}
```

Optional shell sourcing:

- zsh: `~/.config/shell/zsh.local.sh`
- bash: `~/.config/shell/bash.local.sh`

Example (`~/.config/shell/zsh.local.sh`):

```bash
if [ -f "$HOME/.config/dotfiles/ai.env" ]; then
  source "$HOME/.config/dotfiles/ai.env"
fi
```

### Build with overrides

All `nix run .#apply|.#update|.#doctor|.#bootstrap|.#list-tools|.#matrix-tools` commands derive `FACTS` and `SECRETS` from `FACTS_DIR` and `SECRETS_DIR` automatically. Manual invocations still need explicit overrides:

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- build --flake .#own_mac \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```

`nix run .#darwin-rebuild -- ...` uses the nix-darwin wrapper pinned by this repo's `flake.lock`.

**Note**: The repo ships placeholder public facts under `nix/local/`, and the default secrets input is intentionally inert so `darwinConfigurations` still evaluates without in-repo secrets. Real machines should still override both inputs with `~/.config/dotfiles/`. Existing local facts should migrate `machines.<key>` to `own_mac` / `work_mac`; the host catalog `machineKey` values use the same names.

## Binary Cache (Cachix / Attic)

This repo can pull from extra binary caches via your local facts.

Add to `~/.config/dotfiles/facts.nix`:

```nix
{
  binaryCaches = {
    substituters = [
      "https://your-cache.cachix.org"
      # "https://attic.example.org/your-cache"
    ];
    trustedPublicKeys = [
      "your-cache.cachix.org-1:REPLACE_WITH_PUBLIC_KEY"
      # "attic.example.org-1:REPLACE_WITH_PUBLIC_KEY"
    ];
  };
}
```

CI cache pushes are wired for Cachix. Set these in the GitHub repo:

- `CACHIX_CACHE_NAME` (repository variable)
- `CACHIX_AUTH_TOKEN` (repository secret, write-enabled)

Once set, the macOS CI job evaluates every `darwinConfigurations` target and builds each host's default target plus one deterministic non-default profile target before pushing results to the cache.

## Flake Config Trust (`accept-flake-config`)

This repo defaults `system.nix.acceptFlakeConfig = true` for convenience, so flake-level `nixConfig` is applied automatically.

Tradeoff:

- Pros: smoother day-to-day usage for this dotfiles flake (fewer manual flags).
- Cons: evaluating unknown third-party flakes can apply their `nixConfig` (for example cache/substituter settings).

If you want stricter behavior, disable it in your host/profile config:

```nix
{
  myconfig.system.nix.acceptFlakeConfig = false;
}
```

## Karabiner-Elements Setup

This repository includes comprehensive keyboard layouts and input method configurations for Karabiner-Elements in the `keyboards/karabiner/complex_modifications/` directory.

### Available Configurations

1. **japanese-input-toggle.json**: Japanese input method switching configurations

   - Command/Control/Option/Shift keys for 英数・かな switching
   - Caps Lock toggle functionality
   - Vim-friendly ESC key behavior
   - Based on KE-complex_modifications

2. **spacebar-to-shift.json**: Space-and-Shift (SandS) functionality

   - Spacebar acts as Left Shift when held with other keys
   - Normal space character when pressed alone
   - Based on KE-complex_modifications

3. **vylet-alt-layout.json**: Vylet alternative keyboard layout

   - Complete keyboard layout remapping
   - Created by MightyAcas
   - Optimized for efficient typing

4. **shingeta_en.json**: 新下駄配列 (Shingeta layout) for English typing games

   - Japanese keyboard layout optimized for typing games
   - Created by kouy, implemented by funatsufumiya

5. **shingeta_jp.json**: 新下駄配列 (Shingeta layout) for Japanese input
   - Full Japanese input support
   - Same layout as above but for general Japanese typing

### Declarative Setup

If `tools.system.karabiner.enable = true`, dotfiles manages Karabiner-Elements settings as one feature. It does not install Karabiner-Elements; install the app outside this repository if needed.

The configuration is managed in `nix/modules/tools/system/karabiner.nix` and will automatically:

1. Create the necessary directories
2. Generate symbolic links for the managed rule files and `karabiner.json`
3. Keep the links updated when you rebuild your configuration

Keyboard hardware differences stay in host facts:

```nix
{
  machines.own_mac.keyboardType = "ansi";
  # or "jis"
}
```

**Configuration details:**

- Configuration files are sourced from the `keyboards/` directory in this repo
- The linked complex-modification set comes from the explicit `ruleFiles` list in the module
- The generated `karabiner.json` uses `machines.<host>.keyboardType` when set and falls back to `ansi`
- Changes take effect after running `nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME>`

### Credits

These configurations are based on or include work from:

- **KE-complex_modifications** (Unlicense)
- **Shingeta Layout** by kouy and funatsufumiya (MIT License)
- **Vylet Keyboard Layout** by MightyAcas

See the LICENSE file for complete attribution information.

# Usage

## CLI (recommended)

All CLI commands automatically append:
`--override-input local "$FACTS"` and `--override-input secrets "$SECRETS"`.

Most operational CLI commands are Darwin-first: they target `darwinConfigurations` and macOS-specific checks/builds.
`agent-notify` is local runtime tooling for coding-agent Slack notifications.
`apply` and `list-tools` require `--host`, a positional host, or `HOST=...`.
`matrix-tools` evaluates all available `darwinConfigurations` and does not require `--host`.
`update` only requires a host when build is enabled (the default).
`bootstrap` only requires a host when `--apply` or `--yes` is used.

Defaults:

- `FACTS_DIR=$HOME/.config/dotfiles`
- `SECRETS_DIR=$HOME/.config/dotfiles`
- `FACTS=path:$FACTS_DIR`
- `SECRETS=path:$SECRETS_DIR`

Advanced overrides:

- `FACTS` and `SECRETS` may point to other flake input references when needed.
- `doctor` and `bootstrap` still require matching `FACTS_DIR` / `SECRETS_DIR` when those overrides are not `path:...`, because they read or write local files directly.
- `HOME` is required for `sync shell`, `sync emacs`, `sync neovim`, `sync vscode`, and any command that needs default user-scoped paths.

Runtime override details live in [`docs/commands.md`](docs/commands.md#runtime-overrides).

Canonical command examples live in [`docs/commands.md`](docs/commands.md).

### Bootstrap (first run)

`bootstrap` creates a minimal `facts.nix` with required `user.username`, optional identity fields, and commented optional machine/stateVersion examples.

### Doctor (health checks)

`doctor` can run without a host for global facts/secrets/basic system checks.
For target evaluation and strict sync checks, pass `--host` so `doctor` can gate checks by target tool enablement.

### Apply (build/switch)

### Update (flake inputs + checks/build)

`self-update` refreshes the installed dotfiles CLI/runtime from the current
checkout. It upgrades an existing `dotfiles` entry in the default user Nix
profile when present, then runs the canonical Darwin/Home Manager apply path so
`/etc/profiles/per-user/$USER/bin/dotfiles` is updated too. Use it for Rust CLI
changes such as the coding-agent notification runtime:

```bash
nix run .#self-update -- --host own_mac
```

### GC (repo-scoped Nix store cleanup)

`gc` removes repo-local `result` / `result-*` symlinks that point into `/nix/store`, prunes stale legacy Home Manager profile links when the current Home Manager gcroot has superseded them, wipes non-current system/user/Home Manager/root profile generations, then runs Nix garbage collection. It defaults to a dry run; use `sudo -v` and then `nix run .#gc -- --apply` to delete every non-current profile generation and collect unreachable store paths. Add `--delete-older-than <age>` to keep recent generations, or `--store-only` to skip profile history cleanup.

### Formatter / Checks / Dev Shell

### Clean export

`export-clean` is tracked-only and requires Git to access a trusted worktree. It fails closed if Git is unavailable or refuses the repository; see [`docs/commands.md`](docs/commands.md) for examples.

## Manual commands (darwin-rebuild)

Manual rebuild examples live in [`docs/commands.md`](docs/commands.md).

## Troubleshooting

- **`no darwinConfigurations found` / `unable to evaluate darwinConfigurations`** → Verify your overridden `facts.nix` and `secrets.nix`, then rerun `nix run .#doctor`.
- **`target not found for host/profile`** → Run `nix run .#doctor -- --host <host> --profile <profile>` to see available targets.
- **`FACTS_DIR is required ...` / `SECRETS_DIR is required ...`** → `doctor` and `bootstrap` need local file paths. If you override `FACTS` or `SECRETS` with a non-`path:` ref, also set the matching `*_DIR` variable.
- **`HOME is not set`** → `sync shell`, `sync emacs`, `sync neovim`, `sync vscode`, and default user-scoped runtime paths require `HOME`. Export it, or provide the explicit overrides documented in [`docs/commands.md`](docs/commands.md#runtime-overrides).
- **`darwin-rebuild: command not found`** → Use `nix run .#darwin-rebuild -- ...` for manual runs; `nix run .#apply` and `nix run .#update` already use the pinned wrapper automatically.
- **`error: unrecognised flag '--flake'`** → Ensure you invoke `nix run <flake>#<pkg> -- <cmd>`. Everything after `--` is passed through to `darwin-rebuild`.
- **Using `sudo`** → macOS resets `PATH` under `sudo`; `nix run .#apply` preserves `PATH` plus the dotfiles input override variables it needs, while manual runs should use the pinned wrapper via `nix run .#darwin-rebuild -- ...`.
