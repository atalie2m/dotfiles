[English version](../secrets-local.md)

# ローカル secrets（sops + age）

このリポジトリは secret を repo 内に保存しません。代わりに、次の場所で local secrets input を提供してください。

- `~/.config/dotfiles/`（`secrets.nix` と `files/` を含む）

repo の default secrets input は意図的に inert です。`secrets.nix` が存在しない場合、secret の materialization は no-op になります。secret をこの repo に置かないでください。

## 最小レイアウト

```
~/.config/dotfiles/
├── facts.nix
├── secrets.nix
├── .sops.yaml
└── files/
    └── ai.env.sops.yaml
```

## クイックスタート

- まだ age key を持っていない場合は生成します。
  - `mkdir -p ~/.config/sops/age`
  - `age-keygen -o ~/.config/sops/age/keys.txt`
- 公開鍵を取得します。`age-keygen -y ~/.config/sops/age/keys.txt`
- `~/.config/dotfiles/.sops.yaml` を作成します（秘密鍵は commit しないでください）。

  ```yaml
  creation_rules:
    - path_regex: files/.*\.(yaml|json|env)$
      age: ["AGE_PUBLIC_KEY_HERE"]
  ```

- ファイルを暗号化します（例）。

  ```bash
  sops --encrypt --in-place ~/.config/dotfiles/files/ai.env.sops.yaml
  ```

## `secrets.nix` の例

```nix
{
  files = {
    aiEnv = {
      sopsFile = ./files/ai.env.sops.yaml;
      targetPath = ".config/dotfiles/ai.env";
      mode = "0600";
    };
  };
}
```

## メモ

- `sops-nix` は activation 時に strict permission 付きの file として secret を materialize します。
- 暗号化ファイルは disk 上に置けますが、平文は commit せず、Nix store にも書き込まないでください。
- materialize された file は、存在する場合にだけ shell config から source してください。

## Codex Slack 通知

`dotfiles agent-notify codex` は Slack credential を次の file から読みます。

```text
~/.config/dotfiles/files/agent-notifications/slack-bot-token
~/.config/dotfiles/files/agent-notifications/slack-channel-id
~/.config/dotfiles/files/agent-notifications/slack-webhook-url
```

この通知 runtime の stock Darwin profile toggle は
`tools.aiCodingAgent.codex.slackNotifications.enable` です。`pro` ではなく `ultra` で有効化します。

これらの file は local のまま、mode `0600` で管理してください。`slack-bot-token` には
`chat:write` 付きの `xoxb-...` Bot User OAuth token、`slack-channel-id` には投稿先の
Slack channel ID を置きます。`slack-webhook-url` は任意の fallback です。Codex lifecycle
hook からこの command を呼び、Slack credential 値は Codex config と Git に入れないでください。
旧 `~/.config/dotfiles/files/codex/slack-*` file も fallback credential として読みます。

実装は Rust の `dotfiles` control plane にあります。Codex 固有の hook / transcript parsing は
Codex adapter に閉じ込め、Slack 固有の整形、投稿、thread-state、fallback、error-log logic は
generic Slack sink が担当します。`scripts/codex-slack-notification` は
`dotfiles agent-notify codex` へ委譲する互換 shim です。

thread 対応には、その Slack app / bot user が投稿先 channel に投稿できる必要があります。
private channel では bot を invite してください。public channel では bot を invite するか、
app の bot scope に `chat:write.public` を追加して app を reinstall してください。

一時的な override として次も受け付けます。旧 `CODEX_SLACK_*` 名も同じ設定の fallback alias
として残します。

- `AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN_FILE` / `AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN`
- `AGENT_NOTIFICATIONS_SLACK_CHANNEL_ID_FILE` / `AGENT_NOTIFICATIONS_SLACK_CHANNEL_ID`
- `AGENT_NOTIFICATIONS_SLACK_WEBHOOK_FILE` / `AGENT_NOTIFICATIONS_SLACK_WEBHOOK_URL`
- `AGENT_NOTIFICATIONS_SLACK_THREAD_STATE_FILE`
- `AGENT_NOTIFICATIONS_DEDUPE_STATE_FILE`
- `AGENT_NOTIFICATIONS_ERROR_LOG_FILE`
- `AGENT_NOTIFICATIONS_INCLUDE_CONTEXT=1`
- `AGENT_NOTIFICATIONS_REPLY_MENTION`（default は `<!channel>`、空文字で無効化）
- `AGENT_NOTIFICATIONS_REPLY_MENTION_EVENTS`（comma-separated event names）
- `AGENT_NOTIFICATIONS_REPLY_BROADCAST=1`
- `AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1`

