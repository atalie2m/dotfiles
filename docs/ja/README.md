[English version](../../README.md)

## Flake templates

このリポジトリは、Nix flakes 経由で使える project development template を公開しています。

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
nix flake init -t github:atalie2m/dotfiles#rust-dev
nix flake init -t github:atalie2m/dotfiles#infra-iac
```

各 template は `flake-parts`, `treefmt-nix`, `git-hooks.nix`, `devenv`, `process-compose`, `direnv` / `nix-direnv`, `just`, common format / lint hook、security tooling を共有します。project-specific な例:

- `web-dev`: Node.js 22 / corepack、pnpm、bun、deno、TypeScript、Workers / Netlify / Supabase tooling、redocly、Vite / Vitest / Storybook / Nx / OpenAPI / GraphQL / Drizzle / Vercel / Surge の project-pinned npm CLI、AWS CLI v2、jq/yq、mkcert、local service helper。
- `rust-dev`: `rust-overlay` stable toolchain、rust-analyzer、cargo QA / release tools、C build deps、sqlite / protobuf。
- 追加 template: `go-dev`, `python-research`, `data-pipeline`, `native-dev`, `embedded-dev`, `apple-dev`, `infra-nixos`, `infra-iac`, `kubernetes-dev`, `container-oci`, `model-hf`, `docs-dev`, `api-db`, `ai-coding`, `release-dev`。

`web-dev`, `rust-dev`, `go-dev` には optional layer 用の `enabledProfiles`
selector もあります。`api-db`, `docs`, `release`, `container-oci`,
`kubernetes`, `infra-iac`, `ai-coding`, `model-hf`, `native-debug` などは、
必要な project でコメントを外して有効化できます。これらが repo の主目的である
場合に備えて standalone template も残しています。

# dotfiles

## 前提条件

- Nix（Lix または Determinate の vanilla）

## プロファイル（Denix hosts/rices）

この flake は [Denix](https://github.com/yunfachi/denix) を使い、Darwin 専用の host/rice tree で構成されています。

- `nix/denix/darwin/{hosts,rices}`

shared module、catalog、運用 script は Denix の host tree の外にあります。

- `nix/modules/{shared,tools}`
- `nix/catalog/tools/{nixpkgs.nix,homebrew-ownership.nix}`
- 薄い shell entrypoint と smoke test のための `scripts/`
- CLI が使う Nix expression のための `nix/scripts/`

現在の責務分割は [`docs/architecture.md`](architecture.md) を参照してください。
reset の理由、before/after、設計意図は [`docs/architecture-reset.md`](architecture-reset.md) を参照してください。

運用上の注意: サポートされる root flake API は Darwin-first で、`darwinConfigurations` と project `templates` を公開します。

- Hosts: `pro_mac`（default rice: `pro`）、`ultra_mac`（default rice: `ultra`）、`minimal_mac`（default rice: `base`）
- Rices: `base`, `darwin`, `dev`, `pro`, `ultra`, `partial`
  - `base`: shared essentials（`system.nix`, core CLI, shell, Git, GPG/SOPS）
  - `darwin`: macOS base integration（Homebrew + hostnames/fonts）
  - `dev`: editor / terminal / workstation stack
  - `pro`: `base + darwin + dev` の合成。ただし VS Code なし
  - `ultra`: 完全な profile（`base + darwin + dev`）
  - `partial`: `base + darwin + dev` に targeted override を加えた構成（AI coding agent は `codex` のみ有効、VS Code は無効）

正式な host 名と CLI 例は [`docs/commands.md`](commands.md) にあります。

手動 attribute 例（現在も有効）:
`pro_mac`, `ultra_mac`, `minimal_mac`, `ultra_mac-base`, `minimal_mac-ultra`, `pro_mac-partial`

`--rice` を指定した場合、CLI は `host-rice` のみを解決し、`host` への暗黙 fallback は行いません。

## アプリケーション source policy

アプリケーション / tool の source 優先順位:

- 詳細ポリシー: [`docs/homebrew-policy.md`](homebrew-policy.md)

1. CLI tool と library は原則として Nix package を使う。
2. Homebrew は macOS 固有の software や、意図的に latest-first にしたい software に使う。可能なら catalog-backed な `myconfig.tools` toggle を通す。
3. `tools.system.brewNix` は native Homebrew integration が不適切で、pin 済み cask path が必要なときだけ使う。
4. Homebrew backend list は internal implementation detail。`flake check` が unified ownership registry、重複 claim、cross-source overlap、未登録 item を検証する。

`Claude Code` は catalog-backed な `tools.aiCodingAgent.claudeCode` toggle
から latest-first の Homebrew cask として管理します。有効にすると
nix-darwin の Homebrew activation に `claude-code@latest` cask が追加されます。

## リポジトリ単位のツールチェイン方針

1. `terraform`, `opentofu`, `nodejs`, `go` は、その repo 自身の `flake.nix` / devShell で pin する前提にする。
2. stock Darwin bundle（`dev`, `pro`, `ultra`, `partial`）では、この 4 つを global に有効化しない。machine-wide version が repo 間に漏れないようにするため。
3. どうしても machine-global に必要なら `myconfig.tools.dev.<tool>.enable = true` を明示する。ただし stock bundle には戻さない。
4. Terraform は引き続き unfree。allow-list は helper wiring によって有効化 tool（例: `terraform`, `emacs`）から導出し、`allowAll` は無効のままにする。
5. Terraform / OpenTofu repo では、その repo の flake で `nixpkgs.config.allowUnfreePredicate` を設定し、devShell に `pkgs.terraform` / `pkgs.opentofu` を含める。

例（Terraform repo の `flake.nix`）:

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

## Tool Catalog（`myconfig.tools`）

`tools.dev.enable` のような group toggle は、単なる namespace ではなく bundle switch です。group を有効化すると、その group 配下の catalog-owned tool toggle に展開されます。
単一 host/rice の確認には `list-tools`、cross-target matrix には `matrix-tools` を使います。`matrix-tools` は default では group-level toggle を表示し、`--full` でより深い toggle を展開できます。catalog の範囲は [`docs/tool-catalog.md`](tool-catalog.md)、CLI 例は [`docs/commands.md`](commands.md) を参照してください。

手動評価（JSON）:

```bash
nix eval --json .#darwinConfigurations.ultra_mac-base.config.myconfig.tools
```

## VS Code profile

この repo は、手動で install した単一の VS Code app と native VS Code profile を対象にしています。
declarative source は `apps/vscode/<name>/` に置き、runtime への materialization は `sync vscode` で行います。

- `apps/vscode/_default/` はすべての managed profile に適用される shared layer
- `apps/vscode/native/` は native profile（`Native`）として管理
- `apps/vscode/<name>/` は、それ以外の任意名に対して display name を持つ native custom profile に対応
- サポート対象の input は `settings.json`、`extensions.txt`、bootstrap-only な `default-disabled-extensions.txt`
- `tools.editor.vscode.enable` は `dotfiles-sync-vscode` を Home Manager に install するが、Visual Studio Code.app 自体は手動 install 前提
- `sync emacs`、`sync neovim`、`sync shell` は `dotfiles-core` の Rust engine を使い、`sync vscode` は専用 Rust engine（`dotfiles-sync-vscode`）を使う
- **stock `ultra` の挙動:** stock Darwin bundle は VS Code module を有効化するが、Home Manager activation 中には `sync vscode --apply` を実行しない。VS Code install 後に `nix run .#dotfiles -- sync vscode --apply` を明示的に実行する
- **extension 一括 install:** repo-owned extension ID は `apps/vscode/`、主に `_default/extensions.txt` と各 profile の `extensions.txt`（例: `web/`, `native/`）にある。何を install / uninstall するかの source of truth はこの directory
- `sync vscode --apply` は、fully repo-owned な managed profile settings と、それらの repo-owned extension を writable な VS Code profile state に reconcile する
- `default-disabled-extensions.txt` は profile の extension enablement state に一度だけ seed される。その後 user が VS Code UI で有効化しても、sync は再び無効化しない
- drift 管理は意図的に mutable。managed profile settings は fully repo-owned で、repo-owned extension は収束するが、user-added extension は ownership の外に残る

