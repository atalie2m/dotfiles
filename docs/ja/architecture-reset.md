[English version](../architecture-reset.md)

# アーキテクチャリセット

この文書は Darwin-only への reset を説明するものです。何を削除したのか、何をより厳密にしたのか、そしてこのリポジトリが現在どの構成を supported architecture と見なしているのかをまとめています。

## 目的

この reset は、リポジトリを意図的に 1 つのプロダクトへ絞り込みました。

- Darwin-first な personal system platform
- explicit な mutable surface
- 型付きの Rust control plane

目的は mutable state を隠すことではありません。ownership、orchestration、host truth を明確に見える形にすることでした。

## 設計原則

- `One product, one operational API`: サポート対象の operational root surface は Darwin-first。
- `Canonical host truth is shared`: module は `myconfig.hostContext.*` を使う。
- `Typed truth beats ad-hoc validation`: machine metadata と host-derived data は一度だけ正規化する。
- `Mutable boundaries stay explicit`: shell entrypoint、Emacs config、VS Code profile、Homebrew/app state は reconciled surface であり、見せかけの declarative state ではない。
- `Shell is an adapter, not the control plane`: shell は薄い entrypoint layer に留め、orchestration は Rust に置く。

## 何が変わったか

### root flake のスコープ

reset 後:

- supported operational root surface は Darwin-first
- `darwinConfigurations` を常に export する
- project `templates` は再利用可能な public artifact として残す
- 未サポートの Home Manager / NixOS tree と Linux contributor output を削除した

意図:

- root flake を、実際に運用するプロダクトの形に合わせる
- public facts が placeholder でも public evaluation を安定させる

### facts と host model

reset 後:

- raw local facts は input-only data のまま
- canonical derived host data は raw facts と host 宣言から一度だけ構築する
- module は `myconfig.hostContext.*` を読む
- machine metadata は unstructured blob のままにせず型付けする

意図:

- host identity と normalization を 1 箇所に集中させる
- Nix の型により多くの契約を担わせる

### platform truth

reset 後:

- host 宣言が `system` を一度だけ提供する
- `os`、`arch`、default home directory、その他関連値はその system から導出する
- raw facts は platform identity を持たない

意図:

- machine identity を host の責務に保つ
- module が複数箇所から platform truth を推測しないようにする

### CLI と workspace boundary

reset 後:

- Rust は `dotfiles-core`、`dotfiles-cli`、`dotfiles-sync-vscode` の real workspace になった
- `dotfiles-cli` が `apply`、`agent-notify`、`update`、`doctor`、`bootstrap`、`export-clean`、`list-tools`、`matrix-tools`、`sync` を所有する
- `dotfiles-sync-vscode` は別 package として提供しつつ、`dotfiles` 経由で呼び出す
- shell sync は Bash ではなく Rust で実装する

意図:

- bounded context を workspace layout から読み取りやすくする
- VS Code engine crate を CLI 全体の物理的な受け皿として扱うのをやめる

### mutable surface

reset 後:

- `sync shell` は writable shell entrypoint を Rust で reconcile する
- `sync emacs` は writable Emacs config file を Rust で reconcile する
- `sync neovim` は writable Neovim config drift と実効 Lazy lock state を Rust で reconcile する
- `scripts/sync.sh` は薄い shell wrapper のみ
- `sync vscode` は専用の `dotfiles-sync-vscode` binary に dispatch する
- Homebrew ownership は declarative かつ validated のままだが、runtime app state は writable のままにする

意図:

- explicit mutable-surface model を維持する
- orchestration を型付きコードへ移す

### bundle rollout policy

reset 後:

- tool group は taxonomy のまま
- bundle membership は capability bundle で明示する
- enabled な group に tool を追加しただけでは、新しい tool は暗黙に rollout されない

意図:

- 分類と rollout policy を分離する
- host behavior の変化を profile composition 上で明示する

## 重要な repository fact

- canonical host model は `myconfig.hostContext.*` にある
- `pro` は editor app と tooling を install するが、VS Code / Neovim / Emacs の setup sync は実行しない
- `ultra` は `pro` に加えて VS Code / Neovim / Emacs の setup sync を有効化する
- `tools.system.brewNix` は `tools.system.macAppUtil` を自動有効化しない

## 変わっていないこと

- repo-owned Darwin catalog が composition layer である
- 既存の Darwin host 名は維持されている
- mutable surface は設計上 mutable のままである
- Homebrew ownership registry は引き続き policy center である

## 検証の期待値

想定される検証経路:

- Rust workspace に対する `cargo test`
- 実際の local `facts` と `secrets` を使った `nix flake check`
- 変更した host の Darwin build
- portable checks に含まれる shell / VS Code smoke test