使い方:

1. Slack credential を local に保存します。

   ```bash
   mkdir -p ~/.config/dotfiles/files/agent-notifications
   printf '%s\n' 'xoxb-...' \
     > ~/.config/dotfiles/files/agent-notifications/slack-bot-token
   printf '%s\n' 'C0123456789' \
     > ~/.config/dotfiles/files/agent-notifications/slack-channel-id
   chmod 0600 \
     ~/.config/dotfiles/files/agent-notifications/slack-bot-token \
     ~/.config/dotfiles/files/agent-notifications/slack-channel-id
   ```

   任意の webhook fallback:

   ```bash
   printf '%s\n' 'https://hooks.slack.com/services/...' \
     > ~/.config/dotfiles/files/agent-notifications/slack-webhook-url
   chmod 0600 ~/.config/dotfiles/files/agent-notifications/slack-webhook-url
   ```

2. Codex lifecycle hook を `~/.codex/config.toml` に追加します。

   ```toml
   [features]
   codex_hooks = true

   # Codex thread title、Plan Mode 質問、approval wait、その transcript に紐づく
   # 完了 reply を transcript watcher で拾います。自動解決された request_user_input
   # と approval record は skip します。
   [[hooks.SessionStart]]
   [[hooks.SessionStart.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification --spawn-watcher"
   timeout = 5
   statusMessage = "Starting Codex Slack transcript watcher"
   ```

3. Slack に投稿せず payload だけ確認します。

   ```bash
   dotfiles agent-notify codex --dry-run <<'JSON'
   {
     "hook_event_name": "Stop",
     "cwd": "/path/to/project",
     "last_assistant_message": "Dry-run notification."
   }
   JSON
   ```

thread state は local の次の path に保存されます。

```text
~/.local/state/dotfiles/agent-notifications/slack-threads.json
~/.local/state/dotfiles/agent-notifications/codex-dedupe.json
~/.local/state/dotfiles/agent-notifications/slack.log
```

新 state file が無い場合だけ、command は旧
`~/.local/state/dotfiles/codex-slack-*` state を fallback として読み、以後の更新は新しい
`agent-notifications` path に書きます。

Slack が `channel_not_found` を返す場合は、その Slack app / bot user を投稿先 channel
に invite するか、Bot User OAuth token と同じ workspace installation の channel ID を
使ってください。Incoming webhook fallback では通知自体は継続できますが、local の
`thread_ts` map は更新できません。thread 対応には Bot User OAuth token による
`chat.postMessage` の成功が必要です。Bot / webhook の失敗は credential 値を書かずに
`slack.log` へ記録します。

`SessionStart` は transcript watcher を起動し、watcher が Codex の生成 `thread_name_updated`
title event から `Codex: <title> (<repo>)` 形式の Slack 親 message を作ります。title event が
無い場合は最初の user prompt から短い title を作り、それも無ければ `Codex: <repo>` に fallback
します。後から title event が来れば更新します。watcher は Plan Mode 質問、approval wait、
`task_complete` record もその transcript から投稿するため、同じ repo で Codex session が
並行していても「cwd の最新 session」推定に依存しません。Plan Mode 外で Codex が自動解決した
`request_user_input` record は無視します。`guardian_assessment` 由来の approval wait は最大
30 秒、Codex auto-review の判定を待ちます。agent が `approved` と判定した request は skip し、
自動承認されなかった request は Slack に投稿します。対応が必要な通知や完了通知は default で
`<!channel>` 付きの thread reply として投稿します。`AGENT_NOTIFICATIONS_REPLY_BROADCAST=1`
を設定しない限り、channel timeline には再掲しません。

default では `PermissionRequest` を設定しないでください。Codex は helper が payload を見て
skip する前に hook `statusMessage` を表示するため、自動解決された permission event でも
UI ノイズになります。推奨設定では transcript watcher が approval 通知を担当します。

bot token と channel id が設定されている場合、helper はまず threaded Bot API posting を試します。
Bot API posting に失敗した場合、対応が必要な通知や完了通知は incoming webhook に fallback
します。thread parent event は webhook message では Codex と Slack thread の対応を維持できない
ため skip します。unthreaded な best-effort 通知より hard failure を優先したい場合だけ
`AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1` を設定します。

4. 1 回だけ test notification を送ります。

   ```bash
   dotfiles agent-notify test
   ```
