[English version](../../CLAUDE.md)

# CLAUDE.md

このファイルは、この repo で作業する coding agent 向けの repository guidance をまとめたものです。

## 基本事項

- 正式なコマンド例と最新の host 名は `docs/commands.md` にあります。
- 正式な runtime override も `docs/commands.md` にあります（`HOME`, `DOTFILES_ROOT`, `DOTFILES_PROFILE_DIRS`, `EMACSDIR`, `FACTS*`, `SECRETS*`, `DARWIN_REBUILD_BIN`, `DOTFILES_SYNC_VSCODE_BIN`, `VSCODE_*`, `SOPS_AGE_KEY_FILE`）。
- サポートされる operational root API は Darwin-first です。`darwinConfigurations`、`linux_workbench` などの bounded な `homeConfigurations`、project `templates` を公開します。
- public 向け placeholder facts は `nix/local/` にあり、default secrets input は意図的に inert です。実機では両方とも `~/.config/dotfiles/` で override してください。

## 設定フロー

1. `flake.nix` は supported operational root API を Darwin-first（`darwinConfigurations`、bounded Linux Home Manager `homeConfigurations`、project `templates`）として保ちます。
2. platform catalog は `inputs.local/facts.nix` と host 宣言から canonical host truth を構築し、`config.myconfig.hostContext` に入れます。
3. module は raw facts ではなく `config.myconfig.hostContext.*` を使います。
4. `sops-nix` は activation 時に `inputs.secrets/secrets.nix` で定義された secret を materialize します。

## アーキテクチャ概要

- `nix/catalog/darwin/`: Darwin host/profile catalog と stock profile bundle。
- `nix/catalog/linux/`: userland-only target 向け Linux Home Manager host/profile catalog。
- `nix/catalog/shared/`: platform catalog 間で再利用する portable profile bundle。
- `nix/modules/`: 再利用可能な shared/tool module。
- `nix/catalog/`: ownership と backend metadata。
- `crates/dotfiles-core`: 共有 Rust support と shell / Emacs sync engine。
- `crates/dotfiles-cli`: 主な operational CLI。
- `crates/dotfiles-sync-vscode`: 専用の VS Code engine。
- `scripts/`: 薄い shell entrypoint と smoke test。

## 作業ルール

- Rust control-plane の挙動は shell wrapper ではなく workspace 側で変えることを優先してください。
- shell は薄い entrypoint か OS 末端の挙動に限定してください。
- host truth は `myconfig.hostContext.*` の下に集中させてください。
- Linux Home Manager target は userland-only に保ってください。LXC substrate、storage、Tailscale、SSH、observability、lifecycle は `domus-ops` が所有します。
- public behavior が変わったら docs を正確に更新してください。
- project-pinned toolchain は stock global bundle に入れません。`go`, `nodejs`, `terraform`, `opentofu` は host opt-in path を持たせず、project template / devShell 側で version を固定します。`bun` だけを明示的な host opt-in 例外にします。
- template は Git-flake-first に保ってください。unfiltered `path:$PWD` instruction は追加せず、`target/`、`node_modules/`、`.git/`、`.direnv/` は ignore と source filter で flake source から外します。
- Git branch 戦略は `docs/git-branch-strategy.md` に従ってください。変更単位は Pull Request であり、branch 名は authority ではありません。
- 人間の work branch には命名規則を置きません。`main`, `maint/**`, `stabilize/**`, `svc/<principal-id>/**`, Dependabot refs, `gh-readonly-queue/**` は予約 namespace です。
- dotfiles には汎用 unattended task-agent credential を install しないでください。service branch には明示的な principal owner と inventory entry が必要です。
- branch 名に date、run ID、owner、environment、provenance、producer、policy lane、release target、issue type を埋め込んだり、そこから読み取ったりしないでください。

## 検証

toolchain が使える場合は、以下を優先してください。

- `cargo test`
- `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- `nix run .#apply -- --host <host> --action build`
- `nix build .#homeConfigurations.linux_workbench.activationPackage`
