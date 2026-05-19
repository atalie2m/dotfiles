[English version](../commands.md)

# コマンド

正式なコマンド例と現在の host 名はこのページにまとめます。README や AI helper 向けの文書には command surface を重複して書かず、このページに揃えてください。

## 現在の host と package

- Hosts: `own_mac`（default profile: `pro`）、`work_mac`（default profile: `pro`）
- Profiles: `minimal`, `lite`, `pro`, `ultra`
- darwin target の例: `own_mac`, `own_mac-minimal`, `own_mac-lite`, `own_mac-ultra`, `work_mac`, `work_mac-minimal`, `work_mac-lite`, `work_mac-ultra`
- Packages: `dotfiles`, `dotfiles-cli`, `dotfiles-sync-vscode`
- Templates: `web-dev`, `rust-dev`, `go-dev`, `python-research`, `data-pipeline`, `native-dev`, `embedded-dev`, `apple-dev`, `infra-nixos`, `infra-iac`, `kubernetes-dev`, `container-oci`, `model-hf`, `docs-dev`, `api-db`, `ai-coding`, `release-dev`

## Project templates

```bash
nix flake init -t github:atalie2m/dotfiles#web-dev
nix flake init -t github:atalie2m/dotfiles#rust-dev
nix flake init -t github:atalie2m/dotfiles#infra-iac
nix flake init -t github:atalie2m/dotfiles#python-research
```

template 初期化後の project は Git flake として扱います。

```bash
nix run .#...
nix build .#...
nix develop
nix flake check
```

`path:$PWD#...` のような unfiltered local path ref は使わないでください。
`.git/`、`target/`、`node_modules/`、`.direnv/` が `/nix/store` にコピーされ得ます。

## 運用 CLI

これらのコマンドは Darwin 専用で、`darwinConfigurations` を解決します。
`work_mac` は選択 profile と host override の後に host policy を適用するため、`--profile ultra` も work 境界で上限がかかります。

```bash
# 各 host の default profile を適用
nix run .#apply -- --host own_mac
nix run .#apply -- --host work_mac

# build のみ実行
nix run .#apply -- --host own_mac --action build

# profile を明示指定して切り替え
nix run .#apply -- --host own_mac --profile ultra
nix run .#apply -- --host work_mac --profile lite
nix run .#apply -- --host work_mac --profile ultra
nix run .#apply -- --host own_mac --profile minimal

# 実効 group/tool toggle を確認
nix run .#list-tools -- --host own_mac
nix run .#list-tools -- --host work_mac --profile ultra --format json

# target 間の toggle matrix を確認
nix run .#matrix-tools
nix run .#matrix-tools -- --format json
nix run .#matrix-tools -- --full --format json

# local input を bootstrap
nix run .#bootstrap
nix run .#bootstrap -- --host own_mac --apply
nix run .#bootstrap -- --host own_mac --yes

# health check
nix run .#doctor
nix run .#doctor -- --host own_mac
nix run .#doctor -- --host work_mac --strict
nix run .#doctor -- --json

# flake input を更新し、check/build を実行
UPDATE_SKIP_BUILD=1 nix run .#update
nix run .#update -- --host own_mac
UPDATE_ALL=1 nix run .#update -- --host own_mac
UPDATE_CHECKS=1 UPDATE_FORMAT=1 nix run .#update -- --host own_mac

# この checkout から installed dotfiles CLI/runtime を更新
nix run .#self-update -- --host own_mac
nix run .#self-update -- --host own_mac --profile ultra

# user / Home Manager profile を変更せず target を検証
nix run .#self-update -- --host own_mac --action build --no-user-profile
```

`self-update` は dotfiles Rust CLI の変更、coding-agent notification runtime の変更を反映する
one-shot command です。default user Nix profile に `dotfiles` entry があれば先に更新し、
その後 selected target に対して canonical な Darwin/Home Manager apply path を実行します。
通常 `PATH` で先に見つかる `/etc/profiles/per-user/$USER/bin/dotfiles` を更新するのは後者です。
ad-hoc な user profile entry を維持しない host では `--no-user-profile` を使ってください。

