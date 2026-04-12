[English version](../architecture.md)

# アーキテクチャ

このリポジトリは、Darwin composition、再利用可能な module、catalog data、runtime tooling を別々の tree に分けることで、それぞれの層が独立して進化できるようにしています。

reset の理由と before/after の要約は [`docs/architecture-reset.md`](../architecture-reset.md) を参照してください。

## レイアウト

- `nix/denix/darwin`: Darwin host と rice の宣言のみ
- `nix/denix/lib`: Darwin host constructor と Denix 固有 helper
- `nix/modules/shared`: raw facts schema、canonical host model wiring、system module、shared Nixpkgs policy
- `nix/modules/tools`: capability ごとに grouped された user-facing tool module
- `nix/catalog/tools`: Nixpkgs / Homebrew-backed tool の declarative な ownership data
- `crates/dotfiles-core`: 共有 Rust support と shell sync 実装
- `crates/dotfiles-cli`: operational CLI（`apply`, `update`, `doctor`, `bootstrap`, `export-clean`, `list-tools`, `matrix-tools`, `sync`）
- `crates/dotfiles-sync-vscode`: 専用の VS Code native profile reconciliation engine
- `scripts/`: 薄い shell entrypoint と smoke / integration test
- `nix/scripts/`: CLI helper が使う Nix expression（`list-tools.nix`, `matrix-tools.nix`, `doctor/facts-schema.nix`）
- `apps/`、`surfaces/`、`keyboards/`: module と runtime sync が消費する repo-managed asset

## 配線ルール

- `flake.nix` は `repoPaths` を `specialArgs` 経由で渡し、module は深い相対 import ではなくそれを使う
- user-facing option path は `myconfig.*` の下に置く
- module 向け host truth は `myconfig.hostContext.*` に置く
- raw facts import は host-model / bootstrap の境界に限定する
- `scripts/` 配下の shell は control plane ではなく薄い entrypoint に限定する

## 実務上の含意

- サポートされる operational root flake API は Darwin-first
- 再利用可能な feature を追加するなら `nix/modules/` に置き、`nix/denix/darwin` は composition に集中させる
- catalog 管理の tool を追加するなら、`nix/catalog/tools/` の対応する registry / catalog data を更新する
- operational CLI behavior を追加するなら、まず Rust workspace に実装し、shell は薄いままに保つ
