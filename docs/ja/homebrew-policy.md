[English version](../homebrew-policy.md)

# Homebrew ポリシー

この文書は、この dotfiles flake における package source boundary を定義します。

## source boundary

1. CLI tool と library は原則として Nix package を使います。
2. Homebrew は macOS 固有、または意図的に latest-first にしたい software にのみ使います。通常は GUI app と一部の更新頻度が高い CLI が対象です。
3. Homebrew install は可能な限り `myconfig.tools` 配下の catalog-backed toggle を通してください。ad-hoc な backend list は避けます。
4. Homebrew ownership は `nix/catalog/tools/homebrew-ownership.nix` に登録し、`homebrewNative` と `brewNix` の backend metadata も含めます。
5. `tools.system.brewNix` は native Homebrew integration が不適切な場合の明示的な代替 backend としてのみ使ってください。両 backend surface は public configuration API ではなく internal machinery と見なします。

## 重複ルール

1. 同じ CLI を Nix と Homebrew の両方から install しないでください。
2. tool source を移行するとき（Nix <-> Homebrew）は、同じ変更で古い宣言を削除してください。
3. GUI app は、Nix で package 化する強い理由がない限り Homebrew cask に置いてください。
4. `flake check` は最終 Darwin config を検証し、Homebrew item が未登録、複数 owner に claim されている、`brew-nix` cask と重複している、または `group.tool` key が複数 registry に claim されている場合に fail します。

## PATH と runtime ルール

1. 再現性のため、`PATH` 上では Nix 提供の CLI を優先します。
2. Homebrew CLI を残す必要がある場合は、それを有効化する module または catalog entry に理由を記述してください。
3. apply/build の変更後は `command -v <tool>` で実効 binary を確認してください。
4. Homebrew を有効にする全 Darwin profile の Homebrew shell environment は `tools.system.nixHomebrew` が所有します。評価済みの native prefix から `PATH`、`HOMEBREW_*`、zsh completion、manual/Info path を生成し、Homebrew を持たない profile には追加しません。
5. repository 管理の shell 起動処理では `brew shellenv` や追加の macOS `path_helper` を実行してはいけません。Homebrew 側の停止で prompt 表示まで止まらない構成にします。macOS 標準の `/etc/zprofile` は OS の所有境界として維持します。
6. 通常の Darwin activation は宣言済み依存の不足分だけを導入し、Homebrew の auto-update や導入済み依存の upgrade は行いません。network-bound な Homebrew maintenance を意図するときだけ `brew bundle upgrade` を明示的に実行します。このコマンドは生成済みの宣言的 Brewfile を使用します。

## review checklist

1. 各 tool は source を 1 つだけ持っていますか。
2. source choice はこのポリシーと整合していますか。
3. Homebrew item は ownership registry に含まれていますか。
4. `PATH` は意図した executable を解決していますか。

## tool ごとのメモ

1. Cloudflare `wrangler`: default source は Nix（`home-manager` または project `flake.nix`）を推奨します。
2. Homebrew `wrangler` は、workflow 上 Nix packaging が使えない場合に限って残してください。
3. `Claude Code`: `tools.aiCodingAgent.claudeCode` 経由で latest-first の Homebrew cask（`claude-code@latest`）を使います。
4. `Goneovim`: Homebrew cask は Homebrew `neovim` に依存し、Gatekeeper deprecation 後に disable 予定のため使わず、upstream Darwin release 由来の repo Nix package を使います。
5. `Sourcery`: stock profile で tool toggle を有効化しても、runtime facts が full Xcode.app build environment を検出した場合だけ Homebrew formula を出力します。
6. `Mosh`: Darwin では Homebrew `mosh` formula を使い、`mosh-server` の macOS firewall-facing runtime surface を安定させます。repo は non-interactive SSH bootstrap discovery 用に `mosh-server` profile wrapper だけを install します。
