[English version](../commands.md)

# コマンド

正式なコマンド例と現在の host 名はこのページにまとめます。README や AI helper 向けの文書には command surface を重複して書かず、このページに揃えてください。

## 現在の host と package

- Hosts: `pro_mac`（default rice: `pro`）、`ultra_mac`（default rice: `ultra`）、`minimal_mac`（default rice: `base`）
- Rices: `base`, `darwin`, `dev`, `pro`, `ultra`, `partial`
- darwin target の例: `pro_mac`, `ultra_mac`, `minimal_mac`, `ultra_mac-base`, `minimal_mac-ultra`, `pro_mac-partial`
- Packages: `dotfiles`, `dotfiles-cli`, `dotfiles-sync-vscode`

## 運用 CLI

これらのコマンドは Darwin 専用で、`darwinConfigurations` を解決します。

```bash
# 各 host の default rice を適用
nix run .#apply -- --host pro_mac
nix run .#apply -- --host ultra_mac
nix run .#apply -- --host minimal_mac

# build のみ実行
nix run .#apply -- --host ultra_mac --action build

# rice を明示指定して切り替え
nix run .#apply -- --host pro_mac --rice ultra
nix run .#apply -- --host ultra_mac --rice base
nix run .#apply -- --host minimal_mac --rice ultra
nix run .#apply -- --host ultra_mac --rice partial

# 実効 group/tool toggle を確認
nix run .#list-tools -- --host pro_mac
nix run .#list-tools -- --host ultra_mac --rice base --format json

# target 間の toggle matrix を確認
nix run .#matrix-tools
nix run .#matrix-tools -- --format json
nix run .#matrix-tools -- --full --format json

# local input を bootstrap
nix run .#bootstrap
nix run .#bootstrap -- --host pro_mac --apply
nix run .#bootstrap -- --host pro_mac --yes

# health check
nix run .#doctor
nix run .#doctor -- --host pro_mac
nix run .#doctor -- --host pro_mac --strict
nix run .#doctor -- --json

# flake input を更新し、check/build を実行
UPDATE_SKIP_BUILD=1 nix run .#update
nix run .#update -- --host pro_mac
UPDATE_ALL=1 nix run .#update -- --host pro_mac
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host pro_mac
```

## runtime sync

```bash
# shell entrypoint
nix run .#dotfiles -- sync shell --check
nix run .#dotfiles -- sync shell --check --details --diff
nix run .#dotfiles -- sync shell --apply

# VS Code native profile
nix run .#dotfiles -- sync vscode --check
nix run .#dotfiles -- sync vscode --check --details --diff
nix run .#dotfiles -- sync vscode --apply
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native
```

## runtime override

- `HOME` は `nix run .#dotfiles -- sync shell ...` と `nix run .#dotfiles -- sync vscode ...` に必須です。また、repo default の user-scoped path が必要な command でも必須です。
- `DOTFILES_ROOT` は Rust CLI と shell wrapper の flake-root discovery を上書きします。
- `FACTS_DIR` / `SECRETS_DIR` の default は `~/.config/dotfiles` で、`FACTS` / `SECRETS` の default は `path:$FACTS_DIR` / `path:$SECRETS_DIR` です。
- `DARWIN_REBUILD_BIN` は `apply` が使う pin 済み `darwin-rebuild` path を上書きします。
- `DOTFILES_SYNC_VSCODE_BIN` は `sync vscode` engine path を上書きします。
- `VSCODE_CODE_BIN` は `code` CLI path を上書きし、`VSCODE_DATA_HOME`、`VSCODE_EXTENSIONS_DIR`、`VSCODE_CODE_RETRIES` は VS Code runtime location と retry behavior を上書きします。
- `SOPS_AGE_KEY_FILE` は bootstrap / doctor が使う age key location を上書きします。未指定時は `HOME` がある場合に `~/.config/sops/age/keys.txt` を default とします。

注意:

- `scripts/*.sh` は Rust CLI の薄い shell wrapper です。
- `dotfiles-sync-vscode` は別 package として提供され、`dotfiles` が `sync vscode` をその binary に dispatch します。
- stock bundle は activation 中に `sync vscode --apply` を実行しません。自動化したい場合だけ `tools.editor.vscode.sync.enable = true` を自分で有効にしてください。Visual Studio Code.app 自体は手動インストール前提で、`code` または app bundle がなければ activation は安全に skip します。インストール対象の extension ID は `apps/vscode/`（`_default/extensions.txt` と profile ごとの `extensions.txt`）にあります。

## check と開発

```bash
nix fmt
nix run .#format
nix flake check \
  --override-input local path:$HOME/.config/dotfiles \
  --override-input secrets path:$HOME/.config/dotfiles
nix develop
```

## clean export

`export-clean` は tracked file のみを対象とし、trusted worktree にアクセスするため Git が必要です。Git が使えない、または repository を拒否した場合は fail closed します。

```bash
nix run .#dotfiles -- export-clean --format tar --output /tmp/dotfiles-clean.tar
nix run .#export-clean -- --format dir --output /tmp/dotfiles-clean
```

## 手動 rebuild

```bash
FACTS_DIR="$HOME/.config/dotfiles"
SECRETS_DIR="$HOME/.config/dotfiles"

nix run .#darwin-rebuild -- switch --flake .#<PROFILE_NAME> \
  --override-input local path:$FACTS_DIR \
  --override-input secrets path:$SECRETS_DIR
```