runtime model と CLI は `docs/vscode.md` を参照してください。
shell、editor、VS Code、system app surface の mutable / immutable boundary は [`docs/reconciled-surfaces.md`](reconciled-surfaces.md) を参照してください。

## Mutable Editor Tooling

- Emacs の app wiring は Nix-first だが、Doom config file と package state は mutable のまま扱う。`sync emacs` は `apps/emacs/doom/{init,packages,config}.el` と `~/.config/doom` 配下の writable file を reconcile し、`--adopt` で local Doom edit を repo に取り込む。Doom 本体は `${EMACSDIR:-~/.emacs.d}` に置くため、標準の GUI / daemon 起動でも追加引数なしで読み込まれる。dev 派生の stock bundle は activation-time Emacs sync と初回 Doom bootstrap を実行する
- Neovim の app / config wiring は `apps/neovim/` で declarative に管理する。config は LazyVim ベースで、`sync neovim` は実効 state-local Lazy lock を含む runtime edit の drift detection / adopt を行える。`tools.editor.goneovim.enable` は Neovim の dev-bundle companion として upstream Darwin release から Goneovim GUI を install し、`nvim` dependency は Nix ownership のままにする
- VS Code profile 定義は declarative だが、runtime state は writable のまま。managed profile settings は fully repo-owned なので manual settings change は apply で上書きされ、user-added extension は repo ownership の外に残る
- この repo は editor runtime を convenience boundary として扱う。config はここで pin するが、package / login / UI state は pin しない