## Nix store cleanup

`gc` は host を必要とせず、`darwinConfigurations` も解決しません。

```bash
nix run .#gc
nix run .#gc -- --apply
nix run .#gc -- --apply --delete-older-than 14d
nix run .#gc -- --apply --store-only
```

`--apply` は system / root profile history cleanup に非対話の `sudo` を使います。sudo timestamp が有効でない場合は先に `sudo -v` を実行してください。

unfiltered path-flake run で store が肥大化した場合は、まず collectable path を確認し、
その後 old generation を cleanup してください。

```bash
nix store gc --dry-run
sudo nix-collect-garbage -d
```

## runtime sync

```bash
# Emacs と Neovim config sync をまとめて適用
nix run .#sync
nix run .#sync -- --check
nix run .#sync -- --check --details --diff

# shell entrypoint
nix run .#dotfiles -- sync shell --check
nix run .#dotfiles -- sync shell --check --details --diff
nix run .#dotfiles -- sync shell --apply

# Emacs config
nix run .#dotfiles -- sync emacs --check
nix run .#dotfiles -- sync emacs --check --details --diff
nix run .#dotfiles -- sync emacs --apply
nix run .#dotfiles -- sync emacs --adopt --item init

# Neovim config と Lazy lock state
nix run .#dotfiles -- sync neovim --check
nix run .#dotfiles -- sync neovim --check --details --diff
nix run .#dotfiles -- sync neovim --apply
nix run .#dotfiles -- sync neovim --adopt

# VS Code native profile
nix run .#dotfiles -- sync vscode --check
nix run .#dotfiles -- sync vscode --check --details --diff
nix run .#dotfiles -- sync vscode --apply
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native
```

## Codex Slack 通知

`dotfiles agent-notify codex` が Codex Slack 通知の canonical な Rust command です。
`scripts/codex-slack-notification` は既存 hook config のために
`dotfiles agent-notify codex` へ委譲する互換 shim だけを残しています。Slack thread
対応には Bot User OAuth token mode を優先します。Incoming webhook は one-off reply
用の fallback です。

この通知 runtime の stock profile ownership は
`tools.aiCodingAgent.codex.slackNotifications.enable` 経由の `ultra` 限定です。
`pro` は default では有効化しません。

Rust 実装は generic agent-event core を使います。Codex adapter が Codex hook stdin、
transcript record、title、質問、approval、completion event を typed event に変換し、
Slack sink は title、body、thread key、event kind だけを受けて Bot API / webhook 投稿、
thread state、fallback、error log を担当します。

```bash
# Slack credential を Git の外に保存
mkdir -p ~/.config/dotfiles/files/agent-notifications
printf '%s\n' 'xoxb-...' \
  > ~/.config/dotfiles/files/agent-notifications/slack-bot-token
printf '%s\n' 'C0123456789' \
  > ~/.config/dotfiles/files/agent-notifications/slack-channel-id
chmod 0600 \
  ~/.config/dotfiles/files/agent-notifications/slack-bot-token \
  ~/.config/dotfiles/files/agent-notifications/slack-channel-id

# bot token mode が使えない場合の任意 fallback
printf '%s\n' 'https://hooks.slack.com/services/...' \
  > ~/.config/dotfiles/files/agent-notifications/slack-webhook-url
chmod 0600 ~/.config/dotfiles/files/agent-notifications/slack-webhook-url

# Slack へ投稿せず payload を確認
dotfiles agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/path/to/project",
  "last_assistant_message": "Dry-run notification."
}
JSON

# setup test notification を 1 回送る
dotfiles agent-notify test

# coding-agent notification runtime だけを更新します。Darwin switch はしません。
nix run .#agent-notifications-update
```

