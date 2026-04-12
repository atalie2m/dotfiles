[English version](../reconciled-surfaces.md)

# Runtime sync surface

このリポジトリには 2 つの runtime sync surface と、activation で管理する 1 つの system-app boundary があります。

- shell entrypoint
- VS Code native profile
- Homebrew / macOS app ownership

## shell entrypoint

`nix run .#dotfiles -- sync shell` は public な writable entrypoint manager です。
control plane は Rust で実装され、`scripts/sync.sh` は薄い shell wrapper のみです。
共通 shell helper は引き続き Home Manager によって `~/.config/shell/common.sh` に配置され、shell tooling を有効にすると repo の `scripts/` directory も `PATH` に入ります。どちらも runtime sync state ではありません。

- Desired:
  - `surfaces/shell/desired/zdotdir.zshrc.block.sh`
  - `surfaces/shell/desired/bashrc.entrypoint.block.sh`
- Actual:
  - `~/.nix/.zshrc`
  - `~/.bashrc`
- State: なし
- Model: repo 管理 block の内容を現在の target と比較し、必要なら writable regular file として materialize する

挙動:

- block target は managed marker block のみ更新し、marker 外の unmanaged content は保持する
- `sync shell --apply` は missing file、writable regular file、`/nix/store/...` symlink、readable non-store symlink を修復する
- `sync shell --check` は `in-sync`、`needs-apply`、`missing`、`invalid` を返す
- shell sync は local change を repo に逆流させない
- repo 管理の `PATH` 変更に依存する native tool（例: `~/.local/bin` 配下の Claude Code）は、`apply` 後に新しい shell で利用可能になる

## VS Code native profile

Rust engine は `dotfiles-sync-vscode` として別 package 化され、`nix run .#dotfiles -- sync vscode` から dispatch されます。
設計は意図的に mutable です。managed profile settings file は repo state に完全収束し、extension ownership は選択的に扱います。

- Desired:
  - `apps/vscode/_default/settings.json`
  - `apps/vscode/_default/extensions.txt`
  - `apps/vscode/<profile>/settings.json`
  - `apps/vscode/<profile>/extensions.txt`
- Actual:
  - VS Code native profile の settings と extension membership
- State:
  - `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode`
  - managed profile ごとに 1 つの JSON state file
- Model:
  - `_default` と選択した profile を再帰マージする
  - 実効 settings file を fully repo-owned な profile state として書き出す
  - 実効 extension ID を repo が所有し、repo 外の user-added extension は保持する

挙動:

- `sync vscode --check` は `in-sync`、`needs-apply`、`missing`、`invalid` を返す
- `sync vscode --apply` は missing profile を作成し、profile registry を更新し、managed settings file を書き換え、repo-owned extension を reconcile する
- `apps/vscode/` から削除した settings は managed file が fully repo-owned なため、次の apply で消える
- repo が ownership を持たない user-added extension は保持される
- `tools.editor.vscode.enable` は VS Code sync tooling と managed profile surface を所有する。Visual Studio Code.app 自体は手動インストール
- stock bundle は activation 中に `sync vscode --apply` を実行しない。activation-time reconciliation が必要なら `tools.editor.vscode.sync.enable = true` を自分で設定する。VS Code 未インストール時も安全に skip する

## Homebrew と macOS app ownership

Homebrew と macOS app の宣言は `sync` ではなく activation/build 中に reconcile されます。
モデルは declarative ownership で、writable runtime data は upstream tool 側に残します。

- Desired:
  - `myconfig.tools.*` toggle と catalog ownership data
  - `nix/catalog/tools/homebrew-ownership.nix` の internal Homebrew backend metadata
- Actual:
  - Homebrew で install された formula / cask と app bundle
- State:
  - Homebrew 自身の runtime metadata
- Model:
  - repo が ownership と source policy を宣言する
  - activation が宣言済み install を保証する
  - runtime app / user data は mutable のまま
  - `tools.system.karabiner` のような feature module は install policy を所有し、`tools.editor.vscode` は repo-managed profile state と sync tooling を所有する

## 削除済み surface

- Terminal.app profile sync は削除済み
- Linux contributor output は root flake から削除済み