## terminal 互換性

現在の Zsh setup では、最近の terminal ならどれでも動きます。Terminal.app profile sync は repo から削除されているため、Terminal.app は unmanaged な fallback です。

**推奨 terminal:**

- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

## Zsh stack

default の Zsh prompt は Pure です。Zsh は `tools.shell.zsh.profile` で managed profile を切り替えます。

- `stable`: `fzf-tab`, `zsh-autosuggestions`, `fast-syntax-highlighting`, `zsh-vi-mode`, `zsh-autopair`, `zsh-completions`, `carapace`, `nix-zsh-completions`
- `autocomplete`: completion UI として `zsh-autocomplete` を使い、Tab owner としての `fzf-tab` は無効化
- `debug`: stable profile に加えて `zprof`, `bindkey`, `zinit` timing / report output を有効化

`base` は CLI-only S 級 cockpit を持ち、`dev` / `pro` / `ultra` は broader daily workstation profile を追加します。

- `fzf` keybinding: `CTRL-T` で file 挿入、`ALT-C` で directory jump
- `fzf-tab` を `TAB` に割り当て
- `Atuin` を `CTRL-R` に割り当て
- `zoxide` を `z` と `zi` で利用
- `direnv` + `nix-direnv`
- Git pager として `delta`
- `shellUx`, `filesNavigation`, `gitPersonal`, `nixOperator`, `observability`, `network`, `dataPersonal`, `securityPersonal`, `passwordSecrets`, `aiLlm`, `backupRecovery` などの profile group

`tools.profileDefaults` は、catalog toggle が有効な場合に `fzf`, `direnv`,
`gh-dash`, `yazi`, `zellij`, `k9s`, `television`, terminal app,
observability tool, preview tool, search tool の repo-owned default を書きます。

### shell sync（writable entrypoint）

shell sync は小さく stateless な writable-entrypoint manager です。
runtime sync operation は `nix run .#dotfiles -- sync shell` で実行され、`scripts/sync.sh` は Rust `dotfiles` CLI を呼ぶだけの薄い shell wrapper です。
役割は writable な shell entrypoint を維持し、repo-managed block / file だけを更新することです。
共通 shell helper は `apps/shell/common.sh` として別配布され、`~/.config/shell/common.sh` に link されます。repo の `scripts/` directory も shell tooling 有効時に `PATH` に追加されます。どちらも declarative な Home Manager content であり、runtime sync state ではありません。

- Desired source:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
- Local target:
  - `~/.nix/.zshrc`（managed block のみ。runtime ZDOTDIR entrypoint）
  - `~/.bashrc`（managed block のみ。runtime bash entrypoint）
