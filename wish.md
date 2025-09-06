**改善ウィッシュリスト（Dotfiles / Denix / macOS → Linux 拡張）**

- 概要: 現状は macOS 向けに堅牢な Flake + Denix 構成。Linux/NixOS への拡張と、重複/分岐の明確化、オンボーディング耐性の強化でさらに盤石にする。

**優先度: 高（Linux 対応/出力の拡張）**
- NixOS 出力の追加: `flake.nix` に `nixosConfigurations = mkConfigurations "nixos";` を追加し、Linux ホストを `nix/denix/hosts/` に用意する。
- モジュールの NixOS 対応: 例として `nix/denix/modules/packages/packages-core.nix` は `home.ifEnabled` のみ。`nixos.ifEnabled` で `environment.systemPackages` にも反映する（Darwin と Linux での配置先を分離）。
- Darwin 固有パッケージの分離: `nix/denix/modules/packages/packages-development.nix` の `pinentry_mac` のような Darwin 専用品は `darwin.ifEnabled` へ移し、Linux は `pinentry-gtk2` 等に切替できるよう条件分岐する。

**優先度: 中（クロスプラットフォーム一般化）**
- OS/パスの動的化: `nix/env.nix` の `homeDirectory`, `systemType`, `platform`, `dotfilesPath` のハードコードを削減。
  - `homeDirectory`: 可能なら `home.username` と OS から決定（Darwin は `/Users/<name>`, Linux は `/home/<name>`）。
  - `platform`: `pkgs.stdenv.hostPlatform.system` または Flake の `system` から導出して渡す（`specialArgs`/Denix 経由）。
  - `dotfilesPath`: 可能な箇所では `toString ./.` やモジュール側の相対パス（既存の `nix/denix/modules/karabiner.nix` は `../../../.` を使用）に寄せる。
  - Darwin 固有前提の値（`systemType = "darwin"` 等）は Linux 追加時に自動で切替る形へ（テンプレート分割 or 条件式）。

**優先度: 中（ホスト定義の DRY 化）**
- 共通骨格の抽出: `nix/denix/hosts/a2m_mac/default.nix`, `nix/denix/hosts/mn_mac/default.nix` は構造が類似。共通部分（`home.stateVersion`, `users.users.<name>`, `nix.package`, `nixpkgs.hostPlatform` など）を小さな共通モジュール（例: `nix/denix/modules/host-defaults.nix`）へ移動し、各ホストは差分（`rice` など）のみ記述。
  - 代替案: 簡単なヘルパー関数（`nix/denix/hosts/lib.nix`）でホスト骨格を生成し、`rice` 名とタイプだけを渡す。

**優先度: 中（整合性/命名・ドキュメント整備）**
- README の明確化: プロファイルは `env.nix` のトグルではなく、ホスト選択（`.#a2m_mac` は `full`、`.#mn_mac` は `mn` を選択）で切り替える旨を明記。マッピングを表で示すと初学者に親切。
- Linux 追加時の使い方: `nixos-rebuild switch --flake .#<linux-host>` の例と、`nix flake check` の確認ポイントを追記。
- 用語統一: 過去の README/レビューに見られる「common/commercial」表記は、現行リポジトリのホスト名（`a2m_mac`/`mn_mac`）へ統一。ドキュメント・CI・コメントを横断して揃える。
- CI のターゲット修正: `.github/workflows/ci.yml` のビルド対象を `darwinConfigurations.a2m_mac(.system)` / `mn_mac(.system)` と、その `-minimum` などの組み合わせに更新（現状 `common/commercial` を参照している行を置換）。
- .gitattributes と README の整合: README では `.git-filters/*` にフィルタ適用と記述があるが、実際の `.gitattributes` は `-filter`（除外）。どちらかに統一（推奨: 除外のまま README を修正）。
- Karabiner/Terminal の表示名: Karabiner の `A2m`/`Std`、Terminal.app の `"Atalie's dotfiles - Standard"` の由来・用途をコメント/README に注記。必要なら rice に応じてプロファイル名を切り替える実装も検討。

**優先度: 中（Git フィルターの耐障害性）**
- セットアップ漏れ検知: `flake.nix`（初期段階）または共通モジュールで `env.username == "{{USER_NAME}}"` 等のプレースホルダ検知時に明示的エラー（「`./setup-env.sh` を実行してください」）を出すアサーションを導入。
- 対象の絞り込み検討: `.gitattributes` は広めにフィルターを適用（`*.nix`, `*.json`, `*.sh` 等）。デモ文字列が必要なドキュメントを除外する場合は明示除外を検討（現状コメントのみ）。
- OS パス対応の拡張: `.git-filters/clean.sh`/`smudge.sh` が `/Users/{{USER_NAME}}` のみを扱うため、Linux では `/home/{{USER_NAME}}` も対象に。あるいはパス置換をやめ、モジュール側で OS から導出する方式へ統一。