旧 `~/.config/dotfiles/files/codex/slack-*` credential file も fallback として読むため、
既存の local secret はすぐ移動しなくても動きます。

`agent-notifications-update` は default user Nix profile の `dotfiles` entry だけを install / upgrade
します。`scripts/codex-slack-notification` は `$HOME/.nix-profile/bin/dotfiles` が存在する場合に
それを優先するため、Codex Slack hook の修正は full Darwin/Home Manager switch なしで反映できます。
広い installed dotfiles runtime も揃える場合だけ `nix run .#self-update -- --host <host>` を使います。
`codex-slack-update` は compatibility app alias として残しています。

`~/.codex/config.toml` に hook を追加します。

```toml
[features]
codex_hooks = true

# 軽い transcript watcher を起動します。Codex の生成 title を Slack 親 message
# として使い、Plan Mode の request_user_input 質問を回答前に拾い、
# approval wait も拾います。自動解決された record は skip し、
# その Codex transcript から完了 reply も送ります。
[[hooks.SessionStart]]
[[hooks.SessionStart.hooks]]
type = "command"
command = "/path/to/dotfiles/scripts/codex-slack-notification --spawn-watcher"
timeout = 5
statusMessage = "Starting Codex Slack transcript watcher"
```

`SessionStart` は transcript watcher を起動します。watcher は session transcript を先頭から読み、
Codex が `thread_name_updated` を出した時点で Slack 親 message を作り、後続通知を
その親への reply として投稿します。親 message は `Codex: <title> (<repo>)` 形式です。title event
が無い場合は最初の user prompt から短い title を作り、それも無ければ `Codex: <repo>` に
fallback します。後から title event が来れば `chat.update` で親 title を更新します。Plan Mode の
`request_user_input` 質問、`guardian_assessment` から得た approval wait、transcript の
`task_complete` record は、その exact Codex session の watcher から reply として投稿します。
Plan Mode 外で Codex が自動解決した `request_user_input` record は無視します。approval wait は
最大 30 秒、Codex auto-review の判定を待ちます。agent が `approved` と判定した request は skip し、
自動承認されなかった request は Slack に投稿します。

default では `PermissionRequest` を設定しないでください。Codex は approval event ごとに
その hook を実行するため、helper が silent exit しても per-approval overhead があり、
`statusMessage` があると auto-approved request でも helper が skip する前に UI へ表示されます。
`Stop` も通常の完了 reply には不要です。`SessionStart` が transcript path を渡せない環境向けの
互換 fallback としてだけ残してください。

```toml
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "/path/to/dotfiles/scripts/codex-slack-notification"
timeout = 10
statusMessage = "Sending Codex Slack notification"
```