- Local extension point:
  - zsh: `~/.config/shell/zsh.local.sh`
  - bash: `~/.config/shell/bash.local.sh`
- `sync shell` は上記の宣言済み target だけを管理する
- `sync shell --apply` は一般的な entrypoint 形状を自動で正規化する
  - missing file
  - writable regular file
  - `/nix/store/...` symlink
  - readable non-store symlink（writable regular file に materialize し直す）
- managed marker の外側にある content は保持する
- shell sync は machine-local な `lastApplied` state を持たず、local change を repo に取り込まない
- managed な macOS login-shell switching は `zsh` と `bash` をサポート

managed block marker:

```bash
# >>> dotfiles-managed:bashrc >>>
# ... managed content ...
# <<< dotfiles-managed:bashrc <<<
```

workflow:

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

`nix run .#apply -- --host <host>` は、enable された shell group に対して Home Manager activation 中に `sync shell --apply` を実行し、shell reconciliation を起動します。

shell entrypoint の writeability regression test（isolated + auto cleanup）:

```bash
scripts/tests/shell-zsh-writeability-test.sh
```

これらの test script は temporary `HOME` を使い、終了時に test file をすべて削除します。

追加の sync test:

```bash
scripts/tests/sync-cli-common-parse-test.sh
scripts/tests/sync-shell-smoke-test.sh
scripts/tests/sync-emacs-smoke-test.sh
scripts/tests/sync-neovim-smoke-test.sh
scripts/tests/sync-vscode-smoke-test.sh
```

## ローカル facts + secrets（override input）

この repo は Git の clean/smudge filter を使いません。machine-specific な facts と secrets は Git の外に置き、flake override で build 時に注入します。
両 input の default は `~/.config/dotfiles/` で、`facts.nix` と `secrets.nix` を同じ場所に置きます。

default layout:

```
~/.config/dotfiles/
├── facts.nix
├── secrets.nix
├── .sops.yaml
└── files/
    └── ai.env.sops.yaml
```

### facts（非 secret）

- `~/.config/dotfiles/facts.nix` を作成
- 必須: `user.username`
- 推奨（Git identity 用）: `user.fullName`, `user.email`
- 任意 override: `user.homeDirectory`（通常は自動導出）および、真に必要な場合の `machines.<host>.homeDirectory`（host 単位 override）
- 任意の host input metadata: `machines.<host>.keyboardType = "ansi" | "jis"`（入力デバイス差分のある Karabiner 挙動向け）
- platform は raw facts input ではなくなった。host 宣言が `system` を持ち、module は `myconfig.hostContext` から `os` / `arch` を導出する

例 `facts.nix`:

```nix
{
  user = {
    username = "yourname";

    # Recommended (used by Git module)
    fullName = "Your Name";
    email = "you@example.com";

    # Optional overrides
    # homeDirectory = "/path/to/home/yourname";

    stateVersion = {
      home = "25.11";
      darwin = 6;
    };
  };

  machines = {
    ultra_mac = {
      computerName = "Your Mac";
      localHostName = "your-mac";
      hostName = "your-mac";
      keyboardType = "ansi";
    };

    # Optional if you also use the pro_mac target:
    # pro_mac = {
    #   computerName = "Your Mac";
    #   localHostName = "your-mac";
    #   hostName = "your-mac";
    #   keyboardType = "jis";
    # };
  };
}
```

これらの machine 値は `tools.system.hostnames` が macOS の system naming に使います。

### secrets（機密）

- `~/.config/dotfiles/secrets.nix` を作成
- 暗号化 file は `~/.config/dotfiles/files/` に置く（推奨: sops + age）
- `secrets.nix` と暗号化 file を定義する（推奨: sops + age）
- 詳細な setup は [`docs/secrets-local.md`](secrets-local.md)

例 `secrets.nix`:

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

任意の shell source:

- zsh: `~/.config/shell/zsh.local.sh`
- bash: `~/.config/shell/bash.local.sh`

例（`~/.config/shell/zsh.local.sh`）:

```bash
if [ -f "$HOME/.config/dotfiles/ai.env" ]; then
  source "$HOME/.config/dotfiles/ai.env"
fi
```

### override 付き build

