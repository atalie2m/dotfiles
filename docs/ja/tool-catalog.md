[English version](../tool-catalog.md)

# Tool Catalog と Toggle

このリポジトリは `myconfig.tools` 配下の `*.enable` toggle を使って tool / group の enablement を管理します。repo module は単純な規則に従います。`enable = true` なら、その tool は install / configure されます。external 管理の tool では、`enable = true` が upstream binary の install ではなく integration surface の設定を意味することがあります。`tools.dev.enable` のような group toggle は、その group に属する catalog-owned tool の bundle switch として機能します。

`tools.aiCodingAgent.claudeCode.enable` は Homebrew-native backend の catalog-backed toggle です。nix-darwin activation 時に latest-first の `claude-code@latest` cask を install します。
`tools.aiCodingAgent.herdr.enable` は専用の Home Manager integration で、
この repo で pin した upstream Nix flake から Herdr を install します。
`tools.aiCodingAgent.headroom.enable` は専用の Home Manager integration で、
`headroom`, `headroom-codex`, `headroom-claude` wrapper を install します。
これらの wrapper は Nix が提供する `uv` と Python 3.13 で latest の
`headroom-ai[proxy,code,mcp]` PyPI runtime を解決し、`HEADROOM_TELEMETRY=off`
を export します。
`git-xet`、Apple project CLI、optional terminal font のように Homebrew 管理が適した macOS tool も同じ ownership registry に載せ、`flake check` が brew / cask item ごとの owner 一意性を検証できるようにしています。

shell upgrade では Home Manager cockpit 向けの profile group として
`shellUx`, `filesNavigation`, `viewersPreview`, `searchText`, `gitPersonal`,
`nixOperator`, `observability`, `network`, `xorg`, `httpApiPersonal`,
`downloadArchive`, `tuiWorkspace`, `dataPersonal`, `containerK8sPersonal`,
`securityPersonal`, `passwordSecrets`, `aiLlm`, `modelHfPersonal`,
`backupRecovery`, `terminalVisual`, `presentation` を追加しています。

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
nix run .#list-tools -- --host own_mac
nix run .#list-tools -- --host work_mac --profile ultra
```

### JSON 出力

```bash
nix run .#list-tools -- --host work_mac --profile ultra --format json
```

### 出力範囲

`list-tools` が出力する toggle は次の深さに限定されます。

- `group.enable`
- `group.tool.enable`

`system.brewNix.autoDock.enable` や `editor.vscode.sync.enable` のような、より深い toggle は意図的に除外されています。

### 環境変数（任意）

- `HOST`（default: なし。位置引数で渡さない場合は必須）
- `PROFILE`（default: 空）
- `FORMAT`（`text` または `json`。default: `text`）
- `FACTS_DIR`, `SECRETS_DIR`
- `FACTS`, `SECRETS`（高度な override。default は `path:$FACTS_DIR` / `path:$SECRETS_DIR`）

## 実装メモ

- Nixpkgs install catalog: `nix/modules/tools/catalog.nix`
- Nixpkgs install catalog data: `nix/catalog/tools/nixpkgs.nix`
- Repo-local package overlay: `nix/pkgs/overlay.nix`
- Homebrew install catalog: `nix/modules/tools/brew-catalog.nix`
- Homebrew ownership registry: `nix/catalog/tools/homebrew-ownership.nix`
- `nix run .#list-tools -- ...`
- `nix/scripts/list-tools.nix`

toggle filtering logic は `list-tools.nix` にあるため、text 出力と JSON 出力は同じ filtered view から生成されます。

## work host policy

`work_mac` は別 profile taxonomy ではありません。stock の `minimal` / `lite` /
`pro` / `ultra` のいずれかを選び、host positive override を merge した後、
`nix/catalog/darwin/work-policy.nix` を forced-off policy data として適用します。
policy helper は profile と host data から実際に現れた `tools` toggle を flatten
するため、catalog module の group だけでなく、`core`, `shell`, `dev`, `editor`,
`system`, `terminal`, `security`, `aiCodingAgent` のような個別 module の group も対象にします。

policy deny は PATH 境界だけではなく install 境界です。registry-owned な
Homebrew / brew-nix payload は最終 owner toggle で filter されるため、deny
された cask/formula は shell lookup から隠すだけでなく、最終 install plan から
削除します。

`allowedGroups` は group 境界であり、完全な per-tool whitelist ではありません。
現行 policy は、stock Darwin profile と host override が project-pinned toolchain
（`go`, `nodejs`, `terraform`, `opentofu`）の global opt-in toggle を提供しない前提で
`dev` を許可します。`bun` だけは明示的な host opt-in 例外です。
将来それらを stock profile や host opt-in に戻すと、`work_mac` にも流れます。

broad group を広げるときは明示的に review してください。

- `system` は core macOS integration のため許可しますが、`latestApp`,
  `xcodesApp`, `swiftgen`, `sourcery`, `periphery`, `carthage` などの app/dev
  extras は deny しています。
- `terminalVisual` と `securityPersonal` は deny しています。remote access、
  scanner、packet-inspection、personal security tool は work-host default
  ではありません。
- `alacritty`, `ghostty`, `wezterm`, `rio`, `emacs-plus-app`, `goneovim`
  のような GUI terminal/editor app install は、広い `terminal` / `editor`
  group を CLI/editor support 用に残しつつ個別 deny しています。
- `downloadArchive` と `passwordSecrets` は group として許可し、selected extras
  を deny することで policy を読みやすくしています。

work policy は remote desktop、screen sharing、VPN/tunnel、packet-inspection、
security-sensitive app cask に対する Homebrew/brew-nix payload deny も持ちます。
これにより、TeamViewer, AnyDesk, RustDesk, Parsec, Wireshark, Burp Suite,
Tailscale, ngrok などを direct backend payload として追加しても、`work_mac`
には入りません。

`editor.emacs.sync.enable` のような deep toggle は `list-tools` 出力の対象外です。
policy assertion では direct `nix eval` を使って確認します。
`list-tools` は toggle 表示であり、Homebrew や Nix store payload は表示しないため、
install payload の assertion は final config の eval で確認します。

`flake check` には final-config tool-ownership check が含まれます。Darwin target に同じ `group.tool` key が複数 registry から現れる場合、最終 Homebrew config に複数 owner が claim する brew / cask / MAS item が含まれる場合、Homebrew cask が `tools.system.brewNix` と重複する場合、または ownership registry に claim されていない item がある場合に fail します。

`flake check` は、current system 向けの Nix catalog entry がその platform で利用可能な package に解決できることも検証します。同じ package を複数 profile group で使う場合、catalog entry は内部用の unique key と `tool = "name"` を併用できます。
