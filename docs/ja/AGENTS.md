[English version](../../AGENTS.md)

# リポジトリガイドライン

このリポジトリは、macOS システム構成のための Darwin-first な Nix flake です。変更は、現在の bounded context である Darwin hosts/rices、型付きの host truth、明示的な mutable surface、Rust control plane に沿わせてください。

## プロジェクト構成

- `flake.nix` — flake の inputs/outputs。`darwinConfigurations` と `templates`（`web-dev`, `rust-dev`）を公開します。
- `nix/denix/darwin/{hosts,rices}/` — Darwin host/rice プロファイル。
- `nix/denix/lib/` — Darwin host constructor と Denix helper。
- `nix/modules/` — 再利用可能な module。`shared/` と `tools/` に分割されています。
- `nix/catalog/` — tool module と ownership check で使う catalog data。
- `nix/local/` — public evaluation 用の placeholder facts input。
- `crates/dotfiles-core` — 共有 Rust support と shell sync 実装。
- `crates/dotfiles-cli` — 運用 CLI。
- `crates/dotfiles-sync-vscode` — VS Code native profile sync engine。
- `scripts/` — 薄い shell entrypoint（`apply`, `update`, `doctor`, `bootstrap`, `sync`）と smoke test。
- `nix/scripts/` — CLI が使う Nix expression（`list-tools.nix`, `matrix-tools.nix`, `doctor/facts-schema.nix`）。
- `apps/` — app 設定（例: `apps/shell/common.sh`, `apps/vscode/...`）。
- `surfaces/` — writable shell entrypoint の desired state。
- `keyboards/` — Karabiner complex modifications JSON。

ローカル input は Git 管理外の `~/.config/dotfiles/` に置きます。

- `facts.nix`
- `secrets.nix`
- `files/`

## ビルド・テスト・開発コマンド

- 正式なコマンド例と最新の host 名は `docs/commands.md` を参照してください。
- 正式な runtime override も `docs/commands.md` にあります（`HOME`, `DOTFILES_ROOT`, `FACTS*`, `SECRETS*`, `DARWIN_REBUILD_BIN`, `DOTFILES_SYNC_VSCODE_BIN`, `VSCODE_*`, `SOPS_AGE_KEY_FILE`）。
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
- `nix flake init -t github:atalie2m/dotfiles#web-dev`
- `nix flake init -t github:atalie2m/dotfiles#rust-dev`

## コーディングスタイル

- Nix: 2 スペースインデント、末尾改行、可能な範囲で安定した attribute 順序。
- ファイル名/ディレクトリ名: kebab-case。Nix attribute: lowerCamelCase。
- Shell: `#!/usr/bin/env bash` と `set -euo pipefail` を使うこと。
- Rust: workspace boundary を明確に保つこと。共有 CLI/runtime support は `dotfiles-core` に置きます。
- host 固有の literal は commit せず、local facts か secrets input に置いてください。

## アーキテクチャルール

- module は host truth を `myconfig.hostContext.*` から読むこと。
- 承認済みの host-model/bootstrap 境界の外で、新しい直接 `config.host.*`、legacy facts option read、raw `inputs.local/facts.nix` read を追加しないこと。
- shell sync は Rust の `dotfiles` CLI（`sync shell`）で実装されています。`scripts/sync.sh` は薄い shell wrapper のみです。
- VS Code sync は専用の `dotfiles-sync-vscode` binary で実装され、`dotfiles sync vscode` から dispatch されます。
- group toggle は taxonomy であり、rollout は明示的な capability bundle に属します。

## テスト方針

- `README.md`、`docs/`、`AGENTS.md`、`CLAUDE.md` は実際の runtime model と一致させてください。
- runtime sync、CLI 挙動、public docs の記述を変更したら、`scripts/tests/` の smoke test も更新してください。
- `keyboards/` または `nix/modules/tools/system/karabiner.nix` を触る場合は、Karabiner JSON が引き続き読み込めることを確認してください。

## セキュリティ

- secret や machine identifier は絶対に commit しないでください。
- ローカル machine data は repo 内ではなく `~/.config/dotfiles/` に置いてください。
