# Tool Catalog & Toggles

This repository manages tool/group enablement under `myconfig.tools` using
`*.enable` toggles. Denix modules follow a simple rule: when `enable = true`,
the tool is installed/configured.
Group toggles such as `tools.dev.enable` act as bundle switches for the
catalog-owned tools in that group.

## Toggle Rules

- Group: `myconfig.tools.<group>.enable`
- Tool: `myconfig.tools.<group>.<tool>.enable`

## Listing Tools (list-tools)

### Text Output

```bash
nix run .#list-tools -- --host a2m_mac
nix run .#list-tools -- --host a2m_mac --rice minimum
```

### JSON Output

```bash
nix run .#list-tools -- --host a2m_mac --format json
```

### Output Scope

`list-tools` only prints toggles at these depths:

- `group.enable`
- `group.tool.enable`

Deeper toggles such as `system.brewNix.autoDock.enable` are intentionally omitted.

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
- Homebrew install catalog data: `nix/catalog/tools/homebrew.nix`
- `scripts/list-tools.sh`
- `nix/scripts/list-tools.nix`

The toggle filtering logic lives in `list-tools.nix`, so both text and JSON
outputs are produced from the same filtered view.

`flake check` includes a final-config tool-ownership check. It fails when a
Darwin target contains the same `group.tool` key from multiple sources, or when
its final Homebrew config contains a brew/cask/MAS item that is not claimed by
the ownership registry.
