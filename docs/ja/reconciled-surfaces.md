[English version](../reconciled-surfaces.md)

# Runtime sync surface

このリポジトリには 4 つの runtime sync surface と、activation で管理する 1 つの system-app boundary があります。

- shell entrypoint
- Doom Emacs config
- Neovim config
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

## Doom Emacs config

`nix run .#dotfiles -- sync emacs` は public な writable Doom config manager です。
control plane は `dotfiles-core` の Rust 実装で、`scripts/sync.sh` は薄い shell wrapper のみです。

- Desired:
  - `apps/emacs/doom/init.el`
  - `apps/emacs/doom/packages.el`
  - `apps/emacs/doom/config.el`
- Actual:
  - `${DOOMDIR:-~/.config/doom}/init.el`
  - `${DOOMDIR:-~/.config/doom}/packages.el`
  - `${DOOMDIR:-~/.config/doom}/config.el`
- State: なし
- Model: fully repo-owned な Doom config file を writable runtime file と比較する
- Contract: `apply` では Doom config file が repo state に完全収束する

挙動:

- `sync emacs --check` は `in-sync`、`needs-apply`、`missing`、`invalid` を返す
- `sync emacs --apply` は repo から writable runtime Doom config file を作成または上書きする
- `sync emacs --adopt` は runtime Doom config edit を `apps/emacs/doom/` に取り込む
- `--item init`、`--item packages`、`--item config` で対象 file を 1 つに絞れる
- `tools.editor.emacs.enable` は Emacs app、sync tooling、外部 `doom-meow` module を所有する。Doom 本体は mutable checkout のまま
- Doom は `${EMACSDIR:-~/.emacs.d}` に install され、標準の GUI / daemon 起動から直接使われる
- `tools.editor.emacs.bootstrap.enable` は `${EMACSDIR:-~/.emacs.d}/bin/doom` が無い場合だけ `dotfiles-doom bootstrap` を実行する
- stock `dev` 派生 bundle は activation-time Emacs sync と初回 Doom bootstrap を有効にする

## Neovim config

`nix run .#dotfiles -- sync neovim` は public な Neovim config drift manager です。
control plane は `dotfiles-core` の Rust 実装で、`nvim` sync surface alias も使えます。

- Desired:
  - `apps/neovim/**`
  - `apps/neovim/lazy-lock.json`
- Actual:
  - `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/**`
  - `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lazy-lock.json` が存在する場合はそれ、なければ `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json`
- State:
  - `${XDG_STATE_HOME:-$HOME/.local/state}/nvim` 配下の Neovim / LazyVim runtime state
- Model:
  - repo-owned な Neovim config tree と runtime config tree を比較する
  - repo config が Nix-managed で read-only になり得るため、state-local な `lazy-lock.json` を実効 Lazy lock として扱う

挙動:

- `sync neovim --check` は `in-sync`、`needs-apply`、`missing`、`runtime-only`、`invalid` を返す
- `sync neovim --apply` は repo file を writable runtime config dir に materialize し、lock がまだない場合は実効 lock を state dir に書く
- `sync neovim --adopt` は changed/runtime-only な runtime config file と実効 Lazy lock を `apps/neovim/` に取り込む
- adopt は非破壊的です。repo-managed file が runtime に存在しない場合、それを repo から削除せず、その item を拒否します
- runtime config dir が symlink の場合、`--apply` は lock 以外の rewrite を拒否します。linked tree には Home Manager activation を使うか、明示的に writable な `--runtime-dir` を渡してください

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
  - `tools.system.karabiner` のような feature module は install policy を所有し、`tools.editor.emacs` と `tools.editor.vscode` は repo-managed editor state と sync tooling を所有する

## 削除済み surface

- Terminal.app profile sync は削除済み
- Linux contributor output は root flake から削除済み