`nix run .#apply|.#update|.#doctor|.#bootstrap|.#list-tools|.#matrix-tools` は、`FACTS_DIR` と `SECRETS_DIR` から `FACTS` と `SECRETS` を自動導出します。手動 invocation では明示 override が必要です。

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- build --flake .#ultra_mac \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```

`nix run .#darwin-rebuild -- ...` は、この repo の `flake.lock` で pin された nix-darwin wrapper を使います。

**注意**: repo には `nix/local/` に placeholder public facts が入っており、default secrets input も意図的に inert なので、repo 内の secrets がなくても `darwinConfigurations` は評価できます。実機では引き続き両 input を `~/.config/dotfiles/` で override してください。

## Binary Cache（Cachix / Attic）

この repo は local facts を通じて追加の binary cache を参照できます。

`~/.config/dotfiles/facts.nix` に追加:

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

CI の cache push は Cachix 向けに配線済みです。GitHub repo には以下を設定します。

- `CACHIX_CACHE_NAME`（repository variable）
- `CACHIX_AUTH_TOKEN`（repository secret、write 権限あり）

設定されると、macOS CI job はすべての `darwinConfigurations` target を評価し、各 host の default target と、決定的に選ばれた 1 つの non-default rice target を build して cache に push します。

## Flake Config Trust（`accept-flake-config`）

利便性のため、この repo は default で `system.nix.acceptFlakeConfig = true` にしています。これにより flake-level の `nixConfig` が自動適用されます。

トレードオフ:

- Pros: この dotfiles flake を日常的に使うときの摩擦が減る（手動 flag が少ない）
- Cons: 未知の third-party flake を評価すると、その `nixConfig`（例: cache / substituter 設定）が適用されうる

より厳格にしたい場合は host / rice config で無効化します。

```nix
{
  myconfig.system.nix.acceptFlakeConfig = false;
}
```

## Karabiner-Elements setup

このリポジトリには、Karabiner-Elements 用の keyboard layout と input method 設定が `keyboards/karabiner/complex_modifications/` に含まれています。

### 利用可能な設定

1. **japanese-input-toggle.json**: 日本語 input method 切り替え設定
   - Command / Control / Option / Shift key による英数・かな切り替え
   - Caps Lock toggle
   - Vim-friendly な ESC key 挙動
   - KE-complex_modifications ベース

2. **spacebar-to-shift.json**: Space-and-Shift（SandS）機能
   - 他 key と組み合わせたときは Space を Left Shift として扱う
   - 単独押下では通常の Space
   - KE-complex_modifications ベース

3. **vylet-alt-layout.json**: Vylet alternative keyboard layout
   - 完全な keyboard layout remap
   - MightyAcas 作
   - 効率的な typing 向けに最適化

4. **shingeta_en.json**: 英語 typing game 向けの新下駄配列
   - typing game 向けに最適化された日本語 keyboard layout
   - kouy 作、funatsufumiya 実装

5. **shingeta_jp.json**: 日本語入力向けの新下駄配列
   - 完全な日本語入力対応
   - 上と同じ layout を一般的な日本語 typing 向けに利用

### declarative setup

`tools.system.karabiner.enable = true` の場合、dotfiles は Karabiner-Elements を 1 つの feature として管理します。

設定は `nix/modules/tools/system/karabiner.nix` にあり、次を自動で行います。

1. Homebrew で `karabiner-elements` を install
2. 必要な directory を作成
3. 管理対象 rule file と `karabiner.json` の symbolic link を生成
4. 設定の rebuild 時に link を更新

keyboard hardware の差分は host facts に残します。

```nix
{
  machines.ultra_mac.keyboardType = "ansi";
  # or "jis"
}
```

**設定詳細:**

- 設定 file はこの repo の `keyboards/` directory から供給される
- link される complex-modification set は module 内の明示的な `ruleFiles` list から決まる
- 生成される `karabiner.json` は `machines.<host>.keyboardType` があればそれを使い、なければ `ansi` を使う
- 変更は `nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME>` の後に反映される

Karabiner module を有効化しない場合、手動管理はこの repo の supported runtime model の外です。

### Credits

これらの設定は以下の成果物に基づく、またはそれらを含みます。