**優先度: 低（細かな一貫性/堅牢化）**
- Homebrew 連携の前提確認: Homebrew を有効化する `rice`/ホストでは `system.primaryUser` が必須になるため、今後プロファイルを切り替える際も満たすことを README に注意書きとして追加。
- stateVersion の集中管理: 既に `nix/env.nix` に集約済みだが、Linux 追加時も `home`/`nixos`/`darwin` を同一ファイルで管理して更新手順を明示。
- Karabiner の OS 対応注記: `nix/denix/modules/karabiner.nix` は Darwin 専用である旨をコメント/オプション説明に追記（誤って Linux で有効化された場合の noop/エラー方針の決定）。

**優先度: 中（重複削減：オーバーレイ/共通処理）**
- オーバーレイの二重記述解消: `packages/claude-code-overlay.nix` と `packages/codex-overlay.nix` は `home.ifEnabled`/`darwin.ifEnabled` の両方で同一オーバーレイを重複記述。`let overlay = ...; in` で共通化し、両コンテキストに同一値を渡す。
- 将来の NixOS 対応時も同様に `nixos.ifEnabled` へ同じ変数を渡すだけで済むように設計。

**Denix 活用の拡張**
- マルチシステム出力の定着: `nixosConfigurations` 追加後、主要モジュールに `nixos.ifEnabled`/`darwin.ifEnabled`/`home.ifEnabled` のいずれを使うべきかを棚卸しし、分岐を明示。特にパッケージ系と OS 設定系を分離。
- オプションの粒度: OS 別で挙動が変わる箇所（pinentry, フォント, GUI アプリ等）はモジュール内で `cfg` によるサブオプションを用意すると拡張しやすい。
- args 拡張の積極活用: 既に `extensions = [ args (base.withConfig { args.enable = true; }) ]` を使用。必要に応じて CLI 引数で rice/ホスト差し替えを可能にし、CI で複数組合せを評価（例: `.#a2m_mac-minimum` 相当を arg から切替）。
- ホスト自動選択（任意）: ホスト名/環境変数からの自動選択を検討（純粋性とトレードオフ）。現状の明示選択でも十分。

**テスト/CI（任意）**
- 基本チェック: `nix flake check` の成功を前提に、macOS では `darwin-rebuild build --flake .#a2m_mac` が通ることを定期確認。Linux 導入後は `nixos-rebuild build --flake .#<linux-host>` も追加。
- CI 導入の検討: GitHub Actions で `nix flake check` を実行（macOS ランナーはコスト高なので Linux ランナーで評価のみ）。
- CI のビルドターゲット更新: `.github/workflows/ci.yml` の `common/commercial` を `a2m_mac/mn_mac` に更新し、`-minimum` 組合せも現行命名に合わせる。
- 追加の静的解析（任意）: `deadnix`, `alejandra`/`nixfmt` などを `nix flake check`/CI に組込み、未使用変数や整形も自動検出。

**推奨変更箇所（参考ファイル）**
- Flake 出力拡張: `flake.nix`
- クロスプラットフォーム化の要: `nix/env.nix`
- パッケージの OS 分岐: `nix/denix/modules/packages/packages-core.nix`, `nix/denix/modules/packages/packages-development.nix`
- オーバーレイ重複解消: `nix/denix/modules/packages/claude-code-overlay.nix`, `nix/denix/modules/packages/codex-overlay.nix`
- ホスト DRY 化: `nix/denix/hosts/a2m_mac/default.nix`, `nix/denix/hosts/mn_mac/default.nix`（共通化モジュール新設）
- Darwin 専用注記/分岐: `nix/denix/modules/karabiner.nix`, `nix/denix/modules/homebrew-native.nix`
- フィルター制御: `.gitattributes`, `setup-env.sh`
- CI 修正: `.github/workflows/ci.yml`

**次の一手（小さく進める順）**
- [ ] `flake.nix` に `nixosConfigurations` を追加し、`nix flake check` を通す。
- [ ] `packages-core.nix` に `nixos.ifEnabled` を追加（`environment.systemPackages` へ展開）。
- [ ] `packages-development.nix` の Darwin 固有パッケージを `darwin.ifEnabled` に移動し、Linux 代替を用意。
- [ ] `env.nix` の `dotfilesPath`/`homeDirectory`/`platform` を導出方式へリファクタ（または OS 別テンプレート化）。
- [ ] ホスト共通モジュール（例: `nix/denix/modules/host-defaults.nix`）を作り、2 ホストから重複を排除。
- [ ] プレースホルダ検知のアサーション（`./setup-env.sh` 実行促し）を追加。
- [ ] README にプロファイル/ホスト対応表と Linux 手順を追記。
- [ ] `.github/workflows/ci.yml` の `common/commercial` 名称を `a2m_mac/mn_mac` へ更新し、ビルド行を現行出力に合わせて修正。

**検証コマンド（目安）**
- macOS: `darwin-rebuild build --flake .#a2m_mac`
- Linux: `nixos-rebuild build --flake .#<linux-host>`（Linux 追加後）
- 共通: `nix flake check`
