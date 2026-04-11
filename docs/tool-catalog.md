# Tool Catalog & Toggles

This repository manages tool/group enablement under `myconfig.tools` using
`*.enable` toggles. Denix modules follow a simple rule: when `enable = true`,
the tool is installed/configured. For externally managed tools, `enable = true`
may configure the integration surface instead of installing the upstream binary.
Group toggles such as `tools.dev.enable` act as bundle switches for the
catalog-owned tools in that group.

`tools.aiCodingAgent.claudeCode.enable` is the current exception: it prepares
the native Claude Code PATH surface and `apply` advisories, while the actual
Claude Code binary is installed and updated by Anthropic's native installer.
Follow <https://code.claude.com/docs/en/quickstart> for current install steps,
then run `nix run .#apply -- --host <host>` and refresh with `exec zsh -l`.

## Toggle Rules

- Group: `myconfig.tools.<group>.enable`
- Tool: `myconfig.tools.<group>.<tool>.enable`

## Listing Tools (list-tools)

### Text Output

```bash
nix run .#list-tools -- --host pro_mac
nix run .#list-tools -- --host ultra_mac --rice base
```

### JSON Output

```bash
nix run .#list-tools -- --host pro_mac --format json
```

### Output Scope

`list-tools` only prints toggles at these depths:

- `group.enable`
- `group.tool.enable`

Deeper toggles such as `system.brewNix.autoDock.enable` or
`editor.vscode.sync.enable` are intentionally omitted.

### Environment Variables (Optional)

- `HOST` (default: none; required unless passed positionally)
- `RICE` (default: empty)
- `FORMAT` (`text` or `json`, default: `text`)
- `FACTS_DIR`, `SECRETS_DIR`
- `FACTS`, `SECRETS` (advanced overrides; default to `path:$FACTS_DIR` / `path:$SECRETS_DIR`)

## Implementation Notes

- Nixpkgs install catalog: `nix/modules/tools/catalog.nix`
- Nixpkgs install catalog data: `nix/catalog/tools/nixpkgs.nix`
- Homebrew install catalog: `nix/modules/tools/brew-catalog.nix`
- Homebrew ownership registry: `nix/catalog/tools/homebrew-ownership.nix`
- `nix run .#list-tools -- ...`
- `nix/scripts/list-tools.nix`

The toggle filtering logic lives in `list-tools.nix`, so both text and JSON
outputs are produced from the same filtered view.

`flake check` includes a final-config tool-ownership check. It fails when a
Darwin target contains the same `group.tool` key from multiple registries, when
its final Homebrew config contains a brew/cask/MAS item claimed by multiple
owners, when a Homebrew cask overlaps with `tools.system.brewNix`, or when an
item is not claimed by the ownership registry.