- **KE-complex_modifications**（Unlicense）
- **Shingeta Layout** by kouy and funatsufumiya（MIT License）
- **Vylet Keyboard Layout** by MightyAcas

完全な attribution は LICENSE file を参照してください。

# 使い方

## CLI（推奨）

すべての CLI command は自動的に以下を付加します。
`--override-input local "$FACTS"` と `--override-input secrets "$SECRETS"`。

これらの operational CLI command は Darwin-first です。`darwinConfigurations` と macOS 固有の check / build を対象にします。
`apply` と `list-tools` は `--host`、位置引数の host、または `HOST=...` が必要です。
`matrix-tools` は利用可能な `darwinConfigurations` をすべて評価し、`--host` は不要です。
`update` は build が有効（default）な場合にのみ host が必要です。
`bootstrap` は `--apply` または `--yes` を使う場合のみ host が必要です。

default:

- `FACTS_DIR=$HOME/.config/dotfiles`
- `SECRETS_DIR=$HOME/.config/dotfiles`
- `FACTS=path:$FACTS_DIR`
- `SECRETS=path:$SECRETS_DIR`

高度な override:

- 必要に応じて `FACTS` と `SECRETS` は別の flake input reference を指せる
- `doctor` と `bootstrap` は、それらの override が `path:...` でない場合でも local file を直接読む / 書くので、対応する `FACTS_DIR` / `SECRETS_DIR` が必要
- `HOME` は `sync shell`、`sync emacs`、`sync neovim`、`sync vscode`、および default user-scoped path が必要な command で必須

runtime override の詳細は [`docs/commands.md`](commands.md#runtime-overrides) にあります。

正式なコマンド例は [`docs/commands.md`](commands.md) を参照してください。

### Bootstrap（初回）

`bootstrap` は、必須の `user.username`、任意の identity field、コメント付きの machine / stateVersion 例を含む最小の `facts.nix` を作成します。

### Doctor（health check）

`doctor` は host なしでも global facts / secrets / basic system check を実行できます。
target evaluation や strict sync check では、target tool enablement を判定するために `--host` を渡してください。

### Apply（build/switch）

### Update（flake input + check/build）

### Formatter / Checks / Dev Shell

### Clean export

`export-clean` は tracked file のみを対象とし、trusted worktree にアクセスするため Git が必要です。Git が利用できない、または repository を拒否した場合は fail closed します。例は [`docs/commands.md`](commands.md) を参照してください。

## 手動 command（darwin-rebuild）

手動 rebuild の例は [`docs/commands.md`](commands.md) にあります。

## トラブルシューティング

- **`no darwinConfigurations found` / `unable to evaluate darwinConfigurations`** → override した `facts.nix` と `secrets.nix` を確認し、`nix run .#doctor` を再実行してください。
- **`target not found for host/rice`** → 利用可能な target は `nix run .#doctor -- --host <host> --rice <rice>` で確認してください。
- **`FACTS_DIR is required ...` / `SECRETS_DIR is required ...`** → `doctor` と `bootstrap` は local file path を必要とします。`FACTS` や `SECRETS` を非 `path:` ref で override する場合は、対応する `*_DIR` も設定してください。
- **`HOME is not set`** → `sync shell`、`sync emacs`、`sync neovim`、`sync vscode`、および default user-scoped runtime path は `HOME` が必要です。`HOME` を export するか、[`docs/commands.md`](commands.md#runtime-overrides) にある明示 override を使ってください。
- **`darwin-rebuild: command not found`** → 手動実行では `nix run .#darwin-rebuild -- ...` を使ってください。`nix run .#apply` と `nix run .#update` は pin 済み wrapper を自動利用します。
- **`error: unrecognised flag '--flake'`** → `nix run <flake>#<pkg> -- <cmd>` という形で実行してください。`--` 以降が `darwin-rebuild` に渡されます。
- **Using `sudo`** → macOS では `sudo` 下で `PATH` が reset されます。`nix run .#apply` は必要な `PATH` と dotfiles input override 変数を保持します。手動実行では `nix run .#darwin-rebuild -- ...` の pin 済み wrapper を使ってください。
