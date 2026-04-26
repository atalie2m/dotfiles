[English version](../tool-catalog.md)

# Tool Catalog と Toggle

このリポジトリは `myconfig.tools` 配下の `*.enable` toggle を使って tool / group の enablement を管理します。Denix module は単純な規則に従います。`enable = true` なら、その tool は install / configure されます。external 管理の tool では、`enable = true` が upstream binary の install ではなく integration surface の設定を意味することがあります。`tools.dev.enable` のような group toggle は、その group に属する catalog-owned tool の bundle switch として機能します。

`tools.aiCodingAgent.claudeCode.enable` は Homebrew-native backend の catalog-backed toggle です。nix-darwin activation 時に latest-first の `claude-code@latest` cask を install します。
`git-xet`、Apple project CLI、optional terminal font のように Homebrew 管理が適した macOS tool も同じ ownership registry に載せ、`flake check` が brew / cask item ごとの owner 一意性を検証できるようにしています。

shell upgrade では Home Manager cockpit 向けの profile group として
`shellUx`, `filesNavigation`, `viewersPreview`, `searchText`, `gitPersonal`,
`nixOperator`, `observability`, `network`, `httpApiPersonal`,
`downloadArchive`, `tuiWorkspace`, `dataPersonal`, `containerK8sPersonal`,
`securityPersonal`, `passwordSecrets`, `aiLlm`, `modelHfPersonal`,
`backupRecovery`, `terminalVisual` を追加しています。

補助の `tools.profileDefaults` module には public toggle を置きません。明示的な
tool toggle を見て、shell UX、preview/search tool、Git/GitHub、observability
TUI、terminal app、AeroSpace に加えて、Yazi、Zellij、K9s、Television の
default user config を書きます。restic repository、restic password、age recipient、
machine-specific SSH key のような secret-bearing operation は repo に入れず、
local mutable state から与えます。

## toggle ルール

- Group: `myconfig.tools.<group>.enable`
- Tool: `myconfig.tools.<group>.<tool>.enable`

## tool 一覧の表示（list-tools）

### text 出力

```bash
nix run .#list-tools -- --host pro_mac
nix run .#list-tools -- --host ultra_mac --rice base
```

### JSON 出力

```bash
nix run .#list-tools -- --host pro_mac --format json
```

### 出力範囲

`list-tools` が出力する toggle は次の深さに限定されます。

- `group.enable`
- `group.tool.enable`

`system.brewNix.autoDock.enable` や `editor.vscode.sync.enable` のような、より深い toggle は意図的に除外されています。

### 環境変数（任意）

- `HOST`（default: なし。位置引数で渡さない場合は必須）
- `RICE`（default: 空）
- `FORMAT`（`text` または `json`。default: `text`）
- `FACTS_DIR`, `SECRETS_DIR`
- `FACTS`, `SECRETS`（高度な override。default は `path:$FACTS_DIR` / `path:$SECRETS_DIR`）

## 実装メモ

- Nixpkgs install catalog: `nix/modules/tools/catalog.nix`
- Nixpkgs install catalog data: `nix/catalog/tools/nixpkgs.nix`
- Homebrew install catalog: `nix/modules/tools/brew-catalog.nix`
- Homebrew ownership registry: `nix/catalog/tools/homebrew-ownership.nix`
- `nix run .#list-tools -- ...`
- `nix/scripts/list-tools.nix`

toggle filtering logic は `list-tools.nix` にあるため、text 出力と JSON 出力は同じ filtered view から生成されます。

`flake check` には final-config tool-ownership check が含まれます。Darwin target に同じ `group.tool` key が複数 registry から現れる場合、最終 Homebrew config に複数 owner が claim する brew / cask / MAS item が含まれる場合、Homebrew cask が `tools.system.brewNix` と重複する場合、または ownership registry に claim されていない item がある場合に fail します。

`flake check` は、current system 向けの Nix catalog entry がその platform で利用可能な package に解決できることも検証します。同じ package を複数 profile group で使う場合、catalog entry は内部用の unique key と `tool = "name"` を併用できます。