`PreToolUse`、`UserPromptSubmit`、成功した `PostToolUse` は Slack のノイズや Codex 内部 helper
prompt を避けるため default では投稿しません。secret 保管の詳細は
[`docs/secrets-local.md`](secrets-local.md#codex-slack-通知) にあります。

helper は `PostToolUse` failure payload にも対応していますが、この hook は opt-in 扱いに
してください。Codex は match した tool call の後に毎回 `PostToolUse` を走らせるため、
helper が silent exit しても per-tool の hook overhead があり、`statusMessage` を付けると
成功時にも Codex UI に出ます。

Slack message は compact view で読みやすくするため、default では full `cwd` と event
context を出しません。debug で必要な場合だけ `AGENT_NOTIFICATIONS_INCLUDE_CONTEXT=1` を
設定します。旧 `CODEX_SLACK_INCLUDE_CONTEXT=1` も fallback として受け付けます。

`slack-bot-token` と `slack-channel-id` が存在する場合、helper は `chat.postMessage`
を使い、agent notification state を次の local path に保存します。

```text
~/.local/state/dotfiles/agent-notifications/slack-threads.json
~/.local/state/dotfiles/agent-notifications/codex-dedupe.json
~/.local/state/dotfiles/agent-notifications/slack.log
```

新 state file が無い場合だけ、Rust command は旧
`~/.local/state/dotfiles/codex-slack-*` state を fallback として読み、以後の更新は新しい
`agent-notifications` path に書きます。

対応が必要な event や完了 event の thread reply には default で `<!channel>` を付けますが、
Slack thread 内に留めます。mention 文言は `AGENT_NOTIFICATIONS_REPLY_MENTION` で変更でき、
空文字にすると無効化できます。対象 event は comma-separated の
`AGENT_NOTIFICATIONS_REPLY_MENTION_EVENTS` で絞れます。reply を channel timeline に再掲したい
場合だけ `AGENT_NOTIFICATIONS_REPLY_BROADCAST=1` を設定します。旧 `CODEX_SLACK_*` 名も
fallback として受け付けます。

setup test で `channel_not_found` が返る場合、Bot User OAuth token は有効ですが、
bot から投稿先 channel が見えていません。その Slack app / bot user を対象 channel に
invite するか、public channel なら `chat:write.public` を追加するか、同じ workspace
installation の channel ID を使ってください。Incoming webhook fallback では通知自体は継続
できますが、local の `thread_ts` map は作成・更新できません。`slack-threads.json` が
空のままなら、thread mode はまだ `chat.postMessage` 経由で成功していません。

bot token と channel id が設定されている場合、helper はまず threaded Bot API posting を試します。
Bot API posting に失敗した場合、対応が必要な通知や完了通知は incoming webhook に fallback
します。thread parent event は webhook message では Codex と Slack thread の対応を維持できない
ため skip します。Bot / webhook の失敗は credential 値を書かずに
`~/.local/state/dotfiles/agent-notifications/slack.log` へ記録します。unthreaded な best-effort
通知より hard failure を優先したい場合だけ
`AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1` を設定します。

## Emacs

`tools.editor.emacs.enable = true` は GUI Emacs app を Homebrew で入れ、Emacs sync tooling、language/runtime helper、Tree-sitter grammar path を用意します。repo-managed config は Doom ではなく vanilla Emacs です。Meow を編集の中心に置き、package は Elpaca が管理し、初期 package set には doom-modeline、nerd-icons、ef-themes、Vertico/Marginalia/Consult/Orderless/Embark、Corfu/Cape/Eglot、Dired enhancement、Org visual package、Markdown/Nix mode、Popper、Dashboard、Magit が含まれます。

`sync emacs --apply` は `apps/emacs/config/{early-init,init}.el` を `${EMACSDIR:-~/.emacs.d}` に writable regular file として書きます。`sync emacs --adopt --item init` は runtime edit を repo-managed config に戻します。Elpaca の package checkout/build state は `${EMACSDIR:-~/.emacs.d}/elpaca` 配下の mutable state として残り、Emacs 起動時に作られます。

`tools.editor.emacs.bootstrap.enable = true` は legacy profile toggle として残し、現在は activation-time config sync にだけ関与します。`ultra` profile は Emacs sync を activation 中に有効化し、`pro` は Emacs を install するだけで setup は行いません。

`sync emacs --apply` 後の live package QA は `scripts/tests/emacs-package-qa-test.sh` で実行します。設定済み Emacs directory と実際の Elpaca package state を使いますが、書き込み先は一時 QA workspace だけです。

## Neovim と Goneovim

`tools.editor.neovim.enable = true` は Neovim を install します。`tools.editor.neovim.sync.enable = true` は `apps/neovim/` の repo-managed LazyVim config を wire し、その config が期待する file picker、LazyGit、Tree-sitter CLI、設定済み language server と formatter、document/image preview converter などの外部 runtime helper も install します。`ultra` はこの setup を有効化し、`pro` は無効のままにします。`tools.editor.goneovim.enable = true` は upstream Darwin release から Goneovim GUI を install します。Homebrew cask は Homebrew `neovim` に依存し、macOS Gatekeeper validation の理由で deprecated、かつ 2026-09-01 に disabled 予定のため、意図的に使いません。

`nix run .#sync` は個人用 editor setup の convenience app です。引数なしでは `sync emacs --apply` を実行し、その後 `sync neovim --apply` を実行します。追加引数は両方の editor sync engine に渡すため、`--check`、`--details`、`--diff` のような共通の inspection flag は両方に効きます。

## runtime override

- `HOME` は `nix run .#dotfiles -- sync shell ...`、`nix run .#dotfiles -- sync emacs ...`、`nix run .#dotfiles -- sync neovim ...`、`nix run .#dotfiles -- sync vscode ...` に必須です。また、repo default の user-scoped path が必要な command でも必須です。
- `DOTFILES_ROOT` は Rust CLI と shell wrapper の flake-root discovery を上書きします。
- `DOTFILES_PROFILE_DIRS` は colon 区切りの profile directory を shell profile discovery に先頭追加し、`/etc/profiles/per-user/$USER` と `$HOME/.nix-profile` より優先します。
- shell tooling は active user profile の bin を Home Manager session PATH に追加するため、non-interactive な zsh remote command でも user profile に install された tool を解決できます。
- `EMACSDIR` は `sync emacs` が対象にする writable Emacs config directory を上書きします。未指定時は `~/.emacs.d` です。1 command だけ変える場合は `--emacs-dir` を使います。
- `FACTS_DIR` / `SECRETS_DIR` の default は `~/.config/dotfiles` で、`FACTS` / `SECRETS` の default は `path:$FACTS_DIR` / `path:$SECRETS_DIR` です。
- `DARWIN_REBUILD_BIN` は `apply` が使う pin 済み `darwin-rebuild` path を上書きします。
- `DOTFILES_SYNC_VSCODE_BIN` は `sync vscode` engine path を上書きします。
- `XDG_CONFIG_HOME` と `XDG_STATE_HOME` は `sync neovim` の default runtime path に影響します。test では `--runtime-dir` と `--state-dir` で直接上書きできます。
- `VSCODE_CODE_BIN` は `code` CLI path を上書きし、`VSCODE_DATA_HOME`、`VSCODE_EXTENSIONS_DIR`、`VSCODE_CODE_RETRIES` は VS Code runtime location と retry behavior を上書きします。
- `SOPS_AGE_KEY_FILE` は bootstrap / doctor が使う age key location を上書きします。未指定時は `HOME` がある場合に `~/.config/sops/age/keys.txt` を default とします。

注意:

- `scripts/*.sh` は Rust CLI の薄い shell wrapper です。
- `gc` はまず repo 内の `/nix/store` 向き `result` / `result-*` symlink を外し、現在の Home Manager gcroot に置き換わった stale な legacy Home Manager profile link を削除対象にし、system / user / Home Manager / root profile の current 以外の generation を削除してから `nix store gc` を実行します。`--apply` なしでは plan と安全な dry-run check だけを行います。`--apply` ありでは default で current 以外をすべて削除します。直近 generation を残す場合は `--delete-older-than <age>`、profile history 削除を避ける場合は `--store-only` を使います。
- `sync neovim` は `apps/neovim` と `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` を比較し、`${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lazy-lock.json` が存在する場合はそれを実効 Lazy lock として扱います。
- `dotfiles-sync-vscode` は別 package として提供され、`dotfiles` が `sync vscode` をその binary に dispatch します。
- `ultra` profile は activation 中に `sync emacs --apply`、Neovim setup、`sync vscode --apply` を実行します。`pro` profile は editor tooling を install しますが、setup/sync は実行しません。Visual Studio Code.app 自体は手動 install 前提で、まだ無ければ activation は安全に skip します。インストール対象の extension ID は `apps/vscode/`（`_default/extensions.txt` と profile ごとの `extensions.txt`）にあります。

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
