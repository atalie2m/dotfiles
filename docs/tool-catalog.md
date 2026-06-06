[日本語版はこちら](ja/tool-catalog.md)

# Tool Catalog & Toggles

This repository manages tool/group enablement under `myconfig.tools` using
`*.enable` toggles. Repo modules follow a simple rule: when `enable = true`,
the tool is installed/configured. For externally managed tools, `enable = true`
may configure the integration surface instead of installing the upstream binary.
Group toggles such as `tools.dev.enable` act as bundle switches for the
catalog-owned tools in that group.

`tools.aiCodingAgent.claudeCode.enable` is catalog-backed through the
Homebrew-native backend and installs the latest-first `claude-code@latest`
cask during nix-darwin activation.
`tools.aiCodingAgent.headroom.enable` is a dedicated Home Manager integration
that installs `headroom`, `headroom-codex`, and `headroom-claude` wrappers.
Those wrappers resolve the latest `headroom-ai[proxy,code,mcp]` PyPI runtime
through Nix-provided `uv` and Python 3.13, and export `HEADROOM_TELEMETRY=off`.
Fast-moving macOS tools that are better owned by Homebrew, such as `git-xet`,
Apple project CLIs, and optional terminal fonts, use the same ownership
registry so `flake check` can still verify there is a single owner for each
brew/cask item.

The shell upgrade adds profile-oriented global groups for the Home Manager
cockpit: `shellUx`, `filesNavigation`, `viewersPreview`, `searchText`,
`gitPersonal`, `nixOperator`, `observability`, `network`, `xorg`,
`httpApiPersonal`, `downloadArchive`, `tuiWorkspace`, `dataPersonal`,
`containerK8sPersonal`, `securityPersonal`, `passwordSecrets`, `aiLlm`,
`modelHfPersonal`, `backupRecovery`, and `terminalVisual`.

The companion `tools.profileDefaults` module has no public toggle. It watches
those explicit tool toggles and writes matching default user configs for shell
UX, preview/search tools, Git/GitHub, Yazi, Zellij, K9s, observability TUIs,
terminal apps, AeroSpace, and Television. Secret-bearing operations such
as restic repositories, restic passwords, age recipients, and machine-specific
SSH keys stay outside the repo and must come from local mutable state.

## Toggle Rules

- Group: `myconfig.tools.<group>.enable`
- Tool: `myconfig.tools.<group>.<tool>.enable`

## Listing Tools (list-tools)

### Text Output

```bash
nix run .#list-tools -- --host own_mac
nix run .#list-tools -- --host work_mac --profile ultra
```

### JSON Output

```bash
nix run .#list-tools -- --host work_mac --profile ultra --format json
```

### Output Scope

`list-tools` only prints toggles at these depths:

- `group.enable`
- `group.tool.enable`

Deeper toggles such as `system.brewNix.autoDock.enable` or
`editor.vscode.sync.enable` are intentionally omitted.

### Environment Variables (Optional)

- `HOST` (default: none; required unless passed positionally)
- `PROFILE` (default: empty)
- `FORMAT` (`text` or `json`, default: `text`)
- `FACTS_DIR`, `SECRETS_DIR`
- `FACTS`, `SECRETS` (advanced overrides; default to `path:$FACTS_DIR` / `path:$SECRETS_DIR`)

## Implementation Notes

- Nixpkgs install catalog: `nix/modules/tools/catalog.nix`
- Nixpkgs install catalog data: `nix/catalog/tools/nixpkgs.nix`
- Repo-local package overlay: `nix/pkgs/overlay.nix`
- Homebrew install catalog: `nix/modules/tools/brew-catalog.nix`
- Homebrew ownership registry: `nix/catalog/tools/homebrew-ownership.nix`
- `nix run .#list-tools -- ...`
- `nix/scripts/list-tools.nix`

The toggle filtering logic lives in `list-tools.nix`, so both text and JSON
outputs are produced from the same filtered view.

## Work Host Policy

`work_mac` is not a separate profile taxonomy. It selects one of the stock
`minimal` / `lite` / `pro` / `ultra` profiles, merges host positive overrides,
then applies `nix/catalog/darwin/work-policy.nix` as forced-off policy data.
The policy helper flattens the actual `tools` toggles produced by profile plus
host data, so it covers groups defined by catalog modules as well as individual
modules such as `core`, `shell`, `dev`, `editor`, `system`, `terminal`,
`security`, and `aiCodingAgent`.

Policy denial is an install boundary, not only a PATH boundary. Registry-owned
Homebrew and brew-nix payloads are filtered against the final owner toggles, so
a denied cask/formula is removed from the final install plan instead of merely
being hidden from shell lookup.

`allowedGroups` is a group boundary. It is not a complete per-tool whitelist.
The current policy allows `dev` because stock Darwin profiles and host overrides
do not expose global opt-in toggles for project-pinned toolchains (`go`, `nodejs`,
`terraform`, `opentofu`). `bun` is the only explicit host opt-in exception. If
those toolchains return to stock profiles or host opt-ins later, they will also
flow into `work_mac`.

Broad groups need explicit review before widening:

- `system` is allowed for core macOS integration, but app/dev extras such as
  `latestApp`, `xcodesApp`, `swiftgen`, `sourcery`, `periphery`, and `carthage`
  are denied.
- `terminalVisual` and `securityPersonal` are denied. Remote access, scanner,
  packet-inspection, and personal security tools are not work-host defaults.
- GUI terminal/editor app installs such as `alacritty`, `ghostty`, `wezterm`,
  `rio`, `emacs-plus-app`, and `goneovim` are denied even though the broader
  `terminal` and `editor` groups remain available for CLI/editor support.
- `downloadArchive` and `passwordSecrets` are allowed with selected extras
  denied, so their policy remains readable and intentional.

Work policy also carries direct Homebrew/brew-nix payload denies for remote
desktop, screen sharing, VPN/tunnel, packet-inspection, and security-sensitive
app casks. This catches direct backend additions such as TeamViewer, AnyDesk,
RustDesk, Parsec, Wireshark, Burp Suite, Tailscale, or ngrok even if a future
toggle is accidentally placed in an allowed group.

Deep toggles such as `editor.emacs.sync.enable` are intentionally outside the
`list-tools` output; use direct `nix eval` checks for those policy assertions.
Use final-config evals for install payload assertions because `list-tools`
prints toggles, not Homebrew or Nix store payloads.

`flake check` includes a final-config tool-ownership check. It fails when a
Darwin target contains the same `group.tool` key from multiple registries, when
its final Homebrew config contains a brew/cask/MAS item claimed by multiple
owners, when a Homebrew cask overlaps with `tools.system.brewNix`, or when an
item is not claimed by the ownership registry.

`flake check` also validates that Nix catalog entries selected for the current
system resolve to packages available on that platform. Catalog entries may use
an internal unique key plus `tool = "name"` when the same package appears in
multiple profile groups.
